use super::guard::guard;
use std::cell::RefCell;
use windows::Win32::UI::TextServices::{
    ITfContext, ITfEditSession, ITfEditSession_Impl, TF_CONTEXT_EDIT_CONTEXT_FLAGS,
};
use windows_core::{implement, Result};

type Body = Box<dyn FnOnce(u32) -> Result<()>>;

#[implement(ITfEditSession)]
struct EditSession {
    body: RefCell<Option<Body>>,
}

impl ITfEditSession_Impl for EditSession_Impl {
    fn DoEditSession(&self, ec: u32) -> Result<()> {
        guard(|| match self.body.borrow_mut().take() {
            Some(body) => body(ec),
            None => Ok(()),
        })
    }
}

pub fn request(
    context: &ITfContext,
    client_id: u32,
    flags: TF_CONTEXT_EDIT_CONTEXT_FLAGS,
    body: impl FnOnce(u32) -> Result<()> + 'static,
) -> Result<()> {
    let session: ITfEditSession = EditSession {
        body: RefCell::new(Some(Box::new(body))),
    }
    .into();
    let result = unsafe { context.RequestEditSession(client_id, &session, flags)? };
    result.ok()
}
