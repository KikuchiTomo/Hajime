use super::display_attribute;
use super::edit_session;
use super::guard::guard;
use super::keyboard;
use super::langbar::{self, InputModeItem};
use super::launch;
use super::phonetic;
use super::timer;
use crate::filter;
use crate::key::{self, RawKey};
use crate::plan::CompositionPlan;
use ipc::windows::{pipe_name, EngineClient, Outcome, Pending};
use ipc::{
    EditOperation, ErrorCode, FieldContext, InputMode, Key, Rect, RequestBody, ResponseBody,
    SessionState, TextStyle,
};
use std::cell::RefCell;
use std::mem::ManuallyDrop;
use std::rc::Rc;
use std::time::{Duration, Instant};
use windows::Win32::Foundation::{LPARAM, RECT, WPARAM};
use windows::Win32::System::Com::{CoCreateInstance, CoTaskMemFree, CLSCTX_INPROC_SERVER};
use windows::Win32::System::Variant::{VariantClear, VARIANT, VT_I4, VT_UNKNOWN};
use windows::Win32::UI::TextServices::{
    CLSID_TF_CategoryMgr, IEnumTfDisplayAttributeInfo, ITfCategoryMgr, ITfCompartment,
    ITfCompartmentEventSink, ITfCompartmentEventSink_Impl, ITfCompartmentMgr, ITfComposition,
    ITfCompositionSink, ITfCompositionSink_Impl, ITfContext, ITfContextComposition,
    ITfDisplayAttributeInfo, ITfDisplayAttributeProvider, ITfDisplayAttributeProvider_Impl,
    ITfDocumentMgr, ITfInputScope, ITfInsertAtSelection, ITfKeyEventSink, ITfKeyEventSink_Impl,
    ITfKeystrokeMgr, ITfRange, ITfSource, ITfTextInputProcessor, ITfTextInputProcessorEx,
    ITfTextInputProcessorEx_Impl, ITfTextInputProcessor_Impl, ITfThreadMgr, ITfThreadMgrEventSink,
    ITfThreadMgrEventSink_Impl, GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION,
    GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, GUID_PROP_ATTRIBUTE, GUID_PROP_INPUTSCOPE,
    INSERT_TEXT_AT_SELECTION_FLAGS, IS_NUMERIC_PASSWORD, IS_NUMERIC_PIN, IS_PASSWORD, TF_AE_NONE,
    TF_ANCHOR_END, TF_ANCHOR_START, TF_CONVERSIONMODE_ALPHANUMERIC, TF_CONVERSIONMODE_FULLSHAPE,
    TF_CONVERSIONMODE_NATIVE, TF_DEFAULT_SELECTION, TF_ES_ASYNCDONTCARE, TF_ES_READ,
    TF_ES_READWRITE, TF_ES_SYNC, TF_IAS_QUERYONLY, TF_SELECTION, TF_SELECTIONSTYLE,
    TF_ST_CORRECTION,
};
use windows_core::{implement, ComObject, IUnknownImpl, Interface, Ref, Result, BOOL, GUID};

const RESPONSE_TIMEOUT: Duration = Duration::from_millis(ipc::timing::KEY_RESPONSE_MILLISECONDS);
/// 変換のキー(Space・変換)の返事を待つ時間．Zenzai で文全体を変換し直すので CPU では 100ms ほどかかる．
/// 待たずにタイマーで後から反映すると，変換が出るまで間が空き，タイマーの知らせが遅れるアプリでは更に遅れる
const CONVERSION_TIMEOUT: Duration =
    Duration::from_millis(ipc::timing::CONVERSION_RESPONSE_MILLISECONDS);
const RECONNECT_INTERVAL: Duration = Duration::from_millis(ipc::timing::RECONNECT_MILLISECONDS);
/// 返事の遅れがこれより長く続いたら，エンジンが固まったとみなす
const STALL_LIMIT: Duration = Duration::from_millis(ipc::timing::ENGINE_STALL_MILLISECONDS);

thread_local! {
    static ACTIVE: RefCell<Option<ComObject<TextService>>> = const { RefCell::new(None) };
}

#[implement(
    ITfTextInputProcessorEx,
    ITfTextInputProcessor,
    ITfKeyEventSink,
    ITfThreadMgrEventSink,
    ITfCompositionSink,
    ITfCompartmentEventSink,
    ITfDisplayAttributeProvider
)]
#[derive(Default)]
pub struct TextService {
    inner: RefCell<Inner>,
}

#[derive(Default)]
struct Inner {
    thread_mgr: Option<ITfThreadMgr>,
    client_id: u32,
    sink_cookie: Option<u32>,
    mode_cookie: Option<(ITfCompartment, u32)>,
    engine: Option<Rc<EngineClient>>,
    session: Option<u32>,
    state: Option<SessionState>,
    last_open_attempt: Option<Instant>,
    composition: Option<ITfComposition>,
    late: Vec<Pending>,
    /// 返事の遅れが始まった時刻(late が空になったら None)
    late_since: Option<Instant>,
    atoms: Vec<(TextStyle, u32)>,
    caret: Option<Rect>,
    timer: usize,
    application_id: Option<String>,
    mode_item: Option<ComObject<InputModeItem>>,
}

impl ITfTextInputProcessor_Impl for TextService_Impl {
    fn Activate(&self, ptim: Ref<ITfThreadMgr>, tid: u32) -> Result<()> {
        self.ActivateEx(ptim, tid, 0)
    }

