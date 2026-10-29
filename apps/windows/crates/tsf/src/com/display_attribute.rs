use super::guard::guard;
use super::ids::{
    GUID_ATTRIBUTE_CONVERTED, GUID_ATTRIBUTE_CORRECTION, GUID_ATTRIBUTE_FOCUSED,
    GUID_ATTRIBUTE_READING,
};
use ipc::TextStyle;
use std::cell::Cell;
use windows::Win32::Foundation::E_INVALIDARG;
use windows::Win32::UI::TextServices::{
    IEnumTfDisplayAttributeInfo, IEnumTfDisplayAttributeInfo_Impl, ITfDisplayAttributeInfo,
    ITfDisplayAttributeInfo_Impl, TF_ATTR_CONVERTED, TF_ATTR_INPUT, TF_ATTR_TARGET_CONVERTED,
    TF_CT_NONE, TF_DA_ATTR_INFO, TF_DA_COLOR, TF_DA_COLOR_0, TF_DA_LINESTYLE, TF_DISPLAYATTRIBUTE,
    TF_LS_DOT, TF_LS_SOLID,
};
use windows_core::{implement, Error, Result, BOOL, BSTR, GUID};

pub const STYLES: [TextStyle; 4] = [
    TextStyle::Reading,
    TextStyle::Converted,
    TextStyle::Focused,
    TextStyle::Correction,
];

pub fn guid(style: TextStyle) -> GUID {
    match style {
        TextStyle::Reading => GUID_ATTRIBUTE_READING,
        TextStyle::Converted => GUID_ATTRIBUTE_CONVERTED,
        TextStyle::Focused => GUID_ATTRIBUTE_FOCUSED,
        TextStyle::Correction => GUID_ATTRIBUTE_CORRECTION,
    }
}

fn attribute(style: TextStyle) -> TF_DISPLAYATTRIBUTE {
    let (line, bold, info): (TF_DA_LINESTYLE, bool, TF_DA_ATTR_INFO) = match style {
        TextStyle::Reading => (TF_LS_SOLID, false, TF_ATTR_INPUT),
        TextStyle::Converted => (TF_LS_SOLID, false, TF_ATTR_CONVERTED),
        TextStyle::Focused => (TF_LS_SOLID, true, TF_ATTR_TARGET_CONVERTED),
        TextStyle::Correction => (TF_LS_DOT, false, TF_ATTR_INPUT),
    };
    let none = TF_DA_COLOR {
        r#type: TF_CT_NONE,
        Anonymous: TF_DA_COLOR_0 { nIndex: 0 },
    };
    TF_DISPLAYATTRIBUTE {
        crText: none,
        crBk: none,
        lsStyle: line,
        fBoldLine: BOOL::from(bold),
        crLine: none,
        bAttr: info,
    }
}

fn style_of(guid: &GUID) -> Option<TextStyle> {
    STYLES.into_iter().find(|style| self::guid(*style) == *guid)
}

pub fn info(guid: &GUID) -> Result<ITfDisplayAttributeInfo> {
    let style = style_of(guid).ok_or_else(|| Error::from(E_INVALIDARG))?;
    Ok(DisplayAttributeInfo { style }.into())
}

pub fn enumerate() -> IEnumTfDisplayAttributeInfo {
    EnumDisplayAttributeInfo {
        index: Cell::new(0),
    }
    .into()
}

#[implement(ITfDisplayAttributeInfo)]
struct DisplayAttributeInfo {
    style: TextStyle,
}

impl ITfDisplayAttributeInfo_Impl for DisplayAttributeInfo_Impl {
    fn GetGUID(&self) -> Result<GUID> {
        Ok(guid(self.style))
    }

    fn GetDescription(&self) -> Result<BSTR> {
        Ok(BSTR::from("Hajime"))
    }

    fn GetAttributeInfo(&self, pda: *mut TF_DISPLAYATTRIBUTE) -> Result<()> {
        guard(|| {
            if pda.is_null() {
                return Err(Error::from(E_INVALIDARG));
            }
            unsafe { *pda = attribute(self.style) };
            Ok(())
        })
    }

    fn SetAttributeInfo(&self, _pda: *const TF_DISPLAYATTRIBUTE) -> Result<()> {
        Ok(())
    }

    fn Reset(&self) -> Result<()> {
        Ok(())
    }
}

#[implement(IEnumTfDisplayAttributeInfo)]
struct EnumDisplayAttributeInfo {
    index: Cell<usize>,
}

impl IEnumTfDisplayAttributeInfo_Impl for EnumDisplayAttributeInfo_Impl {
    fn Clone(&self) -> Result<IEnumTfDisplayAttributeInfo> {
        Ok(EnumDisplayAttributeInfo {
            index: Cell::new(self.index.get()),
        }
        .into())
    }

    fn Next(
        &self,
        ulcount: u32,
        rginfo: *mut Option<ITfDisplayAttributeInfo>,
        pcfetched: *mut u32,
    ) -> Result<()> {
        guard(|| {
            if rginfo.is_null() {
                return Err(Error::from(E_INVALIDARG));
            }
            let mut fetched = 0u32;
            while fetched < ulcount {
                let Some(style) = STYLES.get(self.index.get()).copied() else {
                    break;
                };
                let info: ITfDisplayAttributeInfo = DisplayAttributeInfo { style }.into();
                unsafe { rginfo.add(fetched as usize).write(Some(info)) };
                fetched += 1;
                self.index.set(self.index.get() + 1);
            }
            if !pcfetched.is_null() {
                unsafe { *pcfetched = fetched };
            }
            if fetched == ulcount {
                Ok(())
            } else {
                Err(Error::from(windows::Win32::Foundation::S_FALSE))
            }
        })
    }

    fn Reset(&self) -> Result<()> {
        self.index.set(0);
        Ok(())
    }

    fn Skip(&self, ulcount: u32) -> Result<()> {
        self.index
            .set(self.index.get().saturating_add(ulcount as usize));
        Ok(())
    }
}
