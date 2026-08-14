# Why this fork exists, and what it changes

Forked from [`getmaapp/signal-wasm`](https://github.com/getmaapp/signal-wasm)
at commit `71428b7` (version `0.6.0`, 2026-08-13).

## What is *not* changed

The cryptography. Not one primitive, not one call. Upstream does not implement
cryptography either — it marshals bytes between JavaScript and
[libsignal](https://github.com/signalapp/libsignal), pinned to git revision
`b5121d07` (libsignal 0.97.4), plus Signal's own `curve25519-dalek` fork. We
reviewed the 1767 lines of `src/lib.rs` before forking and found: zero network
calls, zero `unsafe`, `Zeroizing` on private records, randomness from the Web
Crypto API, and every crypto operation delegated to libsignal. No home-made
cryptography, no hardcoded keys.

That review is the reason forking was worth doing at all. The problems were
never in the crypto.

## What *is* changed, and why

Every item below is something that stood between us and being able to say
"this artifact came from this source". None of them touch behaviour.

### 1. The compiler is pinned — `rust-toolchain.toml`

Upstream had no toolchain pin (`rust-toolchain.toml` was a 404), so the
compiler was whatever the builder happened to have. Rust's output changes
between compiler versions; without a pin, "reproducible" cannot mean anything.

### 2. `protoc` is documented *and asserted* — `scripts/build.sh`, README

libsignal generates Rust from `.proto` files at build time, so `protoc` is a
build dependency — and the first build on a clean machine fails on it with an
error that names neither libsignal nor protobuf. Upstream mentioned it in
neither README nor CONTRIBUTING. This is the classic invisible host
requirement, the reason for "it builds on my machine".

Documenting it turned out not to be enough, so `scripts/build.sh` refuses to
build against an unexpected version.

### 3. Host paths no longer ship to users — `scripts/build.sh`

Rust embeds the absolute path of every compiled source file into the binary.
A plain `wasm-pack build --target web` therefore produced an artifact carrying
`/Users/<name>/.cargo/...` throughout. Two consequences, both real:

- the build could not be byte-identical on any other machine, *by
  construction* — so the reproducibility question could never even be asked;
- the developer's username shipped to every browser that loaded the module.

`--remap-path-prefix` rewrites those roots to fixed placeholders, and the build
script then verifies no host paths survived rather than assuming.

This also explains a puzzle from our first measurement: two builds inside one
session matched byte-for-byte, but a build from a different directory the next
day did not. Same machine, same toolchain, different path — different bytes.

### 4. The 34 tests actually run — `scripts/test.sh`

Upstream ships 34 `#[wasm_bindgen_test]` cases (`tests/web.rs` is longer than
`src/lib.rs`). None of them could be executed: `wasm-pack test --headless
--chrome` died with `http status: 404` and a SIGKILLed driver, on this machine
and outside the sandbox alike.

The cause was not, as first suspected, an incompatibility between
`wasm-bindgen-test` and current drivers. It was smaller and entirely fixable:
**wasm-pack downloads the newest ChromeDriver into its own cache and passes
that path to cargo, overriding any `CHROMEDRIVER` you set yourself.** Here that
meant ChromeDriver 152 driving Chrome 151, which the driver refuses. The error
surfaces as a bare 404, which reads like a broken harness rather than a version
mismatch — so the tests were presumed broken and left alone.

`scripts/test.sh` resolves the driver matching the installed Chrome and calls
the runner directly. **All 34 tests pass.** They were fine the whole time; only
the harness was wrong. 34 tests that nobody runs are the appearance of
coverage, not coverage.

### 5. There is CI — `.github/workflows/build.yml`

Upstream had no `.github` directory at all, so every npm release went out from
a laptop, unverified, which is also why there is no npm provenance attestation
for it. CI here builds on a machine belonging to nobody, checks the artifact
hash against `build-provenance.json`, and runs the 34 tests.

### 6. Build inputs are recorded — `build-provenance.json`

One file listing every input that changes the artifact and the hash they
produce, checked by `./scripts/build.sh --check` and by CI.

## Licence and the obligation this fork carries

Upstream is `AGPL-3.0-only`, inherited from libsignal, which is itself AGPL-3.0.
This is not upstream's choice to undo, and it is not ours: **AGPL is unavoidable
on any Signal-protocol path.**

Tabula Meta's owner decided on 2026-08-14 to meet that obligation the direct
way: publish this bridge as its own open repository under AGPL. The WASM
artifact is downloaded into each person's browser, which is distribution of
object code, so §5–6 require offering corresponding source for it — and this
repository is that offer. The application that loads the module is a separate
work that does not link libsignal; the obligation discharged here is for what we
actually distribute.

Attribution stays where it belongs: upstream's copyright and licence file are
kept intact, and the git history is preserved rather than squashed.

## Not affiliated with Signal

Signal and the Signal Protocol are trademarks of Signal Technology Foundation.
This fork is not affiliated with, endorsed by, or reviewed by Signal
Technology Foundation, and no external cryptographic audit has been carried
out. See [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) for exactly what has and
has not been demonstrated.