    fn Deactivate(&self) -> Result<()> {
        guard(|| {
            self.finish_composition(None);
            self.cancel_timer();
            timer::close();
            if let Some((compartment, cookie)) = self.inner.borrow_mut().mode_cookie.take() {
                if let Ok(source) = compartment.cast::<ITfSource>() {
                    let _ = unsafe { source.UnadviseSink(cookie) };
                }
            }
            let (thread_mgr, client_id, cookie, engine, session, mode_item) = {
                let mut inner = self.inner.borrow_mut();
                (
                    inner.thread_mgr.take(),
                    inner.client_id,
                    inner.sink_cookie.take(),
                    inner.engine.take(),
                    inner.session.take(),
                    inner.mode_item.take(),
                )
            };
            if let (Some(engine), Some(session)) = (engine, session) {
                let _ = engine.send(RequestBody::CloseSession { session });
            }
            if let Some(thread_mgr) = thread_mgr {
                if let Some(item) = mode_item {
                    langbar::remove(&thread_mgr, &item.to_interface());
                }
                if let Ok(keystrokes) = thread_mgr.cast::<ITfKeystrokeMgr>() {
                    let _ = unsafe { keystrokes.UnadviseKeyEventSink(client_id) };
                }
                if let (Ok(source), Some(cookie)) = (thread_mgr.cast::<ITfSource>(), cookie) {
                    let _ = unsafe { source.UnadviseSink(cookie) };
                }
            }
            *self.inner.borrow_mut() = Inner::default();
            ACTIVE.with(|active| active.borrow_mut().take());
            Ok(())
        })
    }
}

impl ITfTextInputProcessorEx_Impl for TextService_Impl {
    fn ActivateEx(&self, ptim: Ref<ITfThreadMgr>, tid: u32, _dwflags: u32) -> Result<()> {
        guard(|| {
            let thread_mgr = ptim.ok()?.clone();
            let key_sink: ITfKeyEventSink = self.to_interface();
            unsafe {
                thread_mgr
                    .cast::<ITfKeystrokeMgr>()?
                    .AdviseKeyEventSink(tid, &key_sink, true)?
            };
            let focus_sink: ITfThreadMgrEventSink = self.to_interface();
            let cookie = unsafe {
                thread_mgr
                    .cast::<ITfSource>()?
                    .AdviseSink(&ITfThreadMgrEventSink::IID, &focus_sink)?
            };
            let atoms = register_attributes().unwrap_or_default();
            let mode_cookie = self.watch_mode(&thread_mgr).ok();
            let engine = pipe_name("engine")
                .ok()
                .and_then(|name| EngineClient::start(name).ok())
                .map(Rc::new);
            let application_id = std::env::current_exe().ok().and_then(|path| {
                path.file_name()
                    .map(|name| name.to_string_lossy().to_lowercase())
            });
            let mode_item = ComObject::new(InputModeItem::new(Box::new(MenuActions)));
            let mode_item = langbar::add(&thread_mgr, &mode_item.to_interface())
                .ok()
                .map(|()| mode_item);
            {
                let mut inner = self.inner.borrow_mut();
                inner.mode_item = mode_item;
                inner.thread_mgr = Some(thread_mgr);
                inner.client_id = tid;
                inner.sink_cookie = Some(cookie);
                inner.mode_cookie = mode_cookie;
                inner.atoms = atoms;
                inner.engine = engine;
                inner.application_id = application_id;
            }
            ACTIVE.with(|active| *active.borrow_mut() = Some(self.to_object()));
            self.ensure_session();
            Ok(())
        })
    }
}

fn register_attributes() -> Result<Vec<(TextStyle, u32)>> {
    let categories: ITfCategoryMgr =
        unsafe { CoCreateInstance(&CLSID_TF_CategoryMgr, None, CLSCTX_INPROC_SERVER)? };
    display_attribute::STYLES
        .into_iter()
        .map(|style| {
            let atom = unsafe { categories.RegisterGUID(&display_attribute::guid(style))? };
            Ok((style, atom))
        })
        .collect()
}

impl ITfKeyEventSink_Impl for TextService_Impl {
    fn OnSetFocus(&self, _fforeground: BOOL) -> Result<()> {
        Ok(())
    }

    fn OnTestKeyDown(&self, _pic: Ref<ITfContext>, wparam: WPARAM, lparam: LPARAM) -> Result<BOOL> {
        guard(|| Ok(self.wants(wparam, lparam).is_some().into()))
    }

    fn OnTestKeyUp(&self, _pic: Ref<ITfContext>, _wparam: WPARAM, _lparam: LPARAM) -> Result<BOOL> {
        Ok(false.into())
    }

    fn OnKeyDown(&self, pic: Ref<ITfContext>, wparam: WPARAM, lparam: LPARAM) -> Result<BOOL> {
        guard(|| {
            let Some(input) = self.wants(wparam, lparam) else {
                return Ok(false.into());
            };
            let Ok(context) = pic.ok() else {
                return Ok(false.into());
            };
            // 前のキーの返事が遅れていたら，少し待って送った順に反映してから，このキーを送る
            self.apply_late(context, RESPONSE_TIMEOUT);
            let field = self.field_context(context);
            let timeout = if matches!(input.key, Key::Space | Key::Henkan) {
                CONVERSION_TIMEOUT
            } else {
                RESPONSE_TIMEOUT
            };
            let (engine, session) = {
                let inner = self.inner.borrow();
                (inner.engine.clone(), inner.session)
            };
            let (Some(engine), Some(session)) = (engine, session) else {
                return Ok(false.into());
            };
            let pending = engine.send(RequestBody::Key {
                session,
                input,
                context: field,
            });
            if !self.inner.borrow().late.is_empty() {
                // 前のキーの返事がまだ届いていない．このキーの返事を先に反映すると順が入れ替わるので，前の返事のあとに反映する
                return Ok(self.defer(pending).into());
            }
            match pending.outcome(timeout) {
                Outcome::Reply(body) => Ok(self.apply_response(context, body).into()),
                Outcome::TimedOut => {
                    // エンジンが固まっていたらキーを奪わずアプリに渡す(入力が消えないように)
                    if !self.defer(pending) {
                        return Ok(false.into());
                    }
                    Ok(true.into())
                }
                Outcome::Unavailable => {
                    self.forget_session();
                    Ok(false.into())
                }
            }
        })
    }

