//! C interface to fsearch for the Launch app. Everything crosses the boundary
//! as C strings holding JSON, so the surface stays small; Swift decodes it.
//!
//! No call may unwind into Swift: each one runs inside `catch_unwind`.

use fsearch::walk::{KIND_DIR, KIND_FILE, KIND_LINK};
use fsearch::{Engine, Options, Query};
use serde::Serialize;
use std::borrow::Cow;
use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::ptr::null_mut;
use std::time::{Duration, Instant};

/// Opaque to C; the header declares it as `lf_engine`.
pub struct LfEngine {
    engine: Engine,
    /// Whether the app had Full Disk Access when the engine started. fsearch
    /// derives its own flag from an empty skip list, which is never empty
    /// here (see `skip_list`), so the wrapper keeps the real answer.
    full_disk_access: bool,
}

/// Folders the engine never opens, relative to home, with or without Full
/// Disk Access. macOS asks the user for permission whenever an app so much as
/// opens `~/Pictures` (Photos), `~/Movies` or `~/Music` (Media & Apple Music),
/// separately from Full Disk Access, and again at every launch for builds
/// signed ad hoc. Skipping the library packages inside them is not enough:
/// opening the folder is what triggers it (found by tracing the scan against
/// the permission log). `~/Library` holds nearly all the other guarded app
/// data (Photos' Syndication library, containers, Mail, ...) and nothing a
/// launcher is asked to find. Files in these folders are therefore not
/// searchable until there is a setting that asks for the permission.
const NEVER_INDEXED: &[&str] = &["Library", "Pictures", "Movies", "Music"];

/// System folders, absolute, that no launcher search needs and that macOS
/// guards (data vaults of the media, Photos and analytics daemons). Without
/// this the first scan is refused by each, and the refusals can prompt.
const SYSTEM_NEVER_INDEXED: &[&str] =
    &["/Library/Caches", "/Library/Bluetooth", "/Library/Trial", "/private/var/protected", "/private/var/containers", "/private/var/folders"];

/// What the engine must not open: the media libraries always, and the
/// consent-gated folders (Desktop, Documents, ...) unless Full Disk Access
/// covers them.
fn skip_list(home: &str, full_disk_access: bool) -> Vec<PathBuf> {
    use std::os::unix::ffi::OsStrExt;
    let gated = if full_disk_access { Vec::new() } else { fsearch::gated(home) };
    gated
        .into_iter()
        .map(|p| PathBuf::from(std::ffi::OsStr::from_bytes(&p)))
        .chain(NEVER_INDEXED.iter().map(|rel| PathBuf::from(home).join(rel)))
        .chain(SYSTEM_NEVER_INDEXED.iter().map(PathBuf::from))
        .collect()
}

fn guard<T>(fallback: T, f: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(fallback)
}

/// # Safety
/// `p` is NULL or a NUL-terminated string that outlives `'a`.
unsafe fn str_arg<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

fn to_c(s: impl Into<Vec<u8>>) -> *mut c_char {
    let mut bytes: Vec<u8> = s.into();
    bytes.retain(|&b| b != 0);
    CString::new(bytes).map(CString::into_raw).unwrap_or(null_mut())
}

fn json_c(v: &impl Serialize) -> *mut c_char {
    match serde_json::to_vec(v) {
        Ok(bytes) => to_c(bytes),
        Err(_) => null_mut(),
    }
}

fn set_error(out: *mut *mut c_char, msg: &str) {
    if !out.is_null() {
        unsafe { *out = to_c(msg) };
    }
}

/// # Safety
/// `home` and `dir` are NUL-terminated strings; `error_out` is NULL or valid to write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lf_start(home: *const c_char, dir: *const c_char, error_out: *mut *mut c_char) -> *mut LfEngine {
    guard(null_mut(), || {
        if !error_out.is_null() {
            unsafe { *error_out = null_mut() };
        }
        let (Some(home), Some(dir)) = (unsafe { str_arg(home) }, unsafe { str_arg(dir) }) else {
            set_error(error_out, "home and dir must be UTF-8 strings");
            return null_mut();
        };
        let full_disk_access = fsearch::has_full_disk_access();
        let skip = skip_list(home, full_disk_access);
        reset_index_if_skip_list_changed(std::path::Path::new(dir), &skip);
        let opts = Options { dir: PathBuf::from(dir), home: home.to_string(), skip: Some(skip) };
        match Engine::start(opts) {
            Ok(engine) => Box::into_raw(Box::new(LfEngine { engine, full_disk_access })),
            Err(e) => {
                set_error(error_out, &e);
                null_mut()
            }
        }
    })
}

