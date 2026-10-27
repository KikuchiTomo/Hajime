// UI Automation の定数は Windows の名前のまま使う
#![allow(non_upper_case_globals)]

//! UI Automation(ナレーターなどの読み上げ)．自分で描いた部品を，名前・役割・状態を持つ要素として見せる．
//! 要素の中身は窓(App)に毎回聞く(状態を写して持たない)．呼び出しは COM で UI スレッドに回してもらう
//! (ProviderOptions_UseComThreading)．入力した中身は名前に入れない(打つ欄は標準の EDIT が自分で読ませる)

use std::cell::{Cell, RefCell};
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Foundation::{VARIANT_FALSE, VARIANT_TRUE};
use windows::Win32::System::Com::SAFEARRAY;
use windows::Win32::System::Ole::{SafeArrayCreateVector, SafeArrayPutElement};
use windows::Win32::System::Variant::{VARIANT, VT_BOOL, VT_BSTR, VT_I4};
use windows::Win32::UI::Accessibility::{
    ExpandCollapseState, ExpandCollapseState_Collapsed, ExpandCollapseState_Expanded,
    ExpandCollapseState_LeafNode, IExpandCollapseProvider, IExpandCollapseProvider_Impl,
    IInvokeProvider, IInvokeProvider_Impl, IRawElementProviderFragment,
    IRawElementProviderFragmentRoot, IRawElementProviderFragmentRoot_Impl,
    IRawElementProviderFragment_Impl, IRawElementProviderSimple, IRawElementProviderSimple_Impl,
    ISelectionItemProvider, ISelectionItemProvider_Impl, IToggleProvider, IToggleProvider_Impl,
    IValueProvider, IValueProvider_Impl, NavigateDirection, NavigateDirection_FirstChild,
    NavigateDirection_LastChild, NavigateDirection_NextSibling, NavigateDirection_Parent,
    NavigateDirection_PreviousSibling, ProviderOptions, ProviderOptions_ServerSideProvider,
    ProviderOptions_UseComThreading, ToggleState, ToggleState_Off, ToggleState_On,
    UIA_AutomationFocusChangedEventId, UIA_AutomationIdPropertyId, UIA_ButtonControlTypeId,
    UIA_CheckBoxControlTypeId, UIA_ComboBoxControlTypeId, UIA_ControlTypePropertyId,
    UIA_DocumentControlTypeId, UIA_EditControlTypeId, UIA_ExpandCollapsePatternId,
    UIA_HasKeyboardFocusPropertyId, UIA_InvokePatternId, UIA_IsEnabledPropertyId,
    UIA_IsKeyboardFocusablePropertyId, UIA_ListControlTypeId, UIA_ListItemControlTypeId,
    UIA_NamePropertyId, UIA_SelectionItemPatternId, UIA_TogglePatternId, UIA_ValuePatternId,
    UiaAppendRuntimeId, UiaClientsAreListening, UiaHostProviderFromHwnd, UiaRaiseAutomationEvent,
    UiaRect, UiaReturnRawElementProvider, UiaRootObjectId, UIA_E_ELEMENTNOTAVAILABLE,
    UIA_PATTERN_ID, UIA_PROPERTY_ID,
};
use windows_core::{
    implement, ComObject, Error, IUnknown, IUnknownImpl, Result, BOOL, BSTR, HRESULT, PCWSTR,
};

/// 要素の役割
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Button,
    CheckBox,
    ComboBox,
    ListItem,
    List,
    Document,
    /// 打つ欄．中身と操作は標準の EDIT が受け持つ(Node::host)
    Edit,
}

/// 要素(窓が今の状態から作る)
#[derive(Debug, Clone, PartialEq)]
pub struct Node {
    /// 窓の中で要素を見分ける番号
    pub id: i32,
    pub role: Role,
    pub name: String,
    /// 画面の中の位置(ピクセル．左・上・幅・高さ)
    pub rect: (i32, i32, i32, i32),
    pub enabled: bool,
    pub focused: bool,
    pub toggled: Option<bool>,
    pub expanded: Option<bool>,
    pub value: Option<String>,
    pub selected: Option<bool>,
    /// 要素の元になる標準の窓(打つ欄の EDIT)．値の読み書きなどはその窓が答える
    pub host: Option<HWND>,
}

/// 読み上げの側から頼まれる操作
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Act {
    Invoke,
    Toggle,
    Expand,
    Collapse,
    Select,
    Focus,
}

/// 窓に要素を聞く・操作を頼む口(窓が入れる)
#[derive(Clone, Copy)]
pub struct Hooks {
    pub nodes: fn() -> Vec<Node>,
    pub act: fn(i32, Act),
}

thread_local! {
    static HOOKS: Cell<Option<Hooks>> = const { Cell::new(None) };
    static ROOT: RefCell<Option<IRawElementProviderSimple>> = const { RefCell::new(None) };
}

