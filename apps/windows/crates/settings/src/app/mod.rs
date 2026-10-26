#![allow(unsafe_code)]

use crate::options::{self, INPUT_STYLES, THEMES};
use ipc::windows::{pipe_name, EngineClient};
use ipc::{RequestBody, ResponseBody, SettingsSnapshot};
use std::cell::RefCell;
use std::time::Duration;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::{CreateFontIndirectW, HFONT, LOGFONTW};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::HiDpi::{
    GetDpiForWindow, SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
};
use windows::Win32::UI::Input::KeyboardAndMouse::EnableWindow;
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DispatchMessageW, GetMessageW, PostQuitMessage,
    RegisterClassExW, SendMessageW, SetWindowPos, TranslateMessage, BM_GETCHECK, BM_SETCHECK,
    BN_CLICKED, BS_AUTOCHECKBOX, BS_PUSHBUTTON, CBN_SELCHANGE, CBS_DROPDOWNLIST, CB_ADDSTRING,
    CB_GETCURSEL, CB_SETCURSEL, CW_USEDEFAULT, HMENU, MSG, SWP_NOMOVE, SWP_NOZORDER, SW_SHOWNORMAL,
    WINDOW_EX_STYLE, WINDOW_STYLE, WM_COMMAND, WM_DESTROY, WM_SETFONT, WNDCLASSEXW, WS_CAPTION,
    WS_CHILD, WS_MINIMIZEBOX, WS_OVERLAPPED, WS_SYSMENU, WS_TABSTOP, WS_VISIBLE, WS_VSCROLL,
};
use windows_core::{w, Result, HSTRING, PCWSTR};

const TIMEOUT: Duration = Duration::from_secs(2);
const BASE_DPI: f32 = 96.0;
const WIDTH: i32 = 400;
const ROW: i32 = 32;
const MARGIN: i32 = 16;
const LABEL_WIDTH: i32 = 120;
const FONT_POINTS: i32 = 12;
const LIST_HEIGHT: i32 = 240;

const ID_THEME: u16 = 101;
const ID_INPUT_STYLE: u16 = 102;
const ID_FONT_SIZE: u16 = 103;
const ID_LIVE_CONVERSION: u16 = 104;
const ID_MODE_INDICATOR: u16 = 105;
const ID_KEY_HINTS: u16 = 106;
const ID_OPEN_FILE: u16 = 107;

struct Controls {
    theme: HWND,
    input_style: HWND,
    font_size: HWND,
    live_conversion: HWND,
    mode_indicator: HWND,
    key_hints: HWND,
}

struct App {
    client: Option<EngineClient>,
    snapshot: Option<SettingsSnapshot>,
    controls: Option<Controls>,
    sizes: Vec<u32>,
}

thread_local! {
    static APP: RefCell<App> = RefCell::new(App {
        client: None,
        snapshot: None,
        controls: None,
        sizes: options::font_sizes(),
    });
}

