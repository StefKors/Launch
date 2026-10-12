# Launch

A Spotlight-style launcher for macOS. Press ⌘Space, type, press Return.

| Type | Result |
| --- | --- |
| `saf`, `sysset`, `vsc` | Apps, matched by name, word start or initials. Frequently used apps rank higher. |
| `cv.pdf` | Matching apps, then a **File Search** row. Return on it switches to file mode. |
| `f cv.pdf ext:pdf` or `/cv.pdf` | File mode directly, with [fsearch](https://github.com/noahdunnagan/fsearch) query syntax. Delete the `f ` to leave it. |
| `kill chrome` | Running processes. Return quits, ⌥Return force-quits. |

⌘Return reveals in Finder. ⌥Return is the alternate action shown in the footer.

## Build

Requires Xcode 27 and Rust (`rustup target add aarch64-apple-darwin`).

```sh
git submodule update --init
xcodebuild -project Launch.xcodeproj -scheme Launch build
xcodebuild -project Launch.xcodeproj -scheme Launch test
```

The Xcode target has a Run Script phase that builds `Rust/` (a small C-ABI wrapper around the pinned `Vendor/fsearch` submodule) into a static library.

## Setup

- Turn off Spotlight's ⌘Space (System Settings → Keyboard → Keyboard Shortcuts → Spotlight), or record another shortcut in Launch's settings.
- Grant Full Disk Access to Launch to index protected folders (Desktop, Documents, …), then reopen it.
- File search skips `~/Pictures`, `~/Movies`, `~/Music` and `~/Library`: macOS asks for permission each time an app opens them (Photos, Media & Apple Music), and Full Disk Access doesn't cover that. The list lives in `Rust/src/lib.rs` (`NEVER_INDEXED`); the index is rebuilt automatically when it changes.

Launch is not sandboxed: it indexes the whole disk and signals other processes.

## Layout

- `Launch/Core`: items, the provider protocol, query routing, fuzzy matching.
- `Launch/Providers`: apps, files, processes. Add a feature by adding a `SearchProvider`.
- `Launch/Search`: the `FileSearching` seam and the in-process fsearch engine.
- `Rust/`: C interface to fsearch (`include/launch_fsearch.h`).
