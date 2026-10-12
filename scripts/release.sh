#!/usr/bin/env bash
#
# Build, sign, notarize and publish a Launch release to GitHub Releases.
# Run it locally; nothing here is meant for CI.
#
#   scripts/release.sh --version 1.0.0 --draft      first release, as a draft to review
#   scripts/release.sh --bump patch                 1.0.0 -> 1.0.1
#   scripts/release.sh                              release the version already in the project
#   scripts/release.sh --version 1.1.0 --dry-run    build and sign only, change nothing
#
# What it does, in order:
#   1. checks the tools, the git state, the tag and the signing setup
#   2. runs the unit tests
#   3. archives the Release build with the new version and exports it signed
#      with your Developer ID Application certificate (hardened runtime)
#   4. notarizes and staples the app, packs Launch-<version>.zip and .dmg
#      (the dmg is notarized and stapled too), writes SHA256SUMS.txt
#   5. asks, then writes the version into the Xcode project, commits "Release
#      <version>", tags v<version>, pushes, and creates the GitHub release
#
# The version is only written to the project in step 5, after everything else
# worked, so a failed build leaves your files untouched. The build is made with
# the version passed on the command line (MARKETING_VERSION and
# CURRENT_PROJECT_VERSION), which overrides the project.
#
# One-time setup:
#   - A "Developer ID Application" certificate in your keychain. Xcode >
#     Settings > Apple Accounts > Manage Certificates > + > Developer ID Application.
#   - Notarization credentials, stored once in the keychain (app-specific
#     password from appleid.apple.com):
#       xcrun notarytool store-credentials launch-notary \
#         --apple-id YOU@EXAMPLE.COM --team-id <TEAM ID>
#   - gh, logged in:  gh auth login
#
# Options:
#   --version X.Y.Z        release this version
#   --bump major|minor|patch   release the project's version bumped this much
#                          (with neither, the project's current version is released)
#   --signing MODE         developer-id (default) | development | adhoc
#                          development and adhoc skip notarization: the app only opens
#                          on this Mac, so publishing needs --allow-unnotarized
#   --notary-profile NAME  keychain profile for notarytool (default: launch-notary,
#                          or $NOTARY_PROFILE)
#   --skip-tests           don't run the unit tests
#   --skip-notarize        sign but don't notarize (implies --allow-unnotarized to publish)
#   --dry-run              stop after packaging: no notarization, commit, tag, push or release
#   --draft                create the GitHub release as a draft
#   --prerelease           mark the GitHub release as a pre-release
#   --notes-file FILE      release notes (default: a short install note + GitHub's generated notes)
#   --allow-dirty          don't require a clean git tree
#   --allow-unnotarized    publish a build that isn't notarized
#   --yes                  don't ask before committing, pushing and publishing
#   -h, --help             show this help

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="Launch.xcodeproj"
SCHEME="Launch"
APP_NAME="Launch"
PBXPROJ="$PROJECT/project.pbxproj"

VERSION=""
BUMP=""
SIGNING="developer-id"
NOTARY_PROFILE="${NOTARY_PROFILE:-launch-notary}"
SKIP_TESTS=0
SKIP_NOTARIZE=0
DRY_RUN=0
DRAFT=0
PRERELEASE=0
NOTES_FILE=""
ALLOW_DIRTY=0
ALLOW_UNNOTARIZED=0
ASSUME_YES=0

# ---------------------------------------------------------------- helpers

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//' -e 's/^#$//'; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"; }

confirm() {
    [[ $ASSUME_YES -eq 1 ]] && return 0
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]
}

project_setting() {   # first value of a build setting in the project file
    grep -m1 -E "^[[:space:]]*$1 = " "$PBXPROJ" | sed -E 's/.*= ([^;]+);.*/\1/' | tr -d '"'
}

normalize_version() { # 1.0 -> 1.0.0
    local a b c
    IFS=. read -r a b c <<<"$1"
    echo "${a:-0}.${b:-0}.${c:-0}"
}

bump_version() {      # bump_version 1.2.3 minor -> 1.3.0
    local a b c
    IFS=. read -r a b c <<<"$(normalize_version "$1")"
    case "$2" in
        major) echo "$((a + 1)).0.0" ;;
        minor) echo "$a.$((b + 1)).0" ;;
        patch) echo "$a.$b.$((c + 1))" ;;
        *) die "--bump takes major, minor or patch" ;;
    esac
}