    fn OnKeyUp(&self, _pic: Ref<ITfContext>, _wparam: WPARAM, _lparam: LPARAM) -> Result<BOOL> {
        Ok(false.into())
    }

    fn OnPreservedKey(&self, _pic: Ref<ITfContext>, _rguid: *const GUID) -> Result<BOOL> {
        Ok(false.into())
    }
}

impl TextService_Impl {
    fn wants(&self, wparam: WPARAM, lparam: LPARAM) -> Option<ipc::KeyInput> {
        let layout = self
            .inner
            .borrow()
            .state
            .as_ref()
            .and_then(|state| state.keyboard_layout.clone());
        let raw: RawKey = keyboard::read(wparam, lparam)?.with_layout(layout.as_deref());
        if key::is_modifier_only(raw.vk) {
            return None;
        }
        let input = key::translate(&raw)?;
        if self.inner.borrow().state.is_none() && self.inner.borrow().timer == 0 {
            self.schedule_timer(Some(0));
        }
        // 返事が遅れているあいだは，入力の状態(組み立て中か)が古いので，キーをすべてエンジンに送って順を保つ
        // (古い状態で決めると，組み立て中の Enter をアプリに渡してしまう)
        let late = !self.inner.borrow().late.is_empty();
        (late || filter::consumes(self.inner.borrow().state.as_ref(), &input)).then_some(input)
    }

    /// 間に合わなかった返事をあとで反映するために残す．遅れが長く続いた・溜まりすぎたときは，
    /// エンジンが固まったとみなして残さず，つなぎ直す(false を返す)
    fn defer(&self, pending: Pending) -> bool {
        let stalled = {
            let mut inner = self.inner.borrow_mut();
            let since = *inner.late_since.get_or_insert_with(Instant::now);
            since.elapsed() >= STALL_LIMIT || inner.late.len() >= ipc::timing::MAXIMUM_LATE_KEYS
        };
        if stalled {
            self.restart_engine();
            return false;
        }
        self.inner.borrow_mut().late.push(pending);
        self.schedule_timer(Some(RESPONSE_TIMEOUT.as_millis() as u32));
        true
    }

    /// 固まったエンジンへの接続を捨てて，新しく作り直す．届かなかった返事は捨てる
    fn restart_engine(&self) {
        let engine = pipe_name("engine")
            .ok()
            .and_then(|name| EngineClient::start(name).ok())
            .map(Rc::new);
        {
            let mut inner = self.inner.borrow_mut();
            inner.late.clear();
            inner.late_since = None;
            inner.engine = engine;
        }
        self.forget_session();
    }

    fn forget_session(&self) {
        let mut inner = self.inner.borrow_mut();
        inner.session = None;
        inner.state = None;
        inner.last_open_attempt = None;
    }

    fn ensure_session(&self) {
        let engine = {
            let mut inner = self.inner.borrow_mut();
            if inner.session.is_some() {
                return;
            }
            if inner
                .last_open_attempt
                .is_some_and(|last| last.elapsed() < RECONNECT_INTERVAL)
            {
                return;
            }
            inner.last_open_attempt = Some(Instant::now());
            inner.engine.clone()
        };
        let Some(engine) = engine else { return };
        if let Some(ResponseBody::SessionOpened { session, state }) =
            engine.send(RequestBody::OpenSession).wait(RESPONSE_TIMEOUT)
        {
            let mode = state.mode;
            {
                let mut inner = self.inner.borrow_mut();
                inner.session = Some(session);
                inner.state = Some(state);
            }
            self.show_mode(mode);
        }
    }

    fn field_context(&self, context: &ITfContext) -> FieldContext {
        let (application_id, caret, client_id, wanted) = {
            let inner = self.inner.borrow();
            (
                inner.application_id.clone(),
                inner.caret.clone(),
                inner.client_id,
                inner
                    .state
                    .as_ref()
                    .and_then(|state| state.preceding_text_length),
            )
        };
        let field = read_field(context, client_id, wanted.unwrap_or(0));
        FieldContext {
            application_id,
            is_secure: field.is_secure,
            preceding_text: field.preceding_text,
            caret,
        }
    }

    fn apply_response(&self, context: &ITfContext, body: ResponseBody) -> bool {
        match body {
            ResponseBody::Edit {
                handled,
                operations,
                state,
            } => {
                let wake = state.wake_after_milliseconds;
                let mode = state.mode;
                self.inner.borrow_mut().state = Some(state);
                self.show_mode(mode);
                let applied = self.apply_operations(context, operations);
                self.schedule_timer(wake);
                handled && applied
            }
            ResponseBody::Error {
                code: ErrorCode::UnknownSession,
            } => {
                self.forget_session();
                false
            }
            _ => false,
        }
    }

