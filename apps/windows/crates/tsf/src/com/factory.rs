use super::guard::guard;
use super::text_service::TextService;
use std::ffi::c_void;
use windows::Win32::Foundation::{CLASS_E_NOAGGREGATION, E_POINTER};
use windows::Win32::System::Com::{IClassFactory, IClassFactory_Impl};
use windows_core::{implement, Error, IUnknown, Interface, Ref, Result, BOOL, GUID};

#[implement(IClassFactory)]
pub struct ClassFactory;

impl ClassFactory {
    pub fn create() -> IClassFactory {
        ClassFactory.into()
    }
}

impl IClassFactory_Impl for ClassFactory_Impl {
    fn CreateInstance(
        &self,
        punkouter: Ref<IUnknown>,
        riid: *const GUID,
        ppvobject: *mut *mut c_void,
    ) -> Result<()> {
        guard(|| {
            if ppvobject.is_null() || riid.is_null() {
                return Err(Error::from(E_POINTER));
            }
            unsafe { *ppvobject = std::ptr::null_mut() };
            if !punkouter.is_null() {
                return Err(Error::from(CLASS_E_NOAGGREGATION));
            }
            let service: IUnknown = TextService::default().into();
            unsafe { service.query(riid, ppvobject).ok() }
        })
    }

    fn LockServer(&self, _flock: BOOL) -> Result<()> {
        Ok(())
    }
}
