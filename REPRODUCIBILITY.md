# Reproducibility — what is proven, and what is not

Measured 2026-08-14. Every number below came from a run, not from reasoning.

## The short version

| claim | status |
| --- | --- |
| **two different machines produce identical bytes on the same host platform** | ✅ **verified** |
| the artifact contains no host paths or usernames | ✅ verified |
| the 34 browser tests run and pass | ✅ verified (34/34) |
| the cryptography is libsignal's, not home-made | ✅ reviewed |
| the same bytes on a *different host platform* (macOS vs Linux) | ❌ not true |
| the code has been audited by external cryptographers | ❌ never claimed |

The honest headline: **reproducible across machines, per host platform.**

Two independent Linux x86_64 machines — a container on the author's laptop and
a GitHub Actions runner, with different source paths and different `CARGO_HOME`
— produced byte-identical artifacts. A macOS aarch64 build does not match them,
and the reason is understood and documented below (§3).

That is a real supply-chain guarantee: the released artifact can be
independently rebuilt and checked by anyone on the same platform. It is not the
absolute "identical everywhere" property, and this file does not pretend
otherwise.

## What broke the naive claim

An earlier measurement recorded two builds matching byte-for-byte and concluded
the build was reproducible. It was not — the two builds simply happened to run
from the same directory minutes apart. Three later measurements show why:

| environment | sha256 | bytes |
| --- | --- | --- |
| macOS aarch64, path A | `9eeee28b…` | 710 243 |
| macOS aarch64, path B | `0e8c8d80…` | 710 262 |
| container, linux/amd64, `/src` | `b1726674…` | 710 279 |

Same machine, same toolchain, same commit — **different directory, different
bytes.** So reproducibility had never actually been tested; repeatability had.

## The three causes, in the order we found and fixed them

### 1. Absolute host paths were compiled into the artifact — fixed

Rust embeds the path of every source file it compiles (panic locations,
`file!()`). A plain `wasm-pack build` produced a `.wasm` carrying
`/Users/<name>/.cargo/...` throughout. That made cross-machine identity
impossible by construction, and shipped a developer's username to every browser
loading the module.

Fixed with `--remap-path-prefix` in `scripts/build.sh`, which then greps the
artifact and fails if any host path survived.

### 2. Parallel codegen — fixed

With more than one codegen unit the compiler splits work across threads, and
section ordering can follow the machine. macOS and Linux differed by **2 916
bytes** before wasm-opt even ran, which ruled out both the optimiser and
`protoc`. `codegen-units = 1` cut the gap to **36 bytes**.

(We first suspected `protoc`, since the container had 3.21.12 against macOS's
35.1. Pinning it to 35.1 changed the artifact by exactly nothing — the
hypothesis was wrong, and it is recorded here because a wrong guess that got
tested is worth more than an untested right one.)

### 3. The host platform — the one input that still shows

The remaining difference is build-metadata identifiers, not compiled logic:

- `…/build/spqr-9f0d62e758c8b1fc/out/signal.proto.pq_ratchet.rs` versus
  `spqr-8543afab34bd03ff` — the `spqr` crate generates code through a build
  script, and cargo's metadata hash lands in the generated file's path, which
  is then embedded;
- `wasm_bindgen_3a35b7f74ba28b95` versus `wasm_bindgen_934f3b78bf77929b` —
  wasm-bindgen's per-build symbol namespace, derived the same way;
- the wasm-bindgen CLI reports `0.2.126 (21ac804a9)` on one platform and
  `0.2.126` on the other — same version, differently built binary.

We first assumed the build **path** drove those hashes, which would have meant
no two checkouts could ever match. **A later measurement disproved that**: a
GitHub Actions runner building natively at `/home/runner/work/…` with
`CARGO_HOME=/home/runner/.cargo` produced bytes identical to a container
building at `/src` with `CARGO_HOME=/opt/cargo`. Path remapping handles the
path completely.

What is left is the **host triple** — `x86_64-unknown-linux-gnu` versus
`aarch64-apple-darwin`. Same source, same rustc version, same target
(`wasm32-unknown-unknown`), but the metadata hash follows the machine doing the
compiling. Hence: identical within a host platform, different across them.

Cargo's `trim-paths` might narrow this further, but it is still nightly-only as
of Rust 1.97.1, and this project does not build on nightly.

## How to verify the artifact yourself

The canonical platform is **linux/amd64**. On it, a plain checkout and
`./scripts/build.sh --check` reproduces the recorded hash — no container
needed:

```bash
./scripts/build.sh --check
```

CI does exactly this on every push and fails if the hash drifts from
`build-provenance.json`.

On any other host (macOS, aarch64), use the container, which supplies a
linux/amd64 environment:

```bash
docker build --platform linux/amd64 -f Dockerfile.reproduce -t signal-bridge-repro .
docker run --rm --platform linux/amd64 signal-bridge-repro ./scripts/build.sh --check
```

Both routes were measured and agree.

## So what does a green hash check actually mean?

**It means: these bytes came from this source, and an independent machine
reached them from the same source with every input recorded.** Not a claim —
a measurement, repeated on two unrelated Linux machines with different paths
and different `CARGO_HOME`.

That is a real supply-chain guarantee, and it is exactly what upstream lacked:
every upstream release went out from a single laptop, unverified, with no
provenance attestation.

**What it does not mean:** that a macOS or aarch64 build will match. It will
not, for the host-triple reason in §3, and that difference is **not** evidence
of tampering. Verify on linux/amd64, natively or through the container.

If someone needs identity across platforms too, the path is known and finite:
wait for `trim-paths` to stabilise, or vendor the generated protobuf code so no
build script writes into a metadata-hashed directory. Neither is done here.

## What this file does not cover at all

- **No external cryptographic audit has been performed.** Not by Signal, not by
  anyone. `SECURITY_AUDIT_REPORT.md` inherited from upstream is self-written.
- Reviewing that the module delegates to libsignal is not the same as
  reviewing that the protocol is used correctly by the application that
  embeds it.
- The 34 tests are upstream's and cover the module's own surface. They say
  nothing about the embedding application.