    /// 遅れた返事を送った順に反映する．まだ届いていない返事があれば，それとそのあとの返事は残す(順を入れ替えない)．
    /// 先頭から wait の時間まで待つ(Duration::ZERO なら待たない)
    fn apply_late(&self, context: &ITfContext, wait: Duration) {
        let late = std::mem::take(&mut self.inner.borrow_mut().late);
        let deadline = Instant::now() + wait;
        let (ready, waiting) = crate::late::drain_in_order(late, |pending| {
            match pending.outcome(deadline.saturating_duration_since(Instant::now())) {
                Outcome::Reply(body) => crate::late::Poll::Ready(body),
                // エンジンとの接続が切れた返事は捨てる(つなぎ直しは別に行う)
                Outcome::Unavailable => crate::late::Poll::Gone,
                Outcome::TimedOut => crate::late::Poll::Waiting,
            }
        });
        for body in ready {
            self.apply_response(context, body);
        }
        let mut inner = self.inner.borrow_mut();
        if waiting.is_empty() {
            inner.late_since = None;
        }
        inner.late.extend(waiting);
    }

    /// 操作を文書に反映する．再変換を頼まれたのに始められなかった(選んでいる文字が無い)ときは false
    fn apply_operations(&self, context: &ITfContext, operations: Vec<EditOperation>) -> bool {
        let mut edits = Vec::new();
        let mut reconversion = None;
        for operation in operations {
            match operation {
                EditOperation::SelectMode { mode } => self.select_mode(mode),
                EditOperation::RequestReconversion { maximum_length } => {
                    reconversion = Some(maximum_length)
                }
                other => edits.push(other),
            }
        }
        let reconverted =
            reconversion.is_none_or(|maximum_length| self.reconvert(context, maximum_length));
        if edits.is_empty() {
            return reconverted;
        }
        let client_id = self.inner.borrow().client_id;
        let service = self.to_object();
        let sink: ITfCompositionSink = self.to_interface();
        let target = context.clone();
        let _ = edit_session::request(
            context,
            client_id,
            TF_ES_ASYNCDONTCARE | TF_ES_READWRITE,
            move |ec| {
                let (mut composition, atoms) = {
                    let inner = service.inner.borrow();
                    (inner.composition.clone(), inner.atoms.clone())
                };
                let mut result = Ok(());
                for edit in edits {
                    result = match edit {
                        EditOperation::Commit { text } => {
                            commit(ec, &target, &mut composition, &text)
                        }
                        EditOperation::SetComposition { segments } => show(
                            ec,
                            &target,
                            &mut composition,
                            &CompositionPlan::new(&segments),
                            &atoms,
                            &sink,
                        ),
                        EditOperation::SelectMode { .. }
                        | EditOperation::RequestReconversion { .. } => Ok(()),
                    };
                    if result.is_err() {
                        break;
                    }
                }
                let caret = composition
                    .as_ref()
                    .and_then(|current| text_rect(ec, &target, current).ok());
                let (engine, session) = {
                    let mut inner = service.inner.borrow_mut();
                    inner.composition = composition;
                    if caret.is_some() {
                        inner.caret = caret.clone();
                    }
                    (inner.engine.clone(), inner.session)
                };
                if let (Some(engine), Some(session), Some(rect)) = (engine, session, caret) {
                    let _ = engine.send(RequestBody::Caret { session, rect });
                }
                result
            },
        );
        reconverted
    }

    fn select_mode(&self, mode: InputMode) {
        let (thread_mgr, client_id) = {
            let inner = self.inner.borrow();
            (inner.thread_mgr.clone(), inner.client_id)
        };
        let Some(thread_mgr) = thread_mgr else { return };
        let open = match mode {
            InputMode::Japanese => 1,
            InputMode::Direct => 0,
        };
        let Ok(compartments) = thread_mgr.cast::<ITfCompartmentMgr>() else {
            return;
        };
        unsafe {
            if let Ok(compartment) =
                compartments.GetCompartment(&GUID_COMPARTMENT_KEYBOARD_OPENCLOSE)
            {
                let _ = compartment.SetValue(client_id, &variant_i32(open));
            }
        }
    }

    /// タスクバーの「あ」「A」と，入力モードの compartment(タッチキーボードなどが読む)を今のモードに合わせる
    fn show_mode(&self, mode: InputMode) {
        let (item, thread_mgr, client_id) = {
            let inner = self.inner.borrow();
            (
                inner.mode_item.clone(),
                inner.thread_mgr.clone(),
                inner.client_id,
            )
        };
        if let Some(item) = item {
            item.set_mode(Some(mode));
        }
        let Some(compartments) =
            thread_mgr.and_then(|manager| manager.cast::<ITfCompartmentMgr>().ok())
        else {
            return;
        };
        let conversion = match mode {
            InputMode::Japanese => TF_CONVERSIONMODE_NATIVE | TF_CONVERSIONMODE_FULLSHAPE,
            InputMode::Direct => TF_CONVERSIONMODE_ALPHANUMERIC,
        };
        unsafe {
            if let Ok(compartment) =
                compartments.GetCompartment(&GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION)
            {
                let _ = compartment.SetValue(client_id, &variant_i32(conversion as i32));
            }
        }
    }

    fn engine_request(&self, body: RequestBody) -> Option<ResponseBody> {
        let engine = self.inner.borrow().engine.clone()?;
        engine.send(body).wait(RESPONSE_TIMEOUT)
    }

