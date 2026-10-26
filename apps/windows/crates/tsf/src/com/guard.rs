use std::panic::{catch_unwind, AssertUnwindSafe};
use windows::Win32::Foundation::E_FAIL;
use windows_core::{Error, Result};

pub fn guard<T>(body: impl FnOnce() -> Result<T>) -> Result<T> {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(result) => result,
        Err(_) => Err(Error::from(E_FAIL)),
    }
}
