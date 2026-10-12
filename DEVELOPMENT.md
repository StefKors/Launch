# Developing Launch

How to build, test and release Launch. For what the app does, see the [README](README.md).

## Requirements

- macOS 27 on Apple silicon, and Xcode 27.
- Rust, with the Apple silicon target: `rustup target add aarch64-apple-darwin`. The file search engine is built from Rust.
- If `xcode-select -p` points at the Command Line Tools, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for command-line builds. (`scripts/release.sh` does this by itself.)

## Build and test

```sh
git submodule update --init
xcodebuild -project Launch.xcodeproj -scheme Launch build
xcodebuild -project Launch.xcodeproj -scheme Launch test
```

The Xcode target has a Run Script phase that builds `Rust/` (a small C-ABI wrapper around the pinned `Vendor/fsearch` submodule) into a static library, so the first build takes a minute longer.

The tests run inside the app as their host. The host skips indexing the disk, the global shortcut and the update check, so tests don't touch your real settings or index.

`Launch --smoke-test` starts the app, proves it launches (every library loads), and quits with status 0. The release script uses it on the exported app.

## Layout

- `Launch/Core`: items, the provider protocol, query routing, fuzzy matching, the feature list.
- `Launch/Providers`: apps, files, processes. Add a feature by adding a `SearchProvider`, and a `Feature` case if it should be switchable.
- `Launch/Search`: the `FileSearching` seam and the in-process fsearch engine. `FileSearchHost` starts the engine only when File Search is on.
- `Launch/Onboarding`: the welcome tour. Its step is saved, so it resumes after a restart.
- `Launch/Settings`: the settings window and its sections.
- `Launch/Updates`: the Sparkle updater.
- `Config/Info.plist`: Sparkle's feed URL and public key, merged into the app's Info.plist.
- `Rust/`: the C interface to fsearch (`include/launch_fsearch.h`).
- `Vendor/fsearch`: the fsearch submodule, pinned to a commit.
- `scripts/release.sh`: the release script.

## File search

fsearch runs inside the app through `Rust/`, which builds a static library with a small C interface that exchanges JSON. The Swift side only talks to the `FileSearching` protocol, so the engine could be swapped for a bundled `fsearch serve` daemon without touching the providers or the UI.

The index lives in `~/Library/Application Support/Launch/FSearch`, apart from any index the standalone fsearch daemon keeps.

`Rust/src/lib.rs` decides what the engine never opens (`NEVER_INDEXED`): `~/Pictures`, `~/Movies`, `~/Music` and `~/Library`, plus a few guarded system folders. macOS asks for permission every time an app opens the media folders, and Full Disk Access doesn't cover it. The index remembers the skip list that built it and is rebuilt (seconds) when the list changes.

## Updates (Sparkle)

Installed copies read `https://github.com/StefKors/Launch/releases/latest/download/appcast.xml`, the `appcast.xml` attached to the latest release. Each update's zip is signed with an EdDSA key. The public half is `SUPublicEDKey` in `Config/Info.plist`; the private half is in your login keychain.

**Back up the private key.** Without it, installed copies can never be updated, and users would have to reinstall by hand. Export it once and keep the file in a password manager, never in the repo:

```sh
<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x launch-sparkle-key
```

`scripts/release.sh` signs with the keychain key and refuses to release if it doesn't match the public key in the app, or if the app's feed URL doesn't point at this repository.

Updates only work from the second release on: a copy of 1.0.0 can update to 1.0.1, but you can only test that once 1.0.1 exists.

## Releasing

[`scripts/release.sh`](scripts/release.sh) builds, signs, notarizes and publishes a release to GitHub Releases. It runs on your Mac, and nothing is committed or pushed until you confirm at the end.

```sh
scripts/release.sh --version 1.0.0 --draft    # first release, as a draft to review
scripts/release.sh --bump patch               # 1.0.0 -> 1.0.1 (or minor, major)
scripts/release.sh --dry-run                  # build, sign and package only
scripts/release.sh --help                     # every option
```

It runs the tests, archives the Release build, exports it signed with Developer ID (hardened runtime), launches the exported app once as a smoke test, notarizes and staples the app and a `.dmg`, writes a `.zip`, a signed `appcast.xml` and `SHA256SUMS.txt`, then commits `Release <version>`, tags `v<version>`, pushes and creates the release. The version goes into the Xcode project only at that last step, so a failed build leaves your files alone.

The push uses `gh`'s login when `origin` is an `https://` URL. After a draft release, review it on GitHub and publish it there; until it's published, the update feed doesn't exist.

### One-time setup

1. A **Developer ID Application** certificate: Xcode → Settings → Apple Accounts → Manage Certificates → + → Developer ID Application. (Apple only lets the Account Holder create it, and not through the App Store Connect API.)
2. Notarization credentials, either of:
   - An App Store Connect API key, with the [`asc` CLI](https://asccli.sh) (used first):
     ```sh
     asc auth login --name launch --key-id <KEY ID> --issuer-id <ISSUER UUID> --private-key AuthKey_<KEY ID>.p8
     ```
     The key ID is the part of the `.p8` file name after `AuthKey_`; the issuer ID is the UUID at the top of the API keys page.
   - Or an [app-specific password](https://support.apple.com/102654), stored for `notarytool`:
     ```sh
     xcrun notarytool store-credentials launch-notary --apple-id YOU@EXAMPLE.COM --team-id <TEAM ID>
     ```
3. `gh auth login`.
4. Sparkle's signing key in your keychain, created once with `generate_keys` (see above), and backed up.

The Developer ID certificate issued through Xcode expires on 2027-02-01. Apps already signed and notarized keep working after that, but you need a new certificate to sign later releases.

`--signing development` builds with your Apple Development certificate instead. That app only opens on your own Mac, so publishing it needs `--allow-unnotarized`, and the release is marked as a pre-release (which the update feed ignores).
