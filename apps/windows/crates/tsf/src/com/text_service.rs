use super::display_attribute;
use super::edit_session;
use super::guard::guard;
use super::keyboard;
use super::langbar::{self, InputModeItem};
use crate::filter;
use crate::key::{self, RawKey};
use crate::plan::CompositionPlan;
use ipc::windows::{pipe_name, EngineClient, Outcome, Pending};
use ipc::{
    EditOperation, ErrorCode, FieldContext, InputMode, Rect, RequestBody, ResponseBody,
    SessionState, TextStyle,
};
use std::cell::RefCell;
use std::mem::ManuallyDrop;
use std::rc::Rc;
use std::time::{Duration, Instant};
use windows::Win32::Foundation::{HWND, LPARAM, RECT, WPARAM};
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
use windows::Win32::UI::WindowsAndMessaging::{KillTimer, SetTimer};
use windows_core::{implement, ComObject, IUnknownImpl, Interface, Ref, Result, BOOL, GUID};

const RESPONSE_TIMEOUT: Duration = Duration::from_millis(50);
const RECONNECT_INTERVAL: Duration = Duration::from_secs(2);

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
            self.apply_late(context);
            let field = self.field_context(context);
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
            match pending.outcome(RESPONSE_TIMEOUT) {
                Outcome::Reply(body) => Ok(self.apply_response(context, body).into()),
                Outcome::TimedOut => {
                    self.inner.borrow_mut().late.push(pending);
                    self.schedule_timer(Some(RESPONSE_TIMEOUT.as_millis() as u32));
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
        let raw: RawKey = keyboard::read(wparam, lparam)?;
        if key::is_modifier_only(raw.vk) {
            return None;
        }
        let input = key::translate(&raw)?;
        if self.inner.borrow().state.is_none() && self.inner.borrow().timer == 0 {
            self.schedule_timer(Some(0));
        }
        filter::consumes(self.inner.borrow().state.as_ref(), &input).then_some(input)
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
                self.apply_operations(context, operations);
                self.schedule_timer(wake);
                handled
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

    fn apply_late(&self, context: &ITfContext) {
        let late = std::mem::take(&mut self.inner.borrow_mut().late);
        let mut waiting = Vec::new();
        for pending in late {
            match pending.try_take() {
                Ok(Some(body)) => {
                    self.apply_response(context, body);
                }
                Ok(None) => {}
                Err(pending) => waiting.push(pending),
            }
        }
        self.inner.borrow_mut().late.extend(waiting);
    }

    fn apply_operations(&self, context: &ITfContext, operations: Vec<EditOperation>) {
        let mut edits = Vec::new();
        for operation in operations {
            match operation {
                EditOperation::SelectMode { mode } => self.select_mode(mode),
                other => edits.push(other),
            }
        }
        if edits.is_empty() {
            return;
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
                        EditOperation::SelectMode { .. } => Ok(()),
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
        let timer = unsafe { SetTimer(None, 0, milliseconds.max(1), Some(on_timer)) };
        self.inner.borrow_mut().timer = timer;
    }

    fn cancel_timer(&self) {
        let timer = std::mem::take(&mut self.inner.borrow_mut().timer);
        if timer != 0 {
            let _ = unsafe { KillTimer(None, timer) };
        }
    }

    fn on_wake(&self) {
        self.cancel_timer();
        if self.inner.borrow().session.is_none() {
            self.ensure_session();
            return;
        }
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
            });
        let Some(context) = context else { return };
        self.apply_late(&context);
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
        let (Some(engine), Some(session), true) = (engine, session, wants_wake) else {
            return;
        };
        let field = self.field_context(&context);
        if let Some(body) = engine
            .send(RequestBody::Wake {
                session,
                context: field,
            })
            .wait(RESPONSE_TIMEOUT)
        {
            self.apply_response(&context, body);
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
        if let Some(service) = Self::active() {
            let _ = service.engine_request(RequestBody::Menu { command });
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

unsafe extern "system" fn on_timer(_hwnd: HWND, _message: u32, timer: usize, _time: u32) {
    let _ = std::panic::catch_unwind(|| {
        let _ = unsafe { KillTimer(None, timer) };
        let service = ACTIVE.with(|active| active.borrow().clone());
        if let Some(service) = service {
            service.on_wake();
        }
    });
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