pub fn run() {
    let _ = unsafe { SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) };
    let client = pipe_name("engine")
        .ok()
        .and_then(|name| EngineClient::start(name).ok());
    let snapshot = client.as_ref().and_then(|client| {
        match client.send(RequestBody::ReadSettings).wait(TIMEOUT) {
            Some(ResponseBody::Settings { settings }) => Some(settings),
            _ => None,
        }
    });
    APP.with(|app| {
        let mut app = app.borrow_mut();
        app.client = client;
        app.snapshot = snapshot;
    });
    if create_window().is_err() {
        return;
    }
    let mut message = MSG::default();
    while unsafe { GetMessageW(&mut message, None, 0, 0) }.as_bool() {
        unsafe {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

fn create_window() -> Result<()> {
    let instance = unsafe { GetModuleHandleW(None)? };
    let class = WNDCLASSEXW {
        cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
        lpfnWndProc: Some(procedure),
        hInstance: instance.into(),
        lpszClassName: w!("s90.tokyo-ime.settings"),
        hbrBackground: windows::Win32::Graphics::Gdi::HBRUSH(
            (windows::Win32::Graphics::Gdi::COLOR_WINDOW.0 + 1) as usize as *mut _,
        ),
        ..Default::default()
    };
    unsafe { RegisterClassExW(&class) };
    let window = unsafe {
        CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            w!("s90.tokyo-ime.settings"),
            &HSTRING::from(options::TITLE),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_VISIBLE,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            WIDTH,
            ROW * 8,
            None,
            None,
            Some(instance.into()),
            None,
        )?
    };
    let dpi = unsafe { GetDpiForWindow(window) };
    let scale = if dpi == 0 { 1.0 } else { dpi as f32 / BASE_DPI };
    let px = |value: i32| (value as f32 * scale).round() as i32;
    let font = create_font(px(FONT_POINTS));
    let mut y = MARGIN;
    let mut row = |label: &str, kind: Kind, id: u16| -> HWND {
        let control = match kind {
            Kind::Choice => {
                child(
                    window,
                    w!("STATIC"),
                    label,
                    WS_VISIBLE,
                    px(MARGIN),
                    px(y + 4),
                    px(LABEL_WIDTH),
                    px(ROW - 8),
                    0,
                    font,
                );
                child(
                    window,
                    w!("COMBOBOX"),
                    "",
                    WS_TABSTOP | WS_VSCROLL | WINDOW_STYLE(CBS_DROPDOWNLIST as u32),
                    px(MARGIN + LABEL_WIDTH),
                    px(y),
                    px(WIDTH - LABEL_WIDTH - MARGIN * 3),
                    px(LIST_HEIGHT),
                    id,
                    font,
                )
            }
            Kind::Check => child(
                window,
                w!("BUTTON"),
                label,
                WS_TABSTOP | WINDOW_STYLE(BS_AUTOCHECKBOX as u32),
                px(MARGIN),
                px(y),
                px(WIDTH - MARGIN * 3),
                px(ROW - 6),
                id,
                font,
            ),
            Kind::Button => child(
                window,
                w!("BUTTON"),
                label,
                WS_TABSTOP | WINDOW_STYLE(BS_PUSHBUTTON as u32),
                px(MARGIN),
                px(y + 4),
                px(WIDTH - MARGIN * 3),
                px(ROW - 4),
                id,
                font,
            ),
        };
        y += ROW;
        control
    };
    let theme = row(options::THEME, Kind::Choice, ID_THEME);
    let input_style = row(options::INPUT_STYLE, Kind::Choice, ID_INPUT_STYLE);
    let font_size = row(options::FONT_SIZE, Kind::Choice, ID_FONT_SIZE);
    let live_conversion = row(options::LIVE_CONVERSION, Kind::Check, ID_LIVE_CONVERSION);
    let mode_indicator = row(options::MODE_INDICATOR, Kind::Check, ID_MODE_INDICATOR);
    let key_hints = row(options::KEY_HINTS, Kind::Check, ID_KEY_HINTS);
    let _ = row(options::OPEN_FILE, Kind::Button, ID_OPEN_FILE);
    let height = y + MARGIN + ROW * 2;
    let _ = unsafe {
        SetWindowPos(
            window,
            None,
            0,
            0,
            px(WIDTH),
            px(height),
            SWP_NOMOVE | SWP_NOZORDER,
        )
    };

    let controls = Controls {
        theme,
        input_style,
        font_size,
        live_conversion,
        mode_indicator,
        key_hints,
    };
    APP.with(|app| {
        let mut app = app.borrow_mut();
        for (_, label) in THEMES {
            add_choice(controls.theme, label);
        }
        for (_, label) in INPUT_STYLES {
            add_choice(controls.input_style, label);
        }
        for size in &app.sizes {
            add_choice(controls.font_size, &size.to_string());
        }
        match &app.snapshot {
            Some(snapshot) => {
                select(controls.theme, options::index_of(THEMES, &snapshot.theme));
                select(
                    controls.input_style,
                    options::index_of(INPUT_STYLES, &snapshot.input_style),
                );
                select(
                    controls.font_size,
                    options::nearest_font_size(&app.sizes, snapshot.candidate_font_size),
                );
                check(controls.live_conversion, snapshot.live_conversion);
                check(controls.mode_indicator, snapshot.shows_mode_indicator);
                check(controls.key_hints, snapshot.shows_key_hints);
            }
            None => {
                for control in [
                    theme,
                    input_style,
                    font_size,
                    live_conversion,
                    mode_indicator,
                    key_hints,
                ] {
                    let _ = unsafe { EnableWindow(control, false) };
                }
                child(
                    window,
                    w!("STATIC"),
                    options::ENGINE_UNAVAILABLE,
                    WS_VISIBLE,
                    px(MARGIN),
                    px(y + 4),
                    px(WIDTH - MARGIN * 3),
                    px(ROW - 8),
                    0,
                    font,
                );
            }
        }
        app.controls = Some(controls);
    });
    Ok(())
}

enum Kind {
    Choice,
    Check,
    Button,
}

#[allow(clippy::too_many_arguments)]
fn child(
    parent: HWND,
    class: PCWSTR,
    text: &str,
    style: WINDOW_STYLE,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    id: u16,
    font: Option<HFONT>,
) -> HWND {
    let control = unsafe {
        CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            class,
            &HSTRING::from(text),
            WS_CHILD | WS_VISIBLE | style,
            x,
            y,
            width,
            height,
            Some(parent),
            Some(HMENU(id as usize as *mut _)),
            None,
            None,
        )
    }
    .unwrap_or_default();
    if let Some(font) = font {
        unsafe {
            SendMessageW(
                control,
                WM_SETFONT,
                Some(WPARAM(font.0 as usize)),
                Some(LPARAM(1)),
            )
        };
    }
    control
}