/// An index built under one skip list is wrong under another: it still holds
/// entries inside folders that are now off limits, and on every start fsearch
/// re-checks each indexed file (touching the Photos and Music libraries, which
/// makes macOS ask for permission again and again). So the index remembers
/// the list that built it, and is thrown away and rebuilt (seconds) when the
/// list differs. Also covers Full Disk Access being granted or revoked, which
/// changes the list.
///
/// Does nothing if another process is running on this index (it holds the
/// lock), so a second copy of the app can't delete files in use.
fn reset_index_if_skip_list_changed(dir: &std::path::Path, skip: &[PathBuf]) {
    use std::os::fd::AsRawFd;

    let mut lines: Vec<String> = skip.iter().map(|p| p.to_string_lossy().into_owned()).collect();
    lines.sort();
    let fingerprint = lines.join("\n");
    let marker = dir.join("skip-list");
    if std::fs::read_to_string(&marker).ok().as_deref() == Some(fingerprint.as_str()) {
        return;
    }
    let _ = std::fs::create_dir_all(dir);
    let Ok(lock) = std::fs::OpenOptions::new().write(true).create(true).truncate(false).open(dir.join("daemon.lock")) else { return };
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return;
    }
    let _ = std::fs::remove_file(dir.join("index.bin"));
    let _ = std::fs::remove_file(dir.join("skipped"));
    let _ = std::fs::remove_dir_all(dir.join("content"));
    let _ = std::fs::write(&marker, fingerprint);
    // `lock` drops here, releasing the flock for Engine::start.
}

#[derive(Serialize)]
struct Hit<'a> {
    path: Cow<'a, str>,
    kind: &'static str,
    size: u64,
    mtime: u32,
    score: i32,
}

#[derive(Serialize)]
struct SearchReply<'a> {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    /// The first index is still being built.
    indexing: bool,
    took_us: u64,
    hits: Vec<Hit<'a>>,
}

fn kind_name(kind: u8) -> &'static str {
    match kind & 3 {
        KIND_FILE => "file",
        KIND_DIR => "dir",
        KIND_LINK => "link",
        _ => "other",
    }
}

/// # Safety
/// `engine` came from `lf_start` and was not stopped; `query` is a NUL-terminated string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lf_search(engine: *mut LfEngine, query: *const c_char, limit: u32) -> *mut c_char {
    guard(null_mut(), || {
        let Some(h) = (unsafe { engine.as_ref() }) else { return null_mut() };
        let engine = &h.engine;
        let failure = |error: String, indexing: bool| {
            json_c(&SearchReply { ok: false, error: Some(error), indexing, took_us: 0, hits: vec![] })
        };
        let Some(text) = (unsafe { str_arg(query) }) else { return failure("query must be UTF-8".into(), false) };
        let mut q = match Query::parse(text, engine.home()) {
            Ok(q) => q,
            Err(e) => return failure(e, false),
        };
        if limit > 0 {
            q.limit = limit as usize;
        }
        let started = Instant::now();
        match engine.search(&q) {
            Ok(found) => {
                let hits = found
                    .iter()
                    .map(|f| Hit { kind: kind_name(f.kind), size: f.size, mtime: f.mtime, score: f.score, path: f.path.to_string_lossy() })
                    .collect();
                json_c(&SearchReply { ok: true, error: None, indexing: false, took_us: started.elapsed().as_micros() as u64, hits })
            }
            Err(e) => failure(e, !engine.status().ready),
        }
    })
}

/// # Safety
/// `engine` came from `lf_start` and was not stopped.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lf_status(engine: *mut LfEngine) -> *mut c_char {
    guard(null_mut(), || {
        let Some(h) = (unsafe { engine.as_ref() }) else { return null_mut() };
        let status = h.engine.status();
        let ready = status.ready;
        let Ok(mut v) = serde_json::to_value(status) else { return null_mut() };
        v["ready"] = ready.into();
        v["full_disk_access"] = h.full_disk_access.into();
        v["progress"] = if ready { serde_json::Value::Null } else { h.engine.indexing().into() };
        json_c(&v)
    })
}