    fn finish_composition(&self, context: Option<&ITfContext>) {
        let (composition, engine, session) = {
            let inner = self.inner.borrow();
            (
                inner.composition.clone(),
                inner.engine.clone(),
                inner.session,
            )
        };
        let (Some(engine), Some(session)) = (engine, session) else {
            return;
        };
        let body = engine
            .send(RequestBody::Deactivate { session })
            .wait(RESPONSE_TIMEOUT);
        let target = context.cloned().or_else(|| {
            composition.as_ref().and_then(|current| unsafe {
                current.GetRange().and_then(|range| range.GetContext()).ok()
            })
        });
        match (body, target) {
            (Some(body), Some(target)) => {
                self.apply_response(&target, body);
            }
            (Some(ResponseBody::Edit { state, .. }), None) => {
                self.inner.borrow_mut().state = Some(state)
            }
            _ => {}
        }
    }

    fn schedule_timer(&self, milliseconds: Option<u32>) {
        self.cancel_timer();
        let Some(milliseconds) = milliseconds else {
            return;
        };
        timer::schedule(milliseconds, on_timer);
        self.inner.borrow_mut().timer = 1;
    }

    fn cancel_timer(&self) {
        let timer = std::mem::take(&mut self.inner.borrow_mut().timer);
        if timer != 0 {
            timer::cancel();
        }
    }

    fn on_wake(&self) {
        self.cancel_timer();
        if self.inner.borrow().session.is_none() {
            self.ensure_session();
            return;
        }
        let Some((context, engine, session)) = self.focused_context() else {
            return;
        };
        self.apply_late(&context, Duration::ZERO);
        let stalled = self
            .inner
            .borrow()
            .late_since
            .is_some_and(|since| since.elapsed() >= STALL_LIMIT);
        if stalled {
            self.restart_engine();
            return;
        }
        if !self.inner.borrow().late.is_empty() {
            self.schedule_timer(Some(RESPONSE_TIMEOUT.as_millis() as u32));
            return;
        }
        let wants_wake = self
            .inner
            .borrow()
            .state
            .as_ref()
            .is_some_and(|state| state.wake_after_milliseconds.is_some());
        if !wants_wake {
            return;
        }
        self.send_edit(&context, engine, session, |session, context| {
            RequestBody::Wake { session, context }
        });
    }

    /// 入力メニューの「手書き入力」．キーの「手書き入力」と同じく，組み立て中の文字を確定してから窓を開く(エンジンが edit で返す)
    fn open_handwriting(&self) {
        if self.inner.borrow().session.is_none() {
            self.ensure_session();
        }
        let Some((context, engine, session)) = self.focused_context() else {
            return;
        };
        self.send_edit(&context, engine, session, |session, context| {
            RequestBody::OpenHandwriting { session, context }
        });
    }

    /// 再変換．入力先で選んでいる文字(maximum_length 文字まで)を読み，Windows の日本語の解析で読みを求めて，エンジンに変換し直してもらう．
    /// 選んでいない・秘密の欄・長すぎる・読みを求められないときは何もせず false
    fn reconvert(&self, context: &ITfContext, maximum_length: u32) -> bool {
        let client_id = self.inner.borrow().client_id;
        let Some(text) = read_selection(context, client_id, maximum_length) else {
            return false;
        };
        let Some(reading) = phonetic::reading(&text) else {
            return false;
        };
        let reading = Some(reading);
        let (engine, session) = {
            let inner = self.inner.borrow();
            (inner.engine.clone(), inner.session)
        };
        self.send_edit(context, engine, session, |session, context| {
            RequestBody::Reconvert {
                session,
                text,
                reading,
                context,
            }
        });
        true
    }

    /// 入力中の文字の文脈(組み立て中ならそこ，無ければ注目している文書)と，エンジン・セッション
    fn focused_context(&self) -> Option<(ITfContext, Option<Rc<EngineClient>>, Option<u32>)> {
        let (thread_mgr, composition, engine, session) = {
            let inner = self.inner.borrow();
            (
                inner.thread_mgr.clone(),
                inner.composition.clone(),
                inner.engine.clone(),
                inner.session,
            )
        };
        let context = composition
            .as_ref()
            .and_then(|current| unsafe {
                current.GetRange().and_then(|range| range.GetContext()).ok()
            })
            .or_else(|| {
                thread_mgr.and_then(|manager| unsafe {
                    manager
                        .GetFocus()
                        .and_then(|focus: ITfDocumentMgr| focus.GetTop())
                        .ok()
                })
            })?;
        Some((context, engine, session))
    }

    /// edit を返す要求を送り，届いた edit を文書に反映する．間に合わなかった応答は捨てずにあとで反映する(キーと同じ)
    fn send_edit(
        &self,
        context: &ITfContext,
        engine: Option<Rc<EngineClient>>,
        session: Option<u32>,
        make: impl FnOnce(u32, FieldContext) -> RequestBody,
    ) {
        let (Some(engine), Some(session)) = (engine, session) else {
            return;
        };
        let field = self.field_context(context);
        let pending = engine.send(make(session, field));
        match pending.outcome(RESPONSE_TIMEOUT) {
            Outcome::Reply(body) => {
                self.apply_response(context, body);
            }
            Outcome::TimedOut => {
                self.defer(pending);
            }
            Outcome::Unavailable => self.forget_session(),
        }
    }
}

/// 入力メニューで選んだことを，このスレッドで動いている文字入力のサービスに頼む
struct MenuActions;

impl MenuActions {
    fn active() -> Option<ComObject<TextService>> {
        ACTIVE.with(|active| active.borrow().clone())
    }
}