pub fn install(hooks: Hooks) {
    HOOKS.with(|cell| cell.set(Some(hooks)));
}

fn nodes() -> Vec<Node> {
    HOOKS
        .with(Cell::get)
        .map(|hooks| (hooks.nodes)())
        .unwrap_or_default()
}

fn act(id: i32, act: Act) {
    if let Some(hooks) = HOOKS.with(Cell::get) {
        (hooks.act)(id, act);
    }
}

/// WM_GETOBJECT に答える．UI Automation の求めでなければ None(既定の扱い)
pub fn get_object(window: HWND, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
    if lparam.0 as i32 != UiaRootObjectId {
        return None;
    }
    let root = ROOT.with(|cell| {
        cell.borrow_mut()
            .get_or_insert_with(|| ComObject::new(Root { window }).to_interface())
            .clone()
    });
    // SAFETY: window はこのスレッドの窓．root は生きている COM の参照
    Some(unsafe { UiaReturnRawElementProvider(window, wparam, lparam, &root) })
}

/// 窓を消すときに，読み上げの側に渡した要素を放してもらう
pub fn disconnect(window: HWND) {
    ROOT.with(|cell| cell.borrow_mut().take());
    // SAFETY: window はこのスレッドの窓．要素を渡さずに呼ぶと，渡したものを放す
    unsafe {
        UiaReturnRawElementProvider(
            window,
            WPARAM(0),
            LPARAM(0),
            None::<&IRawElementProviderSimple>,
        );
    }
}

/// フォーカスが動いたことを知らせる(聞いている側がいるときだけ)
pub fn focus_changed(window: HWND, id: i32) {
    // SAFETY: 引数なしで状態を読むだけ
    if !unsafe { UiaClientsAreListening() }.as_bool() {
        return;
    }
    let provider: IRawElementProviderSimple =
        ComObject::new(NodeProvider { window, id }).to_interface();
    // SAFETY: provider は生きている COM の参照
    let _ = unsafe { UiaRaiseAutomationEvent(&provider, UIA_AutomationFocusChangedEventId) };
}

fn not_available() -> Error {
    Error::from(HRESULT(UIA_E_ELEMENTNOTAVAILABLE as i32))
}

/// 中身の無い(null の)返り値．windows-rs では S_OK の Err で null を返す
fn null<T>() -> Result<T> {
    Err(Error::empty())
}

fn variant_i32(value: i32) -> VARIANT {
    let mut variant = VARIANT::default();
    // SAFETY: 作ったばかりの VARIANT に型と値を書く
    unsafe {
        let inner = &mut *variant.Anonymous.Anonymous;
        inner.vt = VT_I4;
        inner.Anonymous.lVal = value;
    }
    variant
}

fn variant_bool(value: bool) -> VARIANT {
    let mut variant = VARIANT::default();
    // SAFETY: 同上
    unsafe {
        let inner = &mut *variant.Anonymous.Anonymous;
        inner.vt = VT_BOOL;
        inner.Anonymous.boolVal = if value { VARIANT_TRUE } else { VARIANT_FALSE };
    }
    variant
}

fn variant_text(value: &str) -> VARIANT {
    let mut variant = VARIANT::default();
    // SAFETY: 同上．BSTR は VARIANT が持ち，受け取った側が VariantClear で放す
    unsafe {
        let inner = &mut *variant.Anonymous.Anonymous;
        inner.vt = VT_BSTR;
        inner.Anonymous.bstrVal = std::mem::ManuallyDrop::new(BSTR::from(value));
    }
    variant
}

fn provider(window: HWND, id: i32) -> IRawElementProviderFragment {
    ComObject::new(NodeProvider { window, id }).to_interface()
}

/// 窓そのもの(要素の根)．名前などは窓から読む(UiaHostProviderFromHwnd)
#[implement(
    IRawElementProviderSimple,
    IRawElementProviderFragment,
    IRawElementProviderFragmentRoot
)]
struct Root {
    window: HWND,
}

impl IRawElementProviderSimple_Impl for Root_Impl {
    fn ProviderOptions(&self) -> Result<ProviderOptions> {
        Ok(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading)
    }

    fn GetPatternProvider(&self, _patternid: UIA_PATTERN_ID) -> Result<IUnknown> {
        null()
    }

    fn GetPropertyValue(&self, _propertyid: UIA_PROPERTY_ID) -> Result<VARIANT> {
        Ok(VARIANT::default())
    }

    fn HostRawElementProvider(&self) -> Result<IRawElementProviderSimple> {
        // SAFETY: window はこのプロセスの窓
        unsafe { UiaHostProviderFromHwnd(self.window) }
    }
}