/// # Safety
/// `engine` came from `lf_start` and was not stopped.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lf_keep_warm(engine: *mut LfEngine, milliseconds: u32) {
    guard((), || {
        if let Some(h) = unsafe { engine.as_ref() } {
            h.engine.keep_warm(Duration::from_millis(milliseconds.into()));
        }
    })
}

/// # Safety
/// `engine` came from `lf_start` and was not stopped.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lf_save(engine: *mut LfEngine) {
    guard((), || {
        if let Some(h) = unsafe { engine.as_ref() } {
            h.engine.save();
        }
    })
}

/// # Safety
/// `s` is NULL or a string returned by this library, not yet freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lf_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(unsafe { CString::from_raw(s) });
    }
}

/// # Safety
/// `engine` is NULL or came from `lf_start`; it is not used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn lf_stop(engine: *mut LfEngine) {
    guard((), || {
        if engine.is_null() {
            return;
        }
        let h = unsafe { Box::from_raw(engine) };
        h.engine.save();
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn has(list: &[PathBuf], tail: &str) -> bool {
        list.iter().any(|p| p.ends_with(tail))
    }

    #[test]
    fn media_folders_and_library_are_skipped_with_or_without_full_disk_access() {
        for fda in [false, true] {
            let list = skip_list("/Users/me", fda);
            assert!(list.contains(&PathBuf::from("/Users/me/Library")), "~/Library, fda={fda}");
            for folder in ["Pictures", "Movies", "Music"] {
                assert!(list.contains(&PathBuf::from("/Users/me").join(folder)), "{folder}, fda={fda}");
            }
        }
    }

    #[test]
    fn consent_gated_folders_are_skipped_only_without_full_disk_access() {
        assert!(has(&skip_list("/Users/me", false), "Desktop"));
        assert!(has(&skip_list("/Users/me", false), "Documents"));
        assert!(!has(&skip_list("/Users/me", true), "Desktop"));
        assert!(!has(&skip_list("/Users/me", true), "Documents"));
    }

    #[test]
    fn protected_system_folders_are_skipped() {
        let list = skip_list("/Users/me", true);
        for p in ["/Library/Caches", "/private/var/protected", "/private/var/folders"] {
            assert!(list.contains(&PathBuf::from(p)), "{p}");
        }
        // But not the places users do search.
        assert!(!list.contains(&PathBuf::from("/Library")));
        assert!(!list.contains(&PathBuf::from("/Applications")));
    }

    fn scratch_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("launch-fsearch-ffi-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("content")).unwrap();
        dir
    }

    fn fill(dir: &std::path::Path) {
        std::fs::create_dir_all(dir.join("content")).unwrap();
        std::fs::write(dir.join("index.bin"), b"old").unwrap();
        std::fs::write(dir.join("content").join("seg"), b"old").unwrap();
    }

    #[test]
    fn index_is_rebuilt_when_the_skip_list_changes_and_kept_otherwise() {
        let dir = scratch_dir("reset");
        let a = vec![PathBuf::from("/Users/me/Library")];
        let b = vec![PathBuf::from("/Users/me/Library"), PathBuf::from("/Users/me/Movies/TV")];

        // No marker yet: an index from before the skip list existed goes.
        fill(&dir);
        reset_index_if_skip_list_changed(&dir, &a);
        assert!(!dir.join("index.bin").exists());
        assert!(!dir.join("content").exists());

        // Same list: left alone, whatever the order.
        fill(&dir);
        reset_index_if_skip_list_changed(&dir, &a);
        assert!(dir.join("index.bin").exists());
        assert!(dir.join("content").join("seg").exists());

        // Different list: rebuilt.
        reset_index_if_skip_list_changed(&dir, &b);
        assert!(!dir.join("index.bin").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_running_owner_keeps_its_index() {
        use std::os::fd::AsRawFd;
        let dir = scratch_dir("owner");
        fill(&dir);
        let owner = std::fs::File::create(dir.join("daemon.lock")).unwrap();
        assert_eq!(unsafe { libc::flock(owner.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) }, 0);

        reset_index_if_skip_list_changed(&dir, &[PathBuf::from("/x")]);
        assert!(dir.join("index.bin").exists(), "another process is using this index");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn ordinary_home_folders_are_still_searchable() {
        let list = skip_list("/Users/me", true);
        for folder in ["Developer", "Documents", "Desktop", "Downloads"] {
            assert!(!list.contains(&PathBuf::from("/Users/me").join(folder)), "{folder} with Full Disk Access");
        }
    }
}
