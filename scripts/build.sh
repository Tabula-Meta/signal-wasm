#!/usr/bin/env bash
#
# The one build entry point — humans and CI use this same script, or the
# artifact hashes stop meaning anything.
#
# Why a script instead of plain `wasm-pack build`:
#
#   Rust embeds the absolute path of every source file it compiles into the
#   binary (panic locations, `file!()`, assertion messages). Upstream's plain
#   `wasm-pack build --target web` therefore bakes the building machine's home
#   directory into the shipped .wasm — we measured it: `/Users/<name>/.cargo/...`
#   appears throughout the artifact. Two consequences:
#
#     1. the build cannot be byte-identical on any other machine, by
#        construction — so "reproducible build" would be an empty claim;
#     2. the developer's username ships to every browser that loads the module.
#
#   `--remap-path-prefix` rewrites those roots to fixed placeholders, which
#   fixes both. Cargo's own `trim-paths` profile option does the same thing
#   more neatly but is still nightly-only as of Rust 1.97.1, so we do it here.
#
# Usage:  ./scripts/build.sh          — build and print the artifact hash
#         ./scripts/build.sh --check  — additionally fail if the hash has
#                                       drifted from build-provenance.json
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

cargo_home="${CARGO_HOME:-$HOME/.cargo}"

# Keep the getrandom cfg: setting RUSTFLAGS overrides the `rustflags` key in
# .cargo/config.toml rather than appending to it, so dropping it here would
# silently build a module with no working randomness source.
export RUSTFLAGS="--cfg getrandom_backend=\"wasm_js\" --remap-path-prefix=${cargo_home}=/cargo --remap-path-prefix=${repo_root}=/src"

echo "==> toolchain"
rustc --version
cargo --version
wasm-pack --version
protoc --version

# protoc is a build INPUT, not merely a prerequisite: libsignal generates Rust
# from .proto files during the build, so a different protoc yields a different
# artifact. Measured: Debian's stock 3.21.12 and 35.1 differ by ~3 KB of wasm.
# Upstream documented protoc nowhere at all; documenting it is not enough, so
# the expected version is asserted here.
expected_protoc="$(python3 -c 'import json;print(json.load(open("build-provenance.json"))["toolchain"]["protoc"])')"
actual_protoc="$(protoc --version | awk '{print $2}')"
if [[ "$actual_protoc" != "$expected_protoc" ]]; then
  echo "FAIL: protoc $actual_protoc, expected $expected_protoc — the artifact would not be reproducible" >&2
  exit 1
fi

echo "==> build"
wasm-pack build --target web

artifact="pkg/signal_wasm_bg.wasm"
hash="$(shasum -a 256 "$artifact" | cut -d' ' -f1)"
size="$(wc -c < "$artifact" | tr -d ' ')"

echo "==> artifact"
echo "sha256 $hash"
echo "bytes  $size"

# The artifact must not carry host paths — that is the whole point of the
# remapping above, so verify it rather than trust it.
if strings "$artifact" | grep -qE "(/Users/|/home/[a-z]|C:\\\\Users)"; then
  echo "FAIL: host paths leaked into the artifact" >&2
  strings "$artifact" | grep -oE "(/Users/|/home/[a-z]|C:\\\\Users)[^ ]{0,60}" | sort -u | head >&2
  exit 1
fi
echo "host paths: none ✓"

if [[ "${1:-}" == "--check" ]]; then
  expected="$(python3 -c 'import json;print(json.load(open("build-provenance.json"))["artifact"]["sha256"])')"
  if [[ "$hash" != "$expected" ]]; then
    echo "FAIL: artifact hash drifted" >&2
    echo "  expected $expected" >&2
    echo "  actual   $hash" >&2
    exit 1
  fi
  echo "hash matches build-provenance.json ✓"
fi