fn create_font(height: i32) -> Option<HFONT> {
    let mut face = [0u16; 32];
    for (slot, unit) in face.iter_mut().zip("Yu Gothic UI".encode_utf16()) {
        *slot = unit;
    }
    let font = unsafe {
        CreateFontIndirectW(&LOGFONTW {
            lfHeight: -height,
            lfFaceName: face,
            ..Default::default()
        })
    };
    (!font.is_invalid()).then_some(font)
}

fn add_choice(combo: HWND, label: &str) {
    let text = HSTRING::from(label);
    unsafe {
        SendMessageW(
            combo,
            CB_ADDSTRING,
            None,
            Some(LPARAM(text.as_ptr() as isize)),
        )
    };
}

fn select(combo: HWND, index: usize) {
    unsafe { SendMessageW(combo, CB_SETCURSEL, Some(WPARAM(index)), None) };
}

fn selected(combo: HWND) -> usize {
    let result = unsafe { SendMessageW(combo, CB_GETCURSEL, None, None) };
    usize::try_from(result.0).unwrap_or(0)
}

fn check(button: HWND, on: bool) {
    unsafe { SendMessageW(button, BM_SETCHECK, Some(WPARAM(usize::from(on))), None) };
}

fn checked(button: HWND) -> bool {
    unsafe { SendMessageW(button, BM_GETCHECK, None, None) }.0 == 1
}

fn save() {
    APP.with(|app| {
        let mut app = app.borrow_mut();
        let (Some(controls), Some(mut snapshot)) = (app.controls.as_ref(), app.snapshot.clone())
        else {
            return;
        };
        snapshot.theme = THEMES[selected(controls.theme).min(THEMES.len() - 1)]
            .0
            .to_string();
        snapshot.input_style = INPUT_STYLES
            [selected(controls.input_style).min(INPUT_STYLES.len() - 1)]
        .0
        .to_string();
        if let Some(size) = app.sizes.get(selected(controls.font_size)) {
            snapshot.candidate_font_size = f64::from(*size);
        }
        snapshot.live_conversion = checked(controls.live_conversion);
        snapshot.shows_mode_indicator = checked(controls.mode_indicator);
        snapshot.shows_key_hints = checked(controls.key_hints);
        let written = app.client.as_ref().and_then(|client| {
            match client
                .send(RequestBody::WriteSettings { settings: snapshot })
                .wait(TIMEOUT)
            {
                Some(ResponseBody::Settings { settings }) => Some(settings),
                _ => None,
            }
        });
        if written.is_some() {
            app.snapshot = written;
        }
    });
}

fn open_file() {
    let Some(path) = std::env::var_os("APPDATA").map(|base| {
        std::path::PathBuf::from(base)
            .join("s90.tokyo")
            .join("IME")
            .join("settings.json")
    }) else {
        return;
    };
    if !path.exists() {
        return;
    }
    let path = HSTRING::from(path.as_os_str());
    unsafe { ShellExecuteW(None, w!("open"), &path, None, None, SW_SHOWNORMAL) };
}

unsafe extern "system" fn procedure(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| match message {
        WM_COMMAND => {
            let id = (wparam.0 & 0xffff) as u16;
            let notification = ((wparam.0 >> 16) & 0xffff) as u32;
            match (id, notification) {
                (ID_THEME | ID_INPUT_STYLE | ID_FONT_SIZE, CBN_SELCHANGE) => save(),
                (ID_LIVE_CONVERSION | ID_MODE_INDICATOR | ID_KEY_HINTS, BN_CLICKED) => save(),
                (ID_OPEN_FILE, BN_CLICKED) => open_file(),
                _ => {}
            }
            Some(LRESULT(0))
        }
        WM_DESTROY => {
            unsafe { PostQuitMessage(0) };
            Some(LRESULT(0))
        }
        _ => None,
    });
    match handled {
        Ok(Some(result)) => result,
        _ => unsafe { DefWindowProcW(hwnd, message, wparam, lparam) },
    }
}