impl langbar::Actions for MenuActions {
    fn menu_settings(&self) -> Option<ipc::SettingsSnapshot> {
        match Self::active()?.engine_request(RequestBody::ReadSettings)? {
            ResponseBody::Settings { settings } => Some(settings),
            _ => None,
        }
    }

    fn run(&self, command: ipc::MenuCommand) {
        let opens_settings = command == ipc::MenuCommand::OpenSettings;
        let answered = Self::active()
            .and_then(|service| service.engine_request(RequestBody::Menu { command }))
            .is_some();
        // エンジンが動いていなくても設定の画面は開けるようにする(設定の画面がエンジンを起動し直す)
        if !answered && opens_settings {
            let _ = launch::start(launch::SETTINGS_FILE);
        }
    }

    fn connected(&self) -> bool {
        Self::active().is_some_and(|service| service.inner.borrow().session.is_some())
    }

    fn open_handwriting(&self) {
        if let Some(service) = Self::active() {
            service.open_handwriting();
        }
    }

    fn toggle_mode(&self) {
        let Some(service) = Self::active() else {
            return;
        };
        let current = service
            .inner
            .borrow()
            .state
            .as_ref()
            .map(|state| state.mode);
        let next = match current {
            Some(InputMode::Japanese) => InputMode::Direct,
            _ => InputMode::Japanese,
        };
        service.select_mode(next);
    }
}

/// 時計が鳴った(timer の窓の手続きが panic を受け止める)
fn on_timer() {
    let service = ACTIVE.with(|active| active.borrow().clone());
    if let Some(service) = service {
        service.inner.borrow_mut().timer = 0;
        service.on_wake();
    }
}

impl ITfThreadMgrEventSink_Impl for TextService_Impl {
    fn OnInitDocumentMgr(&self, _pdim: Ref<ITfDocumentMgr>) -> Result<()> {
        Ok(())
    }

    fn OnUninitDocumentMgr(&self, _pdim: Ref<ITfDocumentMgr>) -> Result<()> {
        Ok(())
    }

    fn OnSetFocus(
        &self,
        _pdimfocus: Ref<ITfDocumentMgr>,
        _pdimprevfocus: Ref<ITfDocumentMgr>,
    ) -> Result<()> {
        guard(|| {
            self.finish_composition(None);
            self.cancel_timer();
            Ok(())
        })
    }

    fn OnPushContext(&self, _pic: Ref<ITfContext>) -> Result<()> {
        Ok(())
    }

    fn OnPopContext(&self, _pic: Ref<ITfContext>) -> Result<()> {
        Ok(())
    }
}

impl ITfCompartmentEventSink_Impl for TextService_Impl {
    fn OnChange(&self, rguid: *const GUID) -> Result<()> {
        guard(|| {
            if rguid.is_null() || unsafe { *rguid } != GUID_COMPARTMENT_KEYBOARD_OPENCLOSE {
                return Ok(());
            }
            let Some(mode) = self.compartment_mode() else {
                return Ok(());
            };
            let (engine, session, current, thread_mgr) = {
                let inner = self.inner.borrow();
                (
                    inner.engine.clone(),
                    inner.session,
                    inner.state.as_ref().map(|state| state.mode),
                    inner.thread_mgr.clone(),
                )
            };
            if current == Some(mode) {
                return Ok(());
            }
            let (Some(engine), Some(session)) = (engine, session) else {
                return Ok(());
            };
            let body = engine
                .send(RequestBody::SetMode { session, mode })
                .wait(RESPONSE_TIMEOUT);
            let context = thread_mgr.and_then(|manager| unsafe {
                manager
                    .GetFocus()
                    .and_then(|focus: ITfDocumentMgr| focus.GetTop())
                    .ok()
            });
            if let (Some(body), Some(context)) = (body, context) {
                self.apply_response(&context, body);
            }
            Ok(())
        })
    }
}

impl TextService_Impl {
    fn watch_mode(&self, thread_mgr: &ITfThreadMgr) -> Result<(ITfCompartment, u32)> {
        let compartment = unsafe {
            thread_mgr
                .cast::<ITfCompartmentMgr>()?
                .GetCompartment(&GUID_COMPARTMENT_KEYBOARD_OPENCLOSE)?
        };
        let sink: ITfCompartmentEventSink = self.to_interface();
        let cookie = unsafe {
            compartment
                .cast::<ITfSource>()?
                .AdviseSink(&ITfCompartmentEventSink::IID, &sink)?
        };
        Ok((compartment, cookie))
    }

    fn compartment_mode(&self) -> Option<InputMode> {
        let compartment = self
            .inner
            .borrow()
            .mode_cookie
            .as_ref()
            .map(|(compartment, _)| compartment.clone())?;
        let mut value = unsafe { compartment.GetValue().ok()? };
        let open = unsafe {
            let inner = &value.Anonymous.Anonymous;
            (inner.vt == VT_I4).then(|| inner.Anonymous.lVal != 0)
        };
        let _ = unsafe { VariantClear(&mut value) };
        open.map(|open| {
            if open {
                InputMode::Japanese
            } else {
                InputMode::Direct
            }
        })
    }
}

impl ITfCompositionSink_Impl for TextService_Impl {
    fn OnCompositionTerminated(
        &self,
        _ecwrite: u32,
        _pcomposition: Ref<ITfComposition>,
    ) -> Result<()> {
        guard(|| {
            let (engine, session) = {
                let mut inner = self.inner.borrow_mut();
                inner.composition = None;
                (inner.engine.clone(), inner.session)
            };
            self.cancel_timer();
            if let (Some(engine), Some(session)) = (engine, session) {
                if let Some(ResponseBody::Edit { state, .. }) = engine
                    .send(RequestBody::Deactivate { session })
                    .wait(RESPONSE_TIMEOUT)
                {
                    self.inner.borrow_mut().state = Some(state);
                }
            }
            Ok(())
        })
    }
}