impl IRawElementProviderFragment_Impl for Root_Impl {
    fn Navigate(&self, direction: NavigateDirection) -> Result<IRawElementProviderFragment> {
        let nodes = nodes();
        let node = match direction {
            NavigateDirection_FirstChild => nodes.first(),
            NavigateDirection_LastChild => nodes.last(),
            _ => None,
        };
        match node {
            Some(node) => Ok(provider(self.window, node.id)),
            None => null(),
        }
    }

    fn GetRuntimeId(&self) -> Result<*mut SAFEARRAY> {
        Ok(std::ptr::null_mut())
    }

    fn BoundingRectangle(&self) -> Result<UiaRect> {
        Ok(UiaRect::default())
    }

    fn GetEmbeddedFragmentRoots(&self) -> Result<*mut SAFEARRAY> {
        Ok(std::ptr::null_mut())
    }

    fn SetFocus(&self) -> Result<()> {
        Ok(())
    }

    fn FragmentRoot(&self) -> Result<IRawElementProviderFragmentRoot> {
        Ok(self.to_interface())
    }
}

impl IRawElementProviderFragmentRoot_Impl for Root_Impl {
    fn ElementProviderFromPoint(&self, x: f64, y: f64) -> Result<IRawElementProviderFragment> {
        let found = nodes().into_iter().find(|node| {
            let (left, top, width, height) = node.rect;
            x >= f64::from(left)
                && x < f64::from(left + width)
                && y >= f64::from(top)
                && y < f64::from(top + height)
        });
        match found {
            Some(node) => Ok(provider(self.window, node.id)),
            None => null(),
        }
    }

    fn GetFocus(&self) -> Result<IRawElementProviderFragment> {
        match nodes().into_iter().find(|node| node.focused) {
            Some(node) => Ok(provider(self.window, node.id)),
            None => null(),
        }
    }
}

/// 自分で描いた部品 1 つ
#[implement(
    IRawElementProviderSimple,
    IRawElementProviderFragment,
    IInvokeProvider,
    IToggleProvider,
    IExpandCollapseProvider,
    IValueProvider,
    ISelectionItemProvider
)]
struct NodeProvider {
    window: HWND,
    id: i32,
}

impl NodeProvider {
    fn node(&self) -> Result<Node> {
        nodes()
            .into_iter()
            .find(|node| node.id == self.id)
            .ok_or_else(not_available)
    }

    fn act(&self, value: Act) -> Result<()> {
        let node = self.node()?;
        if !node.enabled {
            return Err(Error::from(HRESULT(
                windows::Win32::UI::Accessibility::UIA_E_ELEMENTNOTENABLED as i32,
            )));
        }
        act(self.id, value);
        Ok(())
    }
}

impl IRawElementProviderSimple_Impl for NodeProvider_Impl {
    fn ProviderOptions(&self) -> Result<ProviderOptions> {
        Ok(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading)
    }

    fn GetPatternProvider(&self, patternid: UIA_PATTERN_ID) -> Result<IUnknown> {
        let node = self.node()?;
        let supported = match node.role {
            Role::Button => patternid == UIA_InvokePatternId,
            Role::CheckBox => patternid == UIA_TogglePatternId,
            Role::ComboBox => {
                patternid == UIA_ExpandCollapsePatternId || patternid == UIA_ValuePatternId
            }
            Role::ListItem => {
                patternid == UIA_SelectionItemPatternId || patternid == UIA_InvokePatternId
            }
            // 打つ欄の値の読み書きは標準の EDIT(host)が答える
            Role::List | Role::Document | Role::Edit => false,
        };
        if supported {
            Ok(self.to_interface())
        } else {
            null()
        }
    }

    fn GetPropertyValue(&self, propertyid: UIA_PROPERTY_ID) -> Result<VARIANT> {
        let node = self.node()?;
        let control_type = match node.role {
            Role::Button => UIA_ButtonControlTypeId,
            Role::CheckBox => UIA_CheckBoxControlTypeId,
            Role::ComboBox => UIA_ComboBoxControlTypeId,
            Role::ListItem => UIA_ListItemControlTypeId,
            Role::List => UIA_ListControlTypeId,
            Role::Document => UIA_DocumentControlTypeId,
            Role::Edit => UIA_EditControlTypeId,
        };
        Ok(match propertyid {
            UIA_NamePropertyId => variant_text(&node.name),
            UIA_ControlTypePropertyId => variant_i32(control_type.0),
            UIA_IsEnabledPropertyId => variant_bool(node.enabled),
            UIA_HasKeyboardFocusPropertyId => variant_bool(node.focused),
            UIA_IsKeyboardFocusablePropertyId => variant_bool(node.enabled),
            UIA_AutomationIdPropertyId => variant_text(&format!("s90.settings.{}", node.id)),
            _ => VARIANT::default(),
        })
    }