# ---------------------------------------------------------------- arguments

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)           VERSION="${2:?--version needs a value}"; shift 2 ;;
        --bump)              BUMP="${2:?--bump needs major, minor or patch}"; shift 2 ;;
        --signing)           SIGNING="${2:?--signing needs a mode}"; shift 2 ;;
        --notary-profile)    NOTARY_PROFILE="${2:?--notary-profile needs a name}"; shift 2 ;;
        --notes-file)        NOTES_FILE="${2:?--notes-file needs a path}"; shift 2 ;;
        --skip-tests)        SKIP_TESTS=1; shift ;;
        --skip-notarize)     SKIP_NOTARIZE=1; shift ;;
        --dry-run)           DRY_RUN=1; shift ;;
        --draft)             DRAFT=1; shift ;;
        --prerelease)        PRERELEASE=1; shift ;;
        --allow-dirty)       ALLOW_DIRTY=1; shift ;;
        --allow-unnotarized) ALLOW_UNNOTARIZED=1; shift ;;
        --yes|-y)            ASSUME_YES=1; shift ;;
        -h|--help)           usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

[[ -n "$VERSION" && -n "$BUMP" ]] && die "use --version or --bump, not both"
case "$SIGNING" in developer-id|development|adhoc) ;; *) die "--signing takes developer-id, development or adhoc" ;; esac
[[ "$SIGNING" != developer-id ]] && SKIP_NOTARIZE=1
[[ -n "$NOTES_FILE" && ! -f "$NOTES_FILE" ]] && die "notes file not found: $NOTES_FILE"

# ---------------------------------------------------------------- version

CURRENT_VERSION="$(project_setting MARKETING_VERSION)"
CURRENT_BUILD="$(project_setting CURRENT_PROJECT_VERSION)"
[[ -n "$CURRENT_VERSION" && -n "$CURRENT_BUILD" ]] || die "couldn't read the version from $PBXPROJ"

if [[ -n "$VERSION" ]]; then
    :
elif [[ -n "$BUMP" ]]; then
    VERSION="$(bump_version "$CURRENT_VERSION" "$BUMP")"
else
    VERSION="$(normalize_version "$CURRENT_VERSION")"
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3, got '$VERSION'"
TAG="v$VERSION"

# The build number goes up with every release. The very first one keeps the
# project's number, so 1.0.0 doesn't start at build 2.
if [[ -z "$(git tag --list 'v*')" ]]; then BUILD="$CURRENT_BUILD"; else BUILD="$((CURRENT_BUILD + 1))"; fi

OUT="$ROOT/build/release/$VERSION"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT_DIR="$OUT/export"
ARTIFACTS="$OUT/artifacts"
APP="$EXPORT_DIR/$APP_NAME.app"
ZIP="$ARTIFACTS/$APP_NAME-$VERSION.zip"
DMG="$ARTIFACTS/$APP_NAME-$VERSION.dmg"

say "Launch $VERSION (build $BUILD), signing: $SIGNING$([[ $DRY_RUN -eq 1 ]] && echo ', dry run')"
note "project version was $CURRENT_VERSION (build $CURRENT_BUILD)"

# ---------------------------------------------------------------- preflight

say "Checking the setup"
need xcodebuild "Install Xcode."
need xcrun "Install Xcode."
need git "Install git."
need gh "brew install gh, then gh auth login."
need cargo "Install Rust (https://rustup.rs): the file search engine is built from Rust."
export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:$PATH"

if [[ -n "$(git status --porcelain)" ]]; then
    if [[ $ALLOW_DIRTY -eq 1 || $DRY_RUN -eq 1 ]]; then
        warn "the git tree has uncommitted changes (the release commit will not include them)"
    else
        git status --short | head -10
        die "the git tree isn't clean. Commit or stash first, or pass --allow-dirty."
    fi
fi

if git submodule status --recursive | grep -qE '^[+-U]'; then
    die "a submodule is missing or not at the pinned commit. Run: git submodule update --init"
fi

git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote"
gh auth status >/dev/null 2>&1 || die "gh isn't logged in. Run: gh auth login"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || die "gh can't see the repository for 'origin' (is it pushed?)"
note "repository: $REPO"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    die "the tag $TAG already exists. Pick another version."
fi

