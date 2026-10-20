<p align="center">
<img src="AppIcon%20Exports/AppIcon-iOS-Default-1024@1x.png" height="128">
<h1 align="center">Launch</h1>
</p>

#### Supported Platforms
<img src="https://stefkors.com/api/platform/index.svg?os=macos" />

<img src="screenshots/launcher.png">

A Spotlight-style launcher for macOS. Press ⌘Space, type, press Return.

**Links**
- Download: [Latest release](https://github.com/StefKors/Launch/releases/latest)
- Website: [stefkors.com/launch](https://stefkors.com/launch/)
- Building it yourself: [DEVELOPMENT.md](DEVELOPMENT.md)

**Features**
- Opens apps from a few letters or their initials, and learns which ones you use most
- Searches files and folders across your whole Mac, powered by [fsearch](https://github.com/noahdunnagan/fsearch)
- Quits or force-quits any of your running processes with `kill`
- Shows today's and tomorrow's Calendar events in the menu bar, with the next one as text beside the icon
- Updates itself, and has no analytics
- Native macOS look with Liquid Glass

## Install

1. Download `Launch-<version>.dmg` from the [latest release](https://github.com/StefKors/Launch/releases/latest) and drag Launch to Applications. It needs macOS 27 or later on an Apple silicon Mac.
2. Open it and follow the welcome tour.
3. Turn off Spotlight's ⌘Space (System Settings → Keyboard → Keyboard Shortcuts → Spotlight), or record another shortcut in Launch's settings.

## Use it

Press ⌘Space and start typing.

| Type | Result |
| --- | --- |
| `saf`, `sysset`, `vsc` | Apps, matched by name, the start of a word, or initials. Apps you use often rank higher. |
| `cv.pdf` | Matching apps, then a **File Search** row. Press Return on it to search files. |
| `f cv.pdf ext:pdf` or `/cv.pdf` | Search files directly. `ext:`, `in:`, `kind:` and the other [fsearch](https://github.com/noahdunnagan/fsearch) filters work. |
| `kill chrome` | Running processes. Return quits one, ⌥Return force-quits it. |

- **⌘Return** reveals the selected item in Finder.
- **⌥Return** is the alternate action, such as Force Quit or Copy Path.
- **Backspace** on an empty field leaves file search or kill mode.
- **Esc** closes the launcher.

In Settings → Features you can switch File Search and Kill off. Opening apps is always on. With File Search off, nothing is indexed and it uses no memory.

## Permissions

- **Full Disk Access** (optional) lets file search include Desktop, Documents, Downloads and iCloud Drive. Without it, those folders are skipped. Grant it in System Settings → Privacy & Security, then restart Launch. The welcome tour has a button for it.
- **Pictures, Movies, Music and Library are never searched.** macOS asks for permission every time an app opens them, and Full Disk Access doesn't cover that, so Launch leaves them out instead of asking.
- Launch isn't sandboxed, because it searches your whole disk and quits other processes. It only signals processes you own.

## Updates

Launch checks for updates about once a day and offers to install them. Each update is signed and checked before it's installed. You can check yourself from the menu bar ("Check for Updates…") or switch automatic checks off in Settings → Updates. Apart from downloading an update, that check is the only network request Launch makes.

## Troubleshooting

- **Spotlight opens instead of Launch:** turn off its ⌘Space shortcut (see Install), or record a different shortcut in Settings.
- **A file isn't found:** if it's in Desktop, Documents or Downloads, grant Full Disk Access. Files in Pictures, Movies, Music and Library aren't searched.
- **The first search is empty:** on first launch Launch is still building its file index, which takes a few seconds. Searching files shows "Indexing files…" until it's done.
- **Starting over:** the welcome tour comes back on its own until you finish it. Once finished, it can only be replayed from a development build.

**License**
MIT © Launch. See [LICENSE](LICENSE). It bundles [fsearch](https://github.com/noahdunnagan/fsearch) (MIT), an adaptation of [border-beam](https://github.com/Jakubantalik/Libraries.dev/tree/main/packages/border-beam) by Jakub Antalik (MIT, see [NOTICE](NOTICE.md)) and [Sparkle](https://sparkle-project.org) (its own permissive license).
