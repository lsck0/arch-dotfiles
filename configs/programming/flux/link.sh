#!/usr/bin/env bash

# flux-rs (mirror/pkgbuilds) ships the sysroot; flux runs on the nightly it was built against
SYSROOT=/usr/lib/flux
if [[ ! -f "$SYSROOT/rust-toolchain.toml" ]] || ! command -v rustup >/dev/null 2>&1; then
    exit 0
fi

channel=$(sed -n 's/^channel = "\(.*\)"/\1/p' "$SYSROOT/rust-toolchain.toml")
rustup toolchain install "$channel" --profile minimal --component rust-src,rustc-dev,llvm-tools
# a sysroot from the old `cargo xtask install` is a real directory, ln would nest into it
[[ -d "${HOME}/.flux" && ! -L "${HOME}/.flux" ]] && command rm -rf "${HOME}/.flux"
ln -sfn "$SYSROOT" "${HOME}/.flux"