impl ITfDisplayAttributeProvider_Impl for TextService_Impl {
    fn EnumDisplayAttributeInfo(&self) -> Result<IEnumTfDisplayAttributeInfo> {
        guard(|| Ok(display_attribute::enumerate()))
    }

    fn GetDisplayAttributeInfo(&self, guid: *const GUID) -> Result<ITfDisplayAttributeInfo> {
        guard(|| {
            if guid.is_null() {
                return Err(windows::Win32::Foundation::E_INVALIDARG.into());
            }
            display_attribute::info(unsafe { &*guid })
        })
    }
}

fn commit(
    ec: u32,
    context: &ITfContext,
    composition: &mut Option<ITfComposition>,
    text: &str,
) -> Result<()> {
    let text: Vec<u16> = text.encode_utf16().collect();
    unsafe {
        if let Some(current) = composition.take() {
            let range = current.GetRange()?;
            range.SetText(ec, 0, &text)?;
            context
                .GetProperty(&GUID_PROP_ATTRIBUTE)?
                .Clear(ec, &range)?;
            range.Collapse(ec, TF_ANCHOR_END)?;
            set_selection(ec, context, &range)?;
            current.EndComposition(ec)?;
        } else {
            let range = context
                .cast::<ITfInsertAtSelection>()?
                .InsertTextAtSelection(ec, INSERT_TEXT_AT_SELECTION_FLAGS(0), &text)?;
            range.Collapse(ec, TF_ANCHOR_END)?;
            set_selection(ec, context, &range)?;
        }
    }
    Ok(())
}

fn show(
    ec: u32,
    context: &ITfContext,
    composition: &mut Option<ITfComposition>,
    plan: &CompositionPlan,
    atoms: &[(TextStyle, u32)],
    sink: &ITfCompositionSink,
) -> Result<()> {
    unsafe {
        if plan.is_empty() {
            if let Some(current) = composition.take() {
                let range = current.GetRange()?;
                range.SetText(ec, 0, &[])?;
                current.EndComposition(ec)?;
            }
            return Ok(());
        }
        let current = match composition {
            Some(current) => current.clone(),
            None => {
                let range = context
                    .cast::<ITfInsertAtSelection>()?
                    .InsertTextAtSelection(ec, TF_IAS_QUERYONLY, &[])?;
                let started = context
                    .cast::<ITfContextComposition>()?
                    .StartComposition(ec, &range, sink)?;
                *composition = Some(started.clone());
                started
            }
        };
        let range = current.GetRange()?;
        range.SetText(ec, TF_ST_CORRECTION, &plan.text)?;
        let property = context.GetProperty(&GUID_PROP_ATTRIBUTE)?;
        property.Clear(ec, &range)?;
        for styled in &plan.ranges {
            let Some((_, atom)) = atoms.iter().find(|(style, _)| *style == styled.style) else {
                continue;
            };
            let part: ITfRange = range.Clone()?;
            part.Collapse(ec, TF_ANCHOR_START)?;
            let mut moved = 0;
            part.ShiftEnd(
                ec,
                styled.start + styled.length,
                &mut moved,
                std::ptr::null(),
            )?;
            part.ShiftStart(ec, styled.start, &mut moved, std::ptr::null())?;
            property.SetValue(ec, &part, &variant_i32(*atom as i32))?;
        }
        let caret: ITfRange = range.Clone()?;
        caret.Collapse(ec, TF_ANCHOR_END)?;
        set_selection(ec, context, &caret)?;
    }
    Ok(())
}

fn set_selection(ec: u32, context: &ITfContext, range: &ITfRange) -> Result<()> {
    let selection = TF_SELECTION {
        range: ManuallyDrop::new(Some(range.clone())),
        style: TF_SELECTIONSTYLE {
            ase: TF_AE_NONE,
            fInterimChar: false.into(),
        },
    };
    let result = unsafe { context.SetSelection(ec, std::slice::from_ref(&selection)) };
    drop(ManuallyDrop::into_inner(selection.range));
    result
}

fn text_rect(ec: u32, context: &ITfContext, composition: &ITfComposition) -> Result<Rect> {
    let mut rect = RECT::default();
    let mut clipped = BOOL::default();
    unsafe {
        let range = composition.GetRange()?;
        context
            .GetActiveView()?
            .GetTextExt(ec, &range, &mut rect, &mut clipped)?;
    }
    Ok(Rect {
        x: rect.left,
        y: rect.top,
        width: rect.right - rect.left,
        height: rect.bottom - rect.top,
    })
}

/// 入力欄について読んだこと．入力位置の前の文字列はログに出さない
#[derive(Default)]
struct FieldReading {
    is_secure: bool,
    preceding_text: Option<String>,
}

/// 入力欄が秘密の欄か(パスワードなど)と，入力位置の前の文字列(最大 length 文字．UTF-16 で数える)を 1 回の読み取りで読む．
/// 秘密の欄では前の文字列を読まない
fn read_field(context: &ITfContext, client_id: u32, length: u32) -> FieldReading {
    let reading = Rc::new(RefCell::new(FieldReading::default()));
    let output = reading.clone();
    let target = context.clone();
    let _ = edit_session::request(context, client_id, TF_ES_SYNC | TF_ES_READ, move |ec| {
        let Some(selection) = selection_start(ec, &target)? else {
            return Ok(());
        };
        let secure = input_scope_is_secure(ec, &target, &selection)?;
        let mut field = output.borrow_mut();
        field.is_secure = secure;
        if !secure && length > 0 {
            field.preceding_text = preceding_text(ec, &selection, length).ok().flatten();
        }
        Ok(())
    });
    reading.take()
}