TEAM_ID="$(project_setting DEVELOPMENT_TEAM)"
IDENTITY=""
if [[ "$SIGNING" == developer-id ]]; then
    IDENTITY="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"' || true)"
    if [[ -z "$IDENTITY" ]]; then
        die "no 'Developer ID Application' certificate in your keychain.
    Create one: Xcode > Settings > Apple Accounts > Manage Certificates > + > Developer ID Application.
    (A build signed with an Apple Development certificate only opens on this Mac: use --signing development.)"
    fi
    [[ -n "$TEAM_ID" ]] || die "no DEVELOPMENT_TEAM in the project"
    note "signing identity: $IDENTITY"
    if [[ $SKIP_NOTARIZE -eq 0 && $DRY_RUN -eq 0 ]]; then
        xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
            || die "no notarization credentials named '$NOTARY_PROFILE'. Store them once:
    xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id YOU@EXAMPLE.COM --team-id $TEAM_ID"
        note "notarization profile: $NOTARY_PROFILE"
    fi
fi

if [[ $DRY_RUN -eq 0 && ( $SKIP_NOTARIZE -eq 1 ) && $ALLOW_UNNOTARIZED -eq 0 ]]; then
    die "this build won't be notarized, so it won't open on other Macs without a Gatekeeper workaround.
    Pass --allow-unnotarized to publish it anyway (or --dry-run)."
fi

SIGN_ARGS=()
[[ "$SIGNING" == adhoc ]] && SIGN_ARGS=(CODE_SIGN_IDENTITY=-)

run_xcodebuild() {   # run_xcodebuild <log name> <args...>: quiet, shows the tail on failure
    local name="$1"; shift
    local log="$OUT/$name.log"
    if ! xcodebuild "$@" >"$log" 2>&1; then
        tail -n 40 "$log" >&2
        die "xcodebuild $name failed. Full log: $log"
    fi
    note "log: $log"
}

rm -rf "$OUT"
mkdir -p "$OUT" "$ARTIFACTS"

# ---------------------------------------------------------------- tests

if [[ $SKIP_TESTS -eq 0 ]]; then
    say "Running the unit tests"
    run_xcodebuild tests -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' \
        -derivedDataPath "$OUT/DerivedData" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} test
fi

# ---------------------------------------------------------------- archive, export

say "Archiving (Release)"
run_xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} archive
[[ -d "$ARCHIVE/Products/Applications/$APP_NAME.app" ]] || die "the archive has no $APP_NAME.app"

mkdir -p "$EXPORT_DIR"
if [[ "$SIGNING" == developer-id ]]; then
    say "Exporting with Developer ID"
    cat >"$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
    <key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
PLIST
    run_xcodebuild export -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$OUT/ExportOptions.plist"
else
    say "Using the archived app ($SIGNING signing)"
    ditto "$ARCHIVE/Products/Applications/$APP_NAME.app" "$APP"
fi
[[ -d "$APP" ]] || die "no $APP_NAME.app after export"

# ---------------------------------------------------------------- verify

say "Verifying the app"
codesign --verify --deep --strict "$APP" || die "the signature doesn't verify"
SIG="$(codesign -dvv "$APP" 2>&1)"
grep -E 'Authority|TeamIdentifier|Timestamp' <<<"$SIG" | sed 's/^/    /' || true

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" && "$BUILT_BUILD" == "$BUILD" ]] \
    || die "the built app says $BUILT_VERSION ($BUILT_BUILD), expected $VERSION ($BUILD)"
note "version $BUILT_VERSION (build $BUILT_BUILD)"

if [[ "$SIGNING" == developer-id ]]; then
    grep -q 'flags=.*runtime' <<<"$SIG" || die "the app isn't signed with the hardened runtime (required for notarization)"
    grep -q '^Authority=Developer ID Application' <<<"$SIG" || die "the app isn't signed with a Developer ID Application certificate"
fi

# ---------------------------------------------------------------- notarize

