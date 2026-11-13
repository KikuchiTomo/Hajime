use super::display_attribute;
use super::edit_session;
use super::guard::guard;
use super::keyboard;
use super::langbar::{self, Anchor, InputModeItem};
use super::launch;
use super::phonetic;
use super::preserved::{self, Preserved};
use super::timer;
use crate::filter;
use crate::key::{self, RawKey};
use crate::plan::{CompositionPlan, PanelAnchor};
use ipc::windows::{pipe_name, EngineClient, Outcome, Pending};
use ipc::{
    EditOperation, ErrorCode, FieldContext, InputMode, Key, Rect, RequestBody, ResponseBody,
    SessionState, TextStyle,
};
use std::cell::RefCell;
use std::mem::ManuallyDrop;
use std::rc::Rc;
use std::time::{Duration, Instant};
use windows::Win32::Foundation::{LPARAM, POINT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::ClientToScreen;
use windows::Win32::System::Com::{CoCreateInstance, CoTaskMemFree, CLSCTX_INPROC_SERVER};
use windows::Win32::System::Threading::GetCurrentThreadId;
use windows::Win32::System::Variant::{VariantClear, VARIANT, VT_I4, VT_UNKNOWN};
use windows::Win32::UI::TextServices::{
    CLSID_TF_CategoryMgr, IEnumTfDisplayAttributeInfo, ITfCategoryMgr, ITfCompartment,
    ITfCompartmentEventSink, ITfCompartmentEventSink_Impl, ITfCompartmentMgr, ITfComposition,
    ITfCompositionSink, ITfCompositionSink_Impl, ITfContext, ITfContextComposition,
    ITfDisplayAttributeInfo, ITfDisplayAttributeProvider, ITfDisplayAttributeProvider_Impl,
    ITfDocumentMgr, ITfInputScope, ITfInsertAtSelection, ITfKeyEventSink, ITfKeyEventSink_Impl,
    ITfKeystrokeMgr, ITfRange, ITfSource, ITfTextInputProcessor, ITfTextInputProcessorEx,
    ITfTextInputProcessorEx_Impl, ITfTextInputProcessor_Impl, ITfThreadFocusSink,
    ITfThreadFocusSink_Impl, ITfThreadMgr, ITfThreadMgrEventSink, ITfThreadMgrEventSink_Impl,
    GUID_COMPARTMENT_EMPTYCONTEXT, GUID_COMPARTMENT_KEYBOARD_DISABLED,
    GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, GUID_COMPARTMENT_KEYBOARD_OPENCLOSE,
    GUID_PROP_ATTRIBUTE, GUID_PROP_INPUTSCOPE, INSERT_TEXT_AT_SELECTION_FLAGS, IS_NUMERIC_PASSWORD,
    IS_NUMERIC_PIN, IS_PASSWORD, TF_AE_NONE, TF_ANCHOR_END, TF_ANCHOR_START,
    TF_CONVERSIONMODE_ALPHANUMERIC, TF_CONVERSIONMODE_FULLSHAPE, TF_CONVERSIONMODE_NATIVE,
    TF_DEFAULT_SELECTION, TF_ES_ASYNCDONTCARE, TF_ES_READ, TF_ES_READWRITE, TF_ES_SYNC,
    TF_IAS_QUERYONLY, TF_SELECTION, TF_SELECTIONSTYLE, TF_ST_CORRECTION,
};
use windows::Win32::UI::WindowsAndMessaging::{GetGUIThreadInfo, GUITHREADINFO};
use windows_core::{implement, ComObject, IUnknownImpl, Interface, Ref, Result, BOOL, GUID};

const RESPONSE_TIMEOUT: Duration = Duration::from_millis(ipc::timing::KEY_RESPONSE_MILLISECONDS);
/// 変換のキー(Space・変換)の返事を待つ時間．Zenzai で文全体を変換し直すので CPU では 100ms ほどかかる．
/// 待たずにタイマーで後から反映すると，変換が出るまで間が空き，タイマーの知らせが遅れるアプリでは更に遅れる
const CONVERSION_TIMEOUT: Duration =
    Duration::from_millis(ipc::timing::CONVERSION_RESPONSE_MILLISECONDS);
const RECONNECT_INTERVAL: Duration = Duration::from_millis(ipc::timing::RECONNECT_MILLISECONDS);
/// 返事の遅れがこれより長く続いたら，エンジンが固まったとみなす
const STALL_LIMIT: Duration = Duration::from_millis(ipc::timing::ENGINE_STALL_MILLISECONDS);
/// 入力メニューの「単語の登録…」で読む，選んでいる文字の長さの上限．キーで頼まれたときはエンジンが上限を渡すが，
/// メニューからは渡されないので，登録できる単語の長さの上限(core の DefaultSettings.maximumUserDictionaryWordLength)と同じにする．
/// 登録できない長さの文字を読んで送らないため
const MENU_REGISTRATION_LENGTH: u32 = 64;
/// 予約したキーで受け取った打鍵が，続けてキーのシンクにも届くのを待つ長さ
const PRESERVED_ECHO_WINDOW: Duration = Duration::from_millis(500);

/// 試しのビルドだけ: 経路の番号と有無だけを OutputDebugString に出す(入力した文字・読み・候補は出さない)
fn trace(route: u32, a: bool, b: bool) {
    let text = format!(
        "hajime-trace route={route} a={} b={}\0",
        u8::from(a),
        u8::from(b)
    );
    let wide: Vec<u16> = text.encode_utf16().collect();
    // SAFETY: wide は 0 で終わる文字列で，呼び出しのあいだ生きている
    unsafe {
        windows::Win32::System::Diagnostics::Debug::OutputDebugStringW(windows_core::PCWSTR(
            wide.as_ptr(),
        ))
    };
}

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
    ITfThreadFocusSink,
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
    /// アプリに入力先が移った・外れたを知る ITfThreadFocusSink の登録
    thread_focus_cookie: Option<u32>,
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
    /// 候補の窓をそろえる字．そろえる字を添えない返事でも，組み立て中の文字が同じあいだは前の字にそろえる
    panel_anchor: PanelAnchor,
    timer: usize,
    application_id: Option<String>,
    mode_item: Option<ComObject<InputModeItem>>,
    /// 予約したキー(Alt の付いた表のキー．preserved)
    preserved: Vec<Preserved>,
    /// 予約したキーで受け取った打鍵(仮想キー・受け取った時刻)．同じ打鍵がキーのシンクにも届く欄で 2 回扱わないため
    preserved_echo: Option<(u16, Instant)>,
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
            let (thread_mgr, client_id, cookie, focus_cookie, engine, session, mode_item) = {
                let mut inner = self.inner.borrow_mut();
                (
                    inner.thread_mgr.take(),
                    inner.client_id,
                    inner.sink_cookie.take(),
                    inner.thread_focus_cookie.take(),
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
                    let mut current = std::mem::take(&mut self.inner.borrow_mut().preserved);
                    preserved::clear(&keystrokes, &mut current);
                    let _ = unsafe { keystrokes.UnadviseKeyEventSink(client_id) };
                }
                if let Ok(source) = thread_mgr.cast::<ITfSource>() {
                    for cookie in [cookie, focus_cookie].into_iter().flatten() {
                        let _ = unsafe { source.UnadviseSink(cookie) };
                    }
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
            let thread_focus_sink: ITfThreadFocusSink = self.to_interface();
            let thread_focus_cookie = unsafe {
                thread_mgr
                    .cast::<ITfSource>()?
                    .AdviseSink(&ITfThreadFocusSink::IID, &thread_focus_sink)
                    .ok()
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
                inner.thread_focus_cookie = thread_focus_cookie;
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

/// キーを受け取ってよい入力先の文脈．文脈が無いとき・入力先が IME を切っているときは None．
/// ゲームは遊んでいるあいだ，キーボードを無効にした文脈(GUID_COMPARTMENT_KEYBOARD_DISABLED)や空の文脈
/// (GUID_COMPARTMENT_EMPTYCONTEXT)に入力先を移して IME を切る(Unreal Engine で作った VALORANT など)．
/// それでも日本語の入力でキーを受け取ると，移動の WASD などがゲームに届かず遊べなくなる
fn key_target<'a>(pic: &'a Ref<ITfContext>) -> Option<&'a ITfContext> {
    let context = pic.as_ref()?;
    let Ok(compartments) = context.cast::<ITfCompartmentMgr>() else {
        return Some(context);
    };
    let disabled = [
        GUID_COMPARTMENT_KEYBOARD_DISABLED,
        GUID_COMPARTMENT_EMPTYCONTEXT,
    ]
    .iter()
    .any(|guid| {
        // SAFETY: guid は呼び出しのあいだ生きている．compartment は無ければ空の値で作られるだけで，入力先は変わらない
        unsafe { compartments.GetCompartment(guid) }
            .ok()
            .and_then(|compartment| compartment_i32(&compartment))
            .is_some_and(|value| value != 0)
    });
    (!disabled).then_some(context)
}

/// compartment の値(VT_I4 のときだけ)
fn compartment_i32(compartment: &ITfCompartment) -> Option<i32> {
    // SAFETY: GetValue が返した VARIANT は，型(vt)を確かめてから読み，読んだあと VariantClear で放す
    unsafe {
        let mut value = compartment.GetValue().ok()?;
        let inner = &value.Anonymous.Anonymous;
        let number = (inner.vt == VT_I4).then(|| inner.Anonymous.lVal);
        let _ = VariantClear(&mut value);
        number
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

    fn OnTestKeyDown(&self, pic: Ref<ITfContext>, wparam: WPARAM, lparam: LPARAM) -> Result<BOOL> {
        guard(|| {
            // OnKeyDown で受け取らないキーを，ここで受け取ると答えない(答えると，アプリにキーが届かないことがある)
            if key_target(&pic).is_none() {
                return Ok(false.into());
            }
            if self.is_preserved_echo(wparam, false) {
                return Ok(true.into());
            }
            Ok(self.wants(wparam, lparam).is_some().into())
        })
    }

    fn OnTestKeyUp(&self, _pic: Ref<ITfContext>, _wparam: WPARAM, _lparam: LPARAM) -> Result<BOOL> {
        Ok(false.into())
    }

    fn OnKeyDown(&self, pic: Ref<ITfContext>, wparam: WPARAM, lparam: LPARAM) -> Result<BOOL> {
        guard(|| {
            let Some(context) = key_target(&pic) else {
                return Ok(false.into());
            };
            // 予約したキーで受け取った打鍵が，キーのシンクにも届いた．もう送ったので，送らずに受け取る
            if self.is_preserved_echo(wparam, true) {
                return Ok(true.into());
            }
            let Some(input) = self.wants(wparam, lparam) else {
                return Ok(false.into());
            };
            self.send_key(context, input)
        })
    }

    fn OnKeyUp(&self, _pic: Ref<ITfContext>, _wparam: WPARAM, _lparam: LPARAM) -> Result<BOOL> {
        Ok(false.into())
    }

    fn OnPreservedKey(&self, pic: Ref<ITfContext>, rguid: *const GUID) -> Result<BOOL> {
        guard(|| {
            let Some(context) = key_target(&pic) else {
                return Ok(false.into());
            };
            if rguid.is_null() {
                return Ok(false.into());
            }
            // SAFETY: TSF が渡す識別子．null でないことは上で確かめた
            let guid = unsafe { *rguid };
            let found = self.inner.borrow().preserved.iter().find_map(|preserved| {
                (preserved.guid == guid).then(|| (preserved.chord.clone(), preserved.vk()))
            });
            let Some((chord, vk)) = found else {
                return Ok(false.into());
            };
            // エンジンにつながっていないときはアプリに渡す
            if self.inner.borrow().state.is_none() {
                return Ok(false.into());
            }
            let input = ipc::KeyInput {
                key: chord.key,
                modifiers: chord.modifiers,
                key_label: None,
                is_keypad: false,
            };
            let eaten = self.send_key(context, input)?;
            if eaten.as_bool() {
                self.inner.borrow_mut().preserved_echo = Some((vk, Instant::now()));
            }
            Ok(eaten)
        })
    }
}

impl TextService_Impl {
    /// キーをエンジンに送り，返事を反映する．受け取った(アプリに渡さない)なら true
    fn send_key(&self, context: &ITfContext, input: ipc::KeyInput) -> Result<BOOL> {
        {
            // コマンドの候補を確定すると，エンジンがアプリやページを開く．エンジンは裏のプロセスで窓を前に出せないので，
            // 前にいる入力先のアプリから，つないでいるエンジンにだけ前に出ることを許す(許さないと開いたアプリが後ろに出る)
            if input.key == Key::Enter {
                self.allow_engine_foreground();
            }
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
        }
    }

    /// エンジンの返した状態を覚え，Alt の付いた表のキーを予約し直す
    fn set_state(&self, state: SessionState) {
        let chords = filter::preserved_chords(&state);
        let (thread_mgr, client_id) = {
            let mut inner = self.inner.borrow_mut();
            inner.state = Some(state);
            (inner.thread_mgr.clone(), inner.client_id)
        };
        let (Some(chords), Some(thread_mgr)) = (chords, thread_mgr) else {
            return;
        };
        let Ok(keystrokes) = thread_mgr.cast::<ITfKeystrokeMgr>() else {
            return;
        };
        let mut current = std::mem::take(&mut self.inner.borrow_mut().preserved);
        preserved::replace(&keystrokes, client_id, &mut current, &chords);
        self.inner.borrow_mut().preserved = current;
    }

    /// この打鍵は，予約したキーでもう受け取ったものか(take なら覚えを消す)
    fn is_preserved_echo(&self, wparam: WPARAM, take: bool) -> bool {
        let mut inner = self.inner.borrow_mut();
        let Some((vk, at)) = inner.preserved_echo else {
            return false;
        };
        if at.elapsed() > PRESERVED_ECHO_WINDOW {
            inner.preserved_echo = None;
            return false;
        }
        let echo = wparam.0 == usize::from(vk);
        if echo && take {
            inner.preserved_echo = None;
        }
        echo
    }

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
            }
            self.set_state(state);
            self.show_mode(mode);
            self.activate();
        }
    }

    /// アプリに入力先が移ったことをエンジンに知らせる．除外設定で決めたモードか，ほかのアプリで最後に使ったモードに揃う
    fn activate(&self) {
        let (engine, session, thread_mgr) = {
            let inner = self.inner.borrow();
            (
                inner.engine.clone(),
                inner.session,
                inner.thread_mgr.clone(),
            )
        };
        let (Some(engine), Some(session)) = (engine, session) else {
            return;
        };
        let target = thread_mgr.and_then(|manager| unsafe {
            manager
                .GetFocus()
                .and_then(|focus: ITfDocumentMgr| focus.GetTop())
                .ok()
        });
        // 前のキーの返事が遅れていたら，先に反映する(あとから古い返事がモードを戻さないように)
        if let Some(target) = &target {
            self.apply_late(target, RESPONSE_TIMEOUT);
        }
        // 今の入力位置(モード表示をそこに出す)．読めなければ前の位置
        let client_id = self.inner.borrow().client_id;
        let current = target
            .as_ref()
            .and_then(|target| read_field(target, client_id, 0, true).caret);
        // エンジンはアプリの識別子だけを使う．入力欄の前の文字は読まない・送らない
        let context = {
            let mut inner = self.inner.borrow_mut();
            if let Some(current) = &current {
                inner.caret = Some(current.clone());
            }
            FieldContext {
                application_id: inner.application_id.clone(),
                is_secure: false,
                preceding_text: None,
                caret: inner.caret.clone(),
                can_replace_preceding_text: Some(true),
                can_show_menu: Some(true),
                can_request_word_registration: Some(true),
            }
        };
        let pending = engine.send(RequestBody::Activate { session, context });
        match pending.outcome(RESPONSE_TIMEOUT) {
            Outcome::Reply(body) => match (body, target) {
                (body, Some(target)) => {
                    self.apply_response(&target, body);
                }
                (ResponseBody::Edit { state, .. }, None) => {
                    let mode = state.mode;
                    self.set_state(state);
                    self.show_mode(mode);
                }
                _ => {}
            },
            // 間に合わなければ，キーの返事と同じく，あとで送った順に反映する(エンジンとモードがずれたままにしない)
            Outcome::TimedOut => {
                self.defer(pending);
            }
            Outcome::Unavailable => self.forget_session(),
        }
    }

    fn field_context(&self, context: &ITfContext) -> FieldContext {
        let (application_id, caret, client_id, wanted, composing) = {
            let inner = self.inner.borrow();
            (
                inner.application_id.clone(),
                inner.caret.clone(),
                inner.client_id,
                inner
                    .state
                    .as_ref()
                    .and_then(|state| state.preceding_text_length),
                inner.composition.is_some(),
            )
        };
        // 組み立てている途中は前の位置を使うので，入力位置の画面の上の位置は尋ねない(キーごとにアプリに配置を尋ねない)
        let mut field = read_field(context, client_id, wanted.unwrap_or(0), !composing);
        // 何も選んでいない入力位置の画面の位置を返さない欄(WinForms の TextBox など)では，システムのキャレットの位置を使う
        // (使わないと前の欄やほかのアプリの位置が残り，パレットやモード表示がそこに出る)
        if !composing && field.caret.is_none() {
            field.caret = system_caret();
        }
        // 組み立てていないときは今の入力位置を使う(前の組み立ての位置は，ほかの欄やほかのアプリのことがある．
        // モード表示や最初の候補の窓がそこに出てしまう)
        let caret = match (composing, field.caret) {
            (false, Some(current)) => {
                self.inner.borrow_mut().caret = Some(current.clone());
                Some(current)
            }
            _ => caret,
        };
        FieldContext {
            application_id,
            is_secure: field.is_secure,
            preceding_text: field.preceding_text,
            caret,
            // 組み立てを始めるときに，入力位置の前の文字を置き換えられる(show の replaced_length)
            can_replace_preceding_text: Some(true),
            // 入力メニューを入力位置に出せる(ShowMenu)．選んでいる文字を読んで単語の登録に渡せる(RequestWordRegistration)
            can_show_menu: Some(true),
            can_request_word_registration: Some(true),
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
                self.set_state(state);
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
        let mut registration = None;
        let mut shows_menu = false;
        for operation in operations {
            match operation {
                EditOperation::SelectMode { mode } => self.select_mode(mode),
                EditOperation::RequestReconversion { maximum_length } => {
                    reconversion = Some(maximum_length)
                }
                EditOperation::RequestWordRegistration { maximum_length } => {
                    registration = Some(maximum_length)
                }
                EditOperation::ShowMenu => shows_menu = true,
                other => edits.push(other),
            }
        }
        let reconverted =
            reconversion.is_none_or(|maximum_length| self.reconvert(context, maximum_length));
        if let Some(maximum_length) = registration {
            self.register_word(context, maximum_length);
        }
        // メニューは閉じるまで戻らないので，キーの処理と組み立て中の文字の確定(下の edit)を終えてから出す
        if shows_menu {
            trace(6, true, false);
            timer::defer(on_menu);
        }
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
                // 候補の窓をそろえる字(組み立て中の文字の頭からの UTF-16 の位置)．無ければ頭にそろえる
                let mut panel_anchor = None;
                // この返事で書き換えた組み立て中の文字(そろえる字を前の返事から引き継ぐかを決める)
                let mut written = None;
                for edit in edits {
                    if let EditOperation::SetComposition {
                        panel_anchor: anchor,
                        segments,
                        ..
                    } = &edit
                    {
                        panel_anchor = *anchor;
                        written = Some(CompositionPlan::new(segments).text);
                    }
                    result = match edit {
                        EditOperation::Commit { text } => {
                            commit(ec, &target, &mut composition, &text)
                        }
                        EditOperation::SetComposition {
                            segments,
                            caret,
                            replaced_length,
                            ..
                        } => show(
                            ec,
                            &target,
                            &mut composition,
                            &CompositionPlan::new(&segments).with_caret(caret),
                            replaced_length,
                            &atoms,
                            &sink,
                        ),
                        EditOperation::SelectMode { .. }
                        | EditOperation::RequestReconversion { .. }
                        | EditOperation::RequestWordRegistration { .. }
                        | EditOperation::ShowMenu => Ok(()),
                    };
                    if result.is_err() {
                        break;
                    }
                }
                // 添えない返事でも，組み立て中の文字が同じあいだは前の字にそろえる(基準が行き来して窓が動き続けないように)
                let panel_anchor = {
                    let mut inner = service.inner.borrow_mut();
                    if composition.is_none() {
                        inner.panel_anchor.reset();
                        None
                    } else {
                        inner.panel_anchor.resolve(written.as_deref(), panel_anchor)
                    }
                };
                // 候補の窓を置く基準(そろえる字があればその字)と，組み立て中の文字全体の位置(予測の窓を右に置く基準)
                let rects = composition.as_ref().and_then(|current| {
                    let whole = text_rect(ec, &target, current).ok()?;
                    let caret = panel_anchor
                        .and_then(|offset| anchored_rect(ec, &target, current, offset, &whole))
                        .unwrap_or_else(|| whole.clone());
                    Some((caret, whole))
                });
                let caret = rects.as_ref().map(|(caret, _)| caret.clone());
                let (engine, session) = {
                    let mut inner = service.inner.borrow_mut();
                    inner.composition = composition;
                    if caret.is_some() {
                        inner.caret = caret.clone();
                    }
                    (inner.engine.clone(), inner.session)
                };
                if let (Some(engine), Some(session), Some((rect, whole))) = (engine, session, rects)
                {
                    let _ = engine.send(RequestBody::Caret {
                        session,
                        rect,
                        composition: Some(whole),
                    });
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
                // 返事のたびに同じ値を書き直さない(書くたびに compartment を見ているほかの部品へ知らせが飛ぶ)
                if compartment_i32(&compartment) != Some(conversion as i32) {
                    let _ = compartment.SetValue(client_id, &variant_i32(conversion as i32));
                }
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
            (Some(ResponseBody::Edit { state, .. }), None) => self.set_state(state),
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
        self.send_menu_edit(|session, context| RequestBody::OpenHandwriting { session, context });
    }

    /// 入力メニューの「絵文字と記号」(R-26)．組み立て中の文字を確定してから，前に見ていた種類でパレットを開く(エンジンが edit で返す．
    /// 開いているあいだは状態の isComposing が真になり，キーをすべてエンジンに送る)
    fn open_palette(&self) {
        self.send_menu_edit(|session, context| RequestBody::OpenPalette { session, context });
    }

    /// 入力メニューから，文書を書き換えられる要求をエンジンに送る．セッションが無ければ先に作る
    fn send_menu_edit(&self, make: impl FnOnce(u32, FieldContext) -> RequestBody) {
        if self.inner.borrow().session.is_none() {
            self.ensure_session();
        }
        let Some((context, engine, session)) = self.focused_context() else {
            return;
        };
        self.send_edit(&context, engine, session, make);
    }

    /// 再変換．入力先で選んでいる文字(maximum_length 文字まで)を読み，Windows の日本語の解析で読みを求めて，エンジンに変換し直してもらう．
    /// 選んでいない・秘密の欄・長すぎる・読みを求められないときは何もせず false
    fn reconvert(&self, context: &ITfContext, maximum_length: u32) -> bool {
        let client_id = self.inner.borrow().client_id;
        let Some(text) = read_selection(context, client_id, maximum_length, Overflow::Reject)
        else {
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

    /// 単語の登録(入力していないときのキーの「単語の登録」と，入力メニューの「単語の登録…」)．入力先で選んでいる文字
    /// (maximum_length 文字までで切る)と，Windows の日本語の解析で求めた読みをエンジンに送る．エンジンは設定の画面を
    /// ユーザー辞書の登録で開き，語と読みを渡す．選んでいない・秘密の欄では空の語で開く
    /// (語と読みは入力内容なので，ログにも設定の画面の引数にも出さない)
    fn register_word(&self, context: &ITfContext, maximum_length: u32) {
        let client_id = self.inner.borrow().client_id;
        let text = read_selection(context, client_id, maximum_length, Overflow::Truncate)
            .unwrap_or_default();
        let reading = phonetic::reading(&text);
        self.open_settings(
            RequestBody::OpenWordRegistration { text, reading },
            crate::menu::REGISTER_WORD_ARGUMENTS,
        );
    }

    /// 入力メニューの「単語の登録…」．注目している文書で選んでいる文字を語にする(キーと同じ)
    fn register_selection(&self) {
        match self.focused_context() {
            Some((context, ..)) => self.register_word(&context, MENU_REGISTRATION_LENGTH),
            None => self.open_settings(
                RequestBody::OpenWordRegistration {
                    text: String::new(),
                    reading: None,
                },
                crate::menu::REGISTER_WORD_ARGUMENTS,
            ),
        }
    }

    /// 設定の画面を開く要求をエンジンに送る．エンジンが動いていない・受けなかった(古いエンジン)ときは，設定の画面を arguments で
    /// 直接開く(設定の画面がエンジンを起動し直す)．返事が間に合わないだけなら，エンジンが開いている途中とみなして直接は開かない
    /// (開くと窓が 2 つ出る)．開いた窓が入力先のアプリの後ろに出ないよう，エンジンに前に出ることを許す
    fn open_settings(&self, body: RequestBody, arguments: &str) {
        self.allow_engine_foreground();
        let engine = self.inner.borrow().engine.clone();
        let opened =
            engine.is_some_and(|engine| match engine.send(body).outcome(RESPONSE_TIMEOUT) {
                Outcome::Reply(reply) => matches!(reply, ResponseBody::Done),
                Outcome::TimedOut => true,
                Outcome::Unavailable => false,
            });
        if !opened {
            let _ = launch::start_with(launch::SETTINGS_FILE, arguments);
        }
    }

    /// つないでいるエンジンにだけ，窓を前に出すことを許す．エンジンは裏のプロセスで窓を前に出せないので，
    /// エンジンが開くアプリ(コマンド・設定の画面)が後ろに出る．前にいる入力先のアプリから許す
    fn allow_engine_foreground(&self) {
        let engine = self.inner.borrow().engine.clone();
        if let Some(id) = engine.and_then(|engine| engine.server_process_id()) {
            // SAFETY: 引数はプロセスの番号だけ
            let _ =
                unsafe { windows::Win32::UI::WindowsAndMessaging::AllowSetForegroundWindow(id) };
        }
    }

    /// 入力メニューを入力位置に出す(キーの「入力メニューを開く」)．タスクバーの右クリックと同じ項目を出し，選んだ項目も同じく行う．
    /// 入力位置を読めなければポインターの位置に出す
    fn show_input_menu(&self) {
        let client_id = self.inner.borrow().client_id;
        let focused = self.focused_context();
        let read = focused
            .as_ref()
            .and_then(|(context, ..)| read_field(context, client_id, 0, true).caret);
        trace(2, focused.is_some(), read.is_some());
        trace(
            3,
            self.inner.borrow().caret.is_some(),
            self.inner.borrow().session.is_some(),
        );
        let caret = read.or_else(|| self.inner.borrow().caret.clone());
        let rect = match caret {
            Some(caret) => RECT {
                left: caret.x,
                top: caret.y,
                right: caret.x.saturating_add(caret.width),
                bottom: caret.y.saturating_add(caret.height),
            },
            None => {
                let mut point = POINT::default();
                // SAFETY: point はこの関数の中の値
                if unsafe { windows::Win32::UI::WindowsAndMessaging::GetCursorPos(&mut point) }
                    .is_err()
                {
                    return;
                }
                RECT {
                    left: point.x,
                    top: point.y,
                    right: point.x,
                    bottom: point.y,
                }
            }
        };
        let _ = langbar::show_menu(&MenuActions, Anchor::Caret(rect));
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
            trace(5, false, false);
            return;
        };
        let field = self.field_context(context);
        let pending = engine.send(make(session, field));
        let outcome = pending.outcome(RESPONSE_TIMEOUT);
        trace(5, true, matches!(outcome, Outcome::Reply(_)));
        match outcome {
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
        let service = Self::active();
        // 設定の画面を開くコマンドは，エンジンが動いていなくても開けるようにする(設定の画面がエンジンを起動し直す)
        match (crate::menu::settings_arguments(&command), service) {
            (Some(arguments), Some(service)) => {
                service.open_settings(RequestBody::Menu { command }, arguments)
            }
            (Some(arguments), None) => {
                let _ = launch::start_with(launch::SETTINGS_FILE, arguments);
            }
            (None, Some(service)) => {
                let _ = service.engine_request(RequestBody::Menu { command });
            }
            (None, None) => {}
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

    fn open_palette(&self) {
        let service = Self::active();
        trace(
            4,
            service.is_some(),
            service
                .as_ref()
                .is_some_and(|service| service.focused_context().is_some()),
        );
        if let Some(service) = service {
            service.open_palette();
        }
    }

    fn register_word(&self) {
        match Self::active() {
            Some(service) => service.register_selection(),
            None => {
                let _ =
                    launch::start_with(launch::SETTINGS_FILE, crate::menu::REGISTER_WORD_ARGUMENTS);
            }
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

/// キーで頼まれた入力メニューを，キーの処理を終えてから出す(timer の窓の手続きが panic を受け止める)
fn on_menu() {
    let service = ACTIVE.with(|active| active.borrow().clone());
    trace(1, service.is_some(), false);
    if let Some(service) = service {
        service.show_input_menu();
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
            self.cancel_timer();
            self.finish_composition(None);
            // 手書きの窓を開いているあいだは，選んだ文字を取りに来続ける．エンジンは deactivate の答えで，そのときだけ
            // 来るよう頼む(入力メニューを出し入れするなど，同じアプリの中で注目が動いても，選んだ文字を入れられるように)
            let wake = self
                .inner
                .borrow()
                .state
                .as_ref()
                .and_then(|state| state.wake_after_milliseconds);
            self.schedule_timer(wake);
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

impl ITfThreadFocusSink_Impl for TextService_Impl {
    fn OnSetThreadFocus(&self) -> Result<()> {
        guard(|| {
            if self.inner.borrow().session.is_some() {
                self.activate();
            } else {
                self.ensure_session();
            }
            Ok(())
        })
    }

    fn OnKillThreadFocus(&self) -> Result<()> {
        guard(|| {
            // 組み立て中の文字を確定し，このアプリのモードをエンジンに覚えさせる(macOS の deactivateServer と同じ)
            self.finish_composition(None);
            self.cancel_timer();
            Ok(())
        })
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
        compartment_i32(&compartment).map(|open| {
            if open != 0 {
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
                    self.set_state(state);
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

/// 組み立て中の文字を出す．組み立てを始めるときに replaced_length(UTF-16 の数)があれば，入力位置の前のその長さの文字を
/// 組み立て中の文字で置き換える(確定を取り消して確定する前の変換や読みに戻す．エンジンが入力位置の前の文字列で確かめてから送る)
fn show(
    ec: u32,
    context: &ITfContext,
    composition: &mut Option<ITfComposition>,
    plan: &CompositionPlan,
    replaced_length: Option<u32>,
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
                if let Some(length) = replaced_length.filter(|length| *length > 0) {
                    let mut moved = 0;
                    range.ShiftStart(
                        ec,
                        -(length.min(i32::MAX as u32) as i32),
                        &mut moved,
                        std::ptr::null(),
                    )?;
                }
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
        match plan.caret {
            // 文節をその場で打ち直しているときは，打ち直している文節の終わりに入力位置を置く
            Some(offset) => {
                caret.Collapse(ec, TF_ANCHOR_START)?;
                let mut moved = 0;
                caret.ShiftEnd(ec, offset, &mut moved, std::ptr::null())?;
                caret.Collapse(ec, TF_ANCHOR_END)?;
            }
            None => caret.Collapse(ec, TF_ANCHOR_END)?,
        }
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
    let range = unsafe { composition.GetRange()? };
    range_rect(ec, context, &range)
}

/// 候補の窓を置く基準(macOS の ClientActionPresenter.panelAnchor)．左端は組み立て中の文字の offset の字，上下は
/// 組み立て中の文字の全体(折り返していても窓を文字に重ねない)．字の位置を読めなければ None
fn anchored_rect(
    ec: u32,
    context: &ITfContext,
    composition: &ITfComposition,
    offset: u32,
    whole: &Rect,
) -> Option<Rect> {
    let range = unsafe { composition.GetRange().ok()?.Clone().ok()? };
    let mut moved = 0;
    unsafe {
        range.Collapse(ec, TF_ANCHOR_START).ok()?;
        range
            .ShiftStart(
                ec,
                i32::try_from(offset).ok()?,
                &mut moved,
                std::ptr::null(),
            )
            .ok()?;
        range.Collapse(ec, TF_ANCHOR_START).ok()?;
        range.ShiftEnd(ec, 1, &mut moved, std::ptr::null()).ok()?;
    }
    if moved == 0 {
        return None;
    }
    let character = range_rect(ec, context, &range).ok()?;
    Some(anchored(whole, &character))
}

/// 組み立て中の文字の全体の位置と，そろえる字の位置から，候補の窓を置く基準を作る
fn anchored(whole: &Rect, character: &Rect) -> Rect {
    Rect {
        x: character.x,
        y: whole.y,
        width: character.width.max(1),
        height: whole.height,
    }
}

/// 範囲の画面の上の位置(入力位置なら幅 0 の範囲)
fn range_rect(ec: u32, context: &ITfContext, range: &ITfRange) -> Result<Rect> {
    let mut rect = RECT::default();
    let mut clipped = BOOL::default();
    unsafe {
        context
            .GetActiveView()?
            .GetTextExt(ec, range, &mut rect, &mut clipped)?;
    }
    // 位置を返せないアプリ(組み立て直後で配置が決まっていない)は空の矩形を返す
    if rect.right == rect.left && rect.bottom == rect.top && rect.left == 0 && rect.top == 0 {
        return Err(windows::Win32::Foundation::E_FAIL.into());
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
    /// 入力位置の画面の上の位置(読めなければ None)
    caret: Option<Rect>,
}

/// 入力欄が秘密の欄か(パスワードなど)と，入力位置の前の文字列(最大 length 文字．UTF-16 で数える)を 1 回の読み取りで読む．
/// 秘密の欄では前の文字列を読まない．wants_caret なら入力位置の画面の上の位置も読む
/// この入力のスレッドのシステムのキャレット(画面の位置)．キャレットを出していなければ None
fn system_caret() -> Option<Rect> {
    let mut info = GUITHREADINFO {
        cbSize: std::mem::size_of::<GUITHREADINFO>() as u32,
        ..Default::default()
    };
    // SAFETY: info は cbSize を入れた GUITHREADINFO．スレッドはこの入力のスレッド(TSF はアプリの UI のスレッドで呼ぶ)
    unsafe { GetGUIThreadInfo(GetCurrentThreadId(), &mut info) }.ok()?;
    if info.hwndCaret.is_invalid() {
        return None;
    }
    let mut corners = [
        POINT {
            x: info.rcCaret.left,
            y: info.rcCaret.top,
        },
        POINT {
            x: info.rcCaret.right,
            y: info.rcCaret.bottom,
        },
    ];
    for corner in &mut corners {
        // SAFETY: hwndCaret はキャレットを持つ窓，corner はこの呼び出しのあいだ生きている
        unsafe { ClientToScreen(info.hwndCaret, corner) }
            .ok()
            .ok()?;
    }
    Some(Rect {
        x: corners[0].x,
        y: corners[0].y,
        width: corners[1].x - corners[0].x,
        height: corners[1].y - corners[0].y,
    })
}

fn read_field(
    context: &ITfContext,
    client_id: u32,
    length: u32,
    wants_caret: bool,
) -> FieldReading {
    let reading = Rc::new(RefCell::new(FieldReading::default()));
    let output = reading.clone();
    let target = context.clone();
    let _ = edit_session::request(context, client_id, TF_ES_SYNC | TF_ES_READ, move |ec| {
        let Some(selection) = selection_start(ec, &target)? else {
            return Ok(());
        };
        let secure = input_scope_is_secure(ec, &target, &selection)?;
        let caret = if wants_caret {
            range_rect(ec, &target, &selection).ok()
        } else {
            None
        };
        let mut field = output.borrow_mut();
        field.is_secure = secure;
        field.caret = caret;
        if !secure && length > 0 {
            field.preceding_text = preceding_text(ec, &selection, length).ok().flatten();
        }
        Ok(())
    });
    reading.take()
}

/// 選んでいる文字が上限より長いときの扱い
#[derive(Clone, Copy, PartialEq, Eq)]
enum Overflow {
    /// 読まない(再変換．途中までを変換し直すと，残りが元のまま残る)
    Reject,
    /// 頭から上限までにする(単語の登録．エンジンも単語の長さの上限で切る)
    Truncate,
}

/// 入力先で選んでいる文字．選んでいない・秘密の欄では None．maximum_length(UTF-16 で数える)より長いときは overflow に従う
fn read_selection(
    context: &ITfContext,
    client_id: u32,
    maximum_length: u32,
    overflow: Overflow,
) -> Option<String> {
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
        if fetched == 0 || (fetched > maximum_length && overflow == Overflow::Reject) {
            return Ok(());
        }
        buffer.truncate(fetched.min(maximum_length) as usize);
        // 切った端が上位サロゲートなら，対になる字ごと落とす(壊れた字を送らない)
        if fetched > maximum_length
            && buffer
                .last()
                .is_some_and(|unit| (0xD800..=0xDBFF).contains(unit))
        {
            buffer.pop();
        }
        if buffer.is_empty() {
            return Ok(());
        }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 候補の窓は文節の字の左にそろえ上下は組み立て中の文字の全体にする() {
        let whole = Rect {
            x: 100,
            y: 200,
            width: 300,
            height: 40,
        };
        let character = Rect {
            x: 250,
            y: 220,
            width: 0,
            height: 20,
        };
        assert_eq!(
            anchored(&whole, &character),
            Rect {
                x: 250,
                y: 200,
                width: 1,
                height: 40
            }
        );
    }
}