/// 入力先で選んでいる文字．選んでいない・秘密の欄・maximum_length(UTF-16 で数える)より長いときは None
fn read_selection(context: &ITfContext, client_id: u32, maximum_length: u32) -> Option<String> {
    let selected = Rc::new(RefCell::new(None));
    let output = selected.clone();
    let target = context.clone();
    let _ = edit_session::request(context, client_id, TF_ES_SYNC | TF_ES_READ, move |ec| {
        let Some(range) = selection_range(ec, &target)? else {
            return Ok(());
        };
        // 秘密の欄かは選択の始まりで見る．Clone で別の範囲にする(参照の複製だと選択そのものを縮めてしまう)
        let start = unsafe { range.Clone()? };
        unsafe { start.Collapse(ec, TF_ANCHOR_START)? };
        if input_scope_is_secure(ec, &target, &start)? {
            return Ok(());
        }
        // 上限より 1 文字多く読み，読み切れたら長すぎるとみなす
        let mut buffer = vec![0u16; maximum_length as usize + 1];
        let mut fetched = 0u32;
        unsafe { range.GetText(ec, 0, &mut buffer, &mut fetched)? };
        if fetched == 0 || fetched > maximum_length {
            return Ok(());
        }
        buffer.truncate(fetched as usize);
        *output.borrow_mut() = Some(String::from_utf16_lossy(&buffer));
        Ok(())
    });
    selected.take()
}

/// 選択の範囲(選んでいなければ幅 0)
fn selection_range(ec: u32, context: &ITfContext) -> Result<Option<ITfRange>> {
    let mut selection = [TF_SELECTION {
        range: ManuallyDrop::new(None),
        style: TF_SELECTIONSTYLE {
            ase: TF_AE_NONE,
            fInterimChar: false.into(),
        },
    }];
    let mut fetched = 0u32;
    unsafe { context.GetSelection(ec, TF_DEFAULT_SELECTION, &mut selection, &mut fetched)? };
    let [first] = selection;
    let range = ManuallyDrop::into_inner(first.range);
    if fetched == 0 {
        return Ok(None);
    }
    Ok(range)
}

/// 選択の始まりの位置(幅 0 の範囲)
fn selection_start(ec: u32, context: &ITfContext) -> Result<Option<ITfRange>> {
    let mut selection = [TF_SELECTION {
        range: ManuallyDrop::new(None),
        style: TF_SELECTIONSTYLE {
            ase: TF_AE_NONE,
            fInterimChar: false.into(),
        },
    }];
    let mut fetched = 0u32;
    unsafe { context.GetSelection(ec, TF_DEFAULT_SELECTION, &mut selection, &mut fetched)? };
    let [first] = selection;
    let range = ManuallyDrop::into_inner(first.range);
    if fetched == 0 {
        return Ok(None);
    }
    let Some(range) = range else { return Ok(None) };
    unsafe { range.Collapse(ec, TF_ANCHOR_START)? };
    Ok(Some(range))
}

fn preceding_text(ec: u32, start: &ITfRange, length: u32) -> Result<Option<String>> {
    let length = length.min(i32::MAX as u32);
    let mut buffer = vec![0u16; length as usize];
    let mut fetched = 0u32;
    unsafe {
        let range = start.Clone()?;
        let mut moved = 0;
        range.ShiftStart(ec, -(length as i32), &mut moved, std::ptr::null())?;
        range.GetText(ec, 0, &mut buffer, &mut fetched)?;
    }
    buffer.truncate(fetched as usize);
    Ok((!buffer.is_empty()).then(|| String::from_utf16_lossy(&buffer)))
}

fn input_scope_is_secure(ec: u32, context: &ITfContext, range: &ITfRange) -> Result<bool> {
    unsafe {
        let mut value: VARIANT = context
            .GetProperty(&GUID_PROP_INPUTSCOPE)?
            .GetValue(ec, range)?;
        let inner = &value.Anonymous.Anonymous;
        let scope = if inner.vt == VT_UNKNOWN {
            (*inner.Anonymous.punkVal)
                .as_ref()
                .and_then(|unknown| unknown.cast::<ITfInputScope>().ok())
        } else {
            None
        };
        let secure = scope.map(|scope| has_secure_scope(&scope)).unwrap_or(false);
        let _ = VariantClear(&mut value);
        Ok(secure)
    }
}

fn has_secure_scope(scope: &ITfInputScope) -> bool {
    let mut scopes = std::ptr::null_mut();
    let mut count = 0u32;
    unsafe {
        if scope.GetInputScopes(&mut scopes, &mut count).is_err() || scopes.is_null() {
            return false;
        }
        let found = std::slice::from_raw_parts(scopes, count as usize)
            .iter()
            .any(|scope| [IS_PASSWORD, IS_NUMERIC_PASSWORD, IS_NUMERIC_PIN].contains(scope));
        CoTaskMemFree(Some(scopes as *const _));
        found
    }
}

fn variant_i32(value: i32) -> VARIANT {
    let mut variant = VARIANT::default();
    unsafe {
        let inner = &mut *variant.Anonymous.Anonymous;
        inner.vt = VT_I4;
        inner.Anonymous.lVal = value;
    }
    variant
}