notarize() {   # notarize <file>
    local file="$1" result id
    note "uploading $(basename "$file") to Apple and waiting (usually a few minutes)..."
    result="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
    id="$(grep -m1 -E '^[[:space:]]*id:' <<<"$result" | awk '{print $2}' || true)"
    if ! grep -q 'status: Accepted' <<<"$result"; then
        tail -n 8 <<<"$result" >&2
        [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        die "notarization of $(basename "$file") was not accepted"
    fi
    note "accepted ($id)"
}

if [[ $SKIP_NOTARIZE -eq 1 ]]; then
    warn "not notarizing: the app will only open on this Mac without a Gatekeeper workaround"
elif [[ $DRY_RUN -eq 1 ]]; then
    note "dry run: skipping notarization"
else
    say "Notarizing the app"
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    notarize "$OUT/notarize.zip"
    xcrun stapler staple "$APP" >/dev/null && xcrun stapler validate "$APP" >/dev/null
    note "stapled"
fi

# ---------------------------------------------------------------- package

say "Packaging"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

STAGE="$OUT/dmg"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
# (hdiutil prints a deprecation notice on new macOS; its real errors still show.)
HDI_OUT="$(hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" 2>&1)" \
    || { echo "$HDI_OUT" >&2; die "couldn't create the disk image"; }
hdiutil verify "$DMG" >/dev/null 2>&1 || die "the disk image doesn't verify"
if [[ "$SIGNING" == developer-id ]]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    if [[ $SKIP_NOTARIZE -eq 0 && $DRY_RUN -eq 0 ]]; then
        notarize "$DMG"
        xcrun stapler staple "$DMG" >/dev/null
    fi
fi

( cd "$ARTIFACTS" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" >SHA256SUMS.txt )
ASSETS=("$DMG" "$ZIP" "$ARTIFACTS/SHA256SUMS.txt")
ls -lh "${ASSETS[@]}" | awk '{print "    " $5 "  " $NF}'

if [[ $SKIP_NOTARIZE -eq 0 && $DRY_RUN -eq 0 ]]; then
    spctl --assess --type execute -vv "$APP" 2>&1 | sed 's/^/    /' || warn "Gatekeeper assessment failed"
fi

if [[ $DRY_RUN -eq 1 ]]; then
    say "Dry run finished: nothing was committed, tagged, pushed or published"
    note "artifacts: $ARTIFACTS"
    exit 0
fi

# ---------------------------------------------------------------- publish

say "Ready to publish $TAG to $REPO"
note "will: write version $VERSION (build $BUILD) into the project, commit, tag $TAG, push the branch and the tag,"
note "      and create the GitHub release$([[ $DRAFT -eq 1 ]] && echo ' (as a draft)')$([[ $PRERELEASE -eq 1 ]] && echo ' (pre-release)')"
confirm "Go ahead?" || { note "stopped. The built files are in $ARTIFACTS"; exit 0; }

sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD;/" "$PBXPROJ"
if ! git diff --quiet -- "$PBXPROJ"; then
    git commit -m "Release $VERSION" -- "$PBXPROJ"
fi
git tag -a "$TAG" -m "$APP_NAME $VERSION"
git push origin HEAD "$TAG"

NOTES_ARGS=()
if [[ -n "$NOTES_FILE" ]]; then
    NOTES_ARGS=(--notes-file "$NOTES_FILE")
else
    INSTALL_NOTE="**Install:** open \`$APP_NAME-$VERSION.dmg\` and drag Launch to Applications. Needs macOS 27 or later on Apple silicon.
Turn off Spotlight's ⌘Space shortcut (System Settings > Keyboard > Keyboard Shortcuts > Spotlight), or record another shortcut in Launch's settings.
"
    if [[ $SKIP_NOTARIZE -eq 1 ]]; then
        INSTALL_NOTE+="
**This build isn't notarized.** macOS will refuse to open it at first: right-click the app and choose Open, or allow it in System Settings > Privacy & Security.
"
    fi
    NOTES_ARGS=(--notes "$INSTALL_NOTE" --generate-notes)
fi

FLAGS=(--verify-tag)
[[ $DRAFT -eq 1 ]] && FLAGS+=(--draft)
[[ $PRERELEASE -eq 1 || $SKIP_NOTARIZE -eq 1 ]] && FLAGS+=(--prerelease)

if ! gh release create "$TAG" "${ASSETS[@]}" --repo "$REPO" --title "$APP_NAME $VERSION" "${NOTES_ARGS[@]}" "${FLAGS[@]}"; then
    die "the release wasn't created, but the commit and tag are pushed. Retry just that step:
    gh release create $TAG ${ASSETS[*]} --repo $REPO --title \"$APP_NAME $VERSION\" --generate-notes"
fi

say "Released $APP_NAME $VERSION"
gh release view "$TAG" --repo "$REPO" --json url -q .url
