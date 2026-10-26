use super::factory::ClassFactory;
use super::guard::guard;
use super::ids::CLSID_TEXT_SERVICE;
use super::registration;
use std::ffi::c_void;
use windows::Win32::Foundation::{CLASS_E_CLASSNOTAVAILABLE, E_POINTER, S_FALSE, S_OK};
use windows::Win32::System::Ole::SELFREG_E_CLASS;
use windows_core::{Error, Interface, GUID, HRESULT};

#[no_mangle]
pub unsafe extern "system" fn DllGetClassObject(
    rclsid: *const GUID,
    riid: *const GUID,
    ppv: *mut *mut c_void,
) -> HRESULT {
    let result = guard(|| {
        if rclsid.is_null() || riid.is_null() || ppv.is_null() {
            return Err(Error::from(E_POINTER));
        }
        unsafe { *ppv = std::ptr::null_mut() };
        if unsafe { *rclsid } != CLSID_TEXT_SERVICE {
            return Err(Error::from(CLASS_E_CLASSNOTAVAILABLE));
        }
        let factory = ClassFactory::create();
        unsafe { factory.query(riid, ppv).ok() }
    });
    match result {
        Ok(()) => S_OK,
        Err(error) => error.code(),
    }
}

#[no_mangle]
pub extern "system" fn DllCanUnloadNow() -> HRESULT {
    S_FALSE
}

#[no_mangle]
pub extern "system" fn DllRegisterServer() -> HRESULT {
    match guard(registration::register) {
        Ok(()) => S_OK,
        Err(_) => SELFREG_E_CLASS,
    }
}

#[no_mangle]
pub extern "system" fn DllUnregisterServer() -> HRESULT {
    match guard(registration::unregister) {
        Ok(()) => S_OK,
        Err(_) => SELFREG_E_CLASS,
    }
}
