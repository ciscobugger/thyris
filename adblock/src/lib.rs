//! C interface over Brave's adblock engine for the Qt launcher: network checks and per-URL cosmetics.
use adblock::lists::{FilterSet, ParseOptions};
use adblock::request::Request;
use adblock::resources::{PermissionMask, Resource};
use adblock::Engine;
use std::ffi::{c_char, CStr, CString};

fn s<'a>(p: *const c_char) -> &'a str {
    if p.is_null() { "" } else { unsafe { CStr::from_ptr(p) }.to_str().unwrap_or("") }
}

/// `trusted`: uBlock Origin's own lists, allowed to use trusted scriptlets (permission bit 1, like
/// uBO's requiresTrust); `other`: third-party lists (EasyList etc.); `resources_json`: scriptlets/redirects.
#[no_mangle]
pub extern "C" fn ab_new(trusted: *const c_char, other: *const c_char, resources_json: *const c_char) -> *mut Engine {
    let mut set = FilterSet::new(false);
    let trusted_opts = ParseOptions { permissions: PermissionMask::from_bits(1), ..ParseOptions::default() };
    set.add_filter_list(s(trusted).to_string(), trusted_opts);
    set.add_filter_list(s(other).to_string(), ParseOptions::default());
    let mut engine = Engine::new_with_filter_set(set);
    match serde_json::from_str::<Vec<Resource>>(s(resources_json)) {
        Ok(res) => { eprintln!("ADBLOCK resources {}", res.len()); engine.use_resources(res) }
        Err(e) => eprintln!("ADBLOCK resources not loaded: {e}"),
    }
    Box::into_raw(Box::new(engine))
}

/// The whole decision on a request, as uBlock Origin makes it: 0 allow, 1 block, 2 block but give the page `*out` in its
/// place (a data: URL, the stand-in a `redirect`/`redirect-rule` filter names), 3 load `*out` instead (the address without
/// what `removeparam` filters strip). `*out` is set for 2 and 3 only; free it with ab_free.
#[no_mangle]
pub extern "C" fn ab_decide(e: *const Engine, url: *const c_char, source: *const c_char, kind: *const c_char,
                            out: *mut *mut c_char) -> i32 {
    let engine = unsafe { &*e };
    unsafe { *out = std::ptr::null_mut() };
    let give = |v: String| unsafe { *out = CString::new(v).unwrap_or_default().into_raw() };
    let Ok(r) = Request::new(s(url), s(source), s(kind), "GET") else { return 0 };
    let result = engine.check_network_request(&r);
    if result.should_block() {
        if let Some(redirect) = result.redirect {
            give(redirect);
            return 2;
        }
        return 1;
    }
    if let Some(rewritten) = result.rewritten_url {
        give(rewritten);
        return 3;
    }
    0
}

/// JSON {"hide": [selectors], "script": "..."} for a page URL; free with ab_free.
#[no_mangle]
pub extern "C" fn ab_cosmetic(e: *const Engine, url: *const c_char) -> *mut c_char {
    let engine = unsafe { &*e };
    let r = engine.url_cosmetic_resources(s(url));
    let out = serde_json::json!({ "hide": r.hide_selectors, "script": r.injected_script });
    CString::new(out.to_string()).unwrap_or_default().into_raw()
}

#[no_mangle]
pub extern "C" fn ab_free(p: *mut c_char) {
    if !p.is_null() { unsafe { drop(CString::from_raw(p)) } }
}

#[no_mangle]
pub extern "C" fn ab_drop(e: *mut Engine) {
    if !e.is_null() { unsafe { drop(Box::from_raw(e)) } }
}
