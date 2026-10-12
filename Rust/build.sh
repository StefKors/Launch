#!/bin/bash
# Builds the fsearch static library for the Xcode target. Xcode runs this
# before compiling Swift (Run Script phase "Build fsearch static library").
set -euo pipefail

cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v cargo >/dev/null; then
    echo "error: cargo not found. Install Rust (https://rustup.rs) and add the aarch64-apple-darwin target." >&2
    exit 1
fi

if [ ! -f ../Vendor/fsearch/Cargo.toml ]; then
    echo "error: Vendor/fsearch is empty. Run: git submodule update --init" >&2
    exit 1
fi

# Xcode sets DEVELOPER_DIR and SDKROOT for the app build. Cargo's linker
# step would pick the iOS-style SDK path up wrongly if they leaked in.
unset SDKROOT IPHONEOS_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET WATCHOS_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-27.0}"

OUT="${DERIVED_FILE_DIR:-$PWD/target}"
export CARGO_TARGET_DIR="$OUT/cargo"

cargo build --release --locked --quiet

cp "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/liblaunch_fsearch_ffi.a" "$OUT/liblaunch_fsearch_ffi.a"