    fn HostRawElementProvider(&self) -> Result<IRawElementProviderSimple> {
        match self.node()?.host {
            // SAFETY: host はこのスレッドの窓(打つ欄)．標準の窓の読み上げを，この要素に重ねる
            Some(host) => unsafe { UiaHostProviderFromHwnd(host) },
            None => null(),
        }
    }
}

impl IRawElementProviderFragment_Impl for NodeProvider_Impl {
    fn Navigate(&self, direction: NavigateDirection) -> Result<IRawElementProviderFragment> {
        if direction == NavigateDirection_Parent {
            let root: IRawElementProviderFragment = ComObject::new(Root {
                window: self.window,
            })
            .to_interface();
            return Ok(root);
        }
        let nodes = nodes();
        let Some(index) = nodes.iter().position(|node| node.id == self.id) else {
            return Err(not_available());
        };
        let next = match direction {
            NavigateDirection_NextSibling => nodes.get(index + 1),
            NavigateDirection_PreviousSibling => {
                index.checked_sub(1).and_then(|index| nodes.get(index))
            }
            _ => None,
        };
        match next {
            Some(node) => Ok(provider(self.window, node.id)),
            None => null(),
        }
    }

    fn GetRuntimeId(&self) -> Result<*mut SAFEARRAY> {
        // SAFETY: 2 つの i32 の配列を作って値を入れる．受け取った側が放す
        unsafe {
            let array = SafeArrayCreateVector(VT_I4, 0, 2);
            if array.is_null() {
                return Err(Error::from(windows::Win32::Foundation::E_OUTOFMEMORY));
            }
            let parts = [UiaAppendRuntimeId as i32, self.id];
            for (index, value) in parts.iter().enumerate() {
                let index = index as i32;
                SafeArrayPutElement(array, &index, (value as *const i32).cast())?;
            }
            Ok(array)
        }
    }

    fn BoundingRectangle(&self) -> Result<UiaRect> {
        let node = self.node()?;
        let (left, top, width, height) = node.rect;
        Ok(UiaRect {
            left: f64::from(left),
            top: f64::from(top),
            width: f64::from(width),
            height: f64::from(height),
        })
    }

    fn GetEmbeddedFragmentRoots(&self) -> Result<*mut SAFEARRAY> {
        Ok(std::ptr::null_mut())
    }

    fn SetFocus(&self) -> Result<()> {
        self.act(Act::Focus)
    }

    fn FragmentRoot(&self) -> Result<IRawElementProviderFragmentRoot> {
        Ok(ComObject::new(Root {
            window: self.window,
        })
        .to_interface())
    }
}

impl IInvokeProvider_Impl for NodeProvider_Impl {
    fn Invoke(&self) -> Result<()> {
        self.act(Act::Invoke)
    }
}

impl IToggleProvider_Impl for NodeProvider_Impl {
    fn Toggle(&self) -> Result<()> {
        self.act(Act::Toggle)
    }

    fn ToggleState(&self) -> Result<ToggleState> {
        Ok(if self.node()?.toggled == Some(true) {
            ToggleState_On
        } else {
            ToggleState_Off
        })
    }
}

impl IExpandCollapseProvider_Impl for NodeProvider_Impl {
    fn Expand(&self) -> Result<()> {
        self.act(Act::Expand)
    }

    fn Collapse(&self) -> Result<()> {
        self.act(Act::Collapse)
    }

    fn ExpandCollapseState(&self) -> Result<ExpandCollapseState> {
        Ok(match self.node()?.expanded {
            Some(true) => ExpandCollapseState_Expanded,
            Some(false) => ExpandCollapseState_Collapsed,
            None => ExpandCollapseState_LeafNode,
        })
    }
}

impl IValueProvider_Impl for NodeProvider_Impl {
    fn SetValue(&self, _val: &PCWSTR) -> Result<()> {
        Err(Error::from(windows::Win32::Foundation::E_ACCESSDENIED))
    }

    fn Value(&self) -> Result<BSTR> {
        Ok(BSTR::from(self.node()?.value.unwrap_or_default()))
    }

    fn IsReadOnly(&self) -> Result<BOOL> {
        Ok(true.into())
    }
}

impl ISelectionItemProvider_Impl for NodeProvider_Impl {
    fn Select(&self) -> Result<()> {
        self.act(Act::Select)
    }

    fn AddToSelection(&self) -> Result<()> {
        self.act(Act::Select)
    }

    fn RemoveFromSelection(&self) -> Result<()> {
        Ok(())
    }

    fn IsSelected(&self) -> Result<BOOL> {
        Ok((self.node()?.selected == Some(true)).into())
    }

    fn SelectionContainer(&self) -> Result<IRawElementProviderSimple> {
        null()
    }
}
