# Maintaining this fork

Written for whoever picks this up next — including us, a year from now, having
forgotten everything. If something here is out of date, fix it in the same
commit that made it out of date.

## What this repository is, in one paragraph

A browser bridge that lets [libsignal](https://github.com/signalapp/libsignal)
(the Signal Protocol implementation by Signal Technology Foundation) run inside
a web page, compiled to WebAssembly. Tabula Meta uses it for Secret Chat. We did
not write the cryptography and we do not modify it — libsignal does all of it.
What we own is the *build*: pinned inputs, verified output, working tests, CI.

Why it exists at all, and what we changed relative to upstream:
[`FORK.md`](FORK.md). What is and isn't proven about the build:
[`REPRODUCIBILITY.md`](REPRODUCIBILITY.md).

## ⛓️ The two upstreams — do not confuse them

This is the single most important thing to understand before touching anything.

| | what it is | how it reaches us | who maintains it |
| --- | --- | --- | --- |
| [`signalapp/libsignal`](https://github.com/signalapp/libsignal) | **the actual cryptography** | a pinned git dependency in `Cargo.toml` (`rev = "b5121d07…"`) | Signal Technology Foundation |
| [`getmaapp/signal-wasm`](https://github.com/getmaapp/signal-wasm) | the thin WASM wrapper we forked | git history — this repo *is* a fork of it | one person, no CI, no release tags |

**We forked the wrapper. We did NOT fork libsignal.** libsignal stays an
ordinary pinned dependency, exactly as Signal's own maintainers recommend
([libsignal#350](https://github.com/signalapp/libsignal/issues/350): write a
wasm wrapper depending on `libsignal-protocol`, not on `libsignal-bridge`).

That distinction is what keeps this maintainable. Our maintenance surface is
~1,700 lines of wrapper, not a cryptographic library. Updating the crypto means
bumping a revision string, not rebasing a fork of libsignal.

## Routine 1 — track libsignal drift (the one that matters)

libsignal moves roughly weekly. Falling behind is the standing cost of this
fork, and the only real one.

```bash
# where we are
grep 'rev =' Cargo.toml

# where upstream is
npm view @signalapp/libsignal-client version   # Signal's own release cadence
git ls-remote https://github.com/signalapp/libsignal HEAD
```

**As of 2026-08-15:** we pin libsignal **0.97.4** (`b5121d07`); Signal's own
client ships **0.101.0**. Four minor versions in about a month. That gap will
not close by itself.

Suggested cadence: check monthly, bump when a release contains a security fix
or when the gap reaches ~4 minors. Do not bump reflexively — every bump costs a
rebuild, a test run and a provenance update.

### How to bump libsignal

1. edit both `rev = "…"` lines in `Cargo.toml` (`libsignal-protocol` **and**
   `zkgroup` — they must stay identical);
2. `cargo update -p libsignal-protocol` to refresh `Cargo.lock`;
3. `./scripts/build.sh` — expect a new hash;
4. `./scripts/test.sh` — **all 34 must pass**; a failure here is a real API
   change, not flakiness;
5. update `libsignal.rev`, `libsignal.workspaceVersion` and `artifact.sha256`
   in `build-provenance.json` **in the same commit**;
6. update the consuming app's pinned artifact.

⚠️ libsignal makes breaking API changes between minor versions (0.4.0 removed
`map_group_id`; 0.6.0 changed kyber storage). Read their changelog before
bumping, not after.

## Routine 2 — track the wrapper upstream

Far less urgent: upstream is one person with no CI. Assume nothing arrives.

```bash
git remote add upstream https://github.com/getmaapp/signal-wasm.git  # once
git fetch upstream
git log --oneline HEAD..upstream/main    # what they have that we don't
```

Review anything they change **as if it were a pull request from a stranger** —
because effectively it is. Cherry-pick what is useful; do not merge blindly.
If they publish something that conflicts with our build hardening, ours wins.

## Routine 3 — the release

There is no npm publish. The app consumes the artifact built by CI.

1. `./scripts/build.sh --check` — hash must match `build-provenance.json`;
2. `./scripts/test.sh` — 34/34;
3. tag it. Upstream stopped tagging at `v0.2.0` and shipped 0.3–0.6 as bare
   commits on a rewritable branch, which is precisely why no immutable
   reference to what they published exists. **We tag every release.** That is
   not ceremony — it is the thing upstream's absence of it cost us.

## ⛓️ Invariants — do not break these

- **never modify the cryptography.** If a fix seems to belong inside
  libsignal, send it to libsignal. This repo marshals bytes; it does not
  implement primitives;
- **never build with bare `wasm-pack build`** — it bakes the builder's home
  directory into the artifact shipped to every user's browser. Use
  `./scripts/build.sh`, which remaps paths and then verifies none survived;
- **never test with bare `wasm-pack test`** — it silently overrides
  `CHROMEDRIVER` with whatever driver it downloaded, which is why upstream's 34
  tests went unrun for so long. Use `./scripts/test.sh`;
- **keep `unsafe_code = "deny"`**;
- **keep the upstream LICENSE and git history.** This is AGPL-3.0 and the
  history is the attribution;
- **update `build-provenance.json` in the same commit** as any pinned-input
  change. A provenance file that lags is worse than none, because it looks
  authoritative.

## Troubleshooting: `http status: 404` from the test runner

Read this before spending a day on it. **One opaque symptom covers at least
three unrelated causes**, and that is the single reason upstream's 34 tests
went unrun. The run prints a bare `Error: http status: 404`, the driver gets
`SIGKILL`, and nothing says why.

| cause | how to tell | fix |
| --- | --- | --- |
| driver/browser major versions differ | compare `chromedriver --version` with your Chrome | `scripts/test.sh` resolves the matching driver — do not hand it a `CHROMEDRIVER` |
| Chrome cannot use its sandbox (CI, containers) | only fails on CI, works locally | `--no-sandbox`, written into `webdriver.json` by the script |
| chromedriver launches the wrong Chrome | driver and Chrome versions match and it still fails | `goog:chromeOptions.binary`, written into `webdriver.json` by the script |

All three are handled by `./scripts/test.sh`. If you find a fourth, add a row.

⚠️ `webdriver.json` is **generated per run** and gitignored, because it contains
this machine's Chrome path. Do not commit it — a committed one can only ever be
correct on one machine, and being wrong is silent.

## Known gaps — deliberately open, not forgotten

Measured against [S2C2F](https://github.com/ossf/s2c2f), the OpenSSF-adopted
framework for consuming open source safely, this repository sits at ING-4
(mirror the source internally, level 3) and satisfies REB-1 (rebuild in a
trusted environment / validate reproducibility, level 4).

Three level-4 practices are **not** done:

| gap | what it means |
| --- | --- |
| **REB-2** | we do not digitally sign the artifact we rebuild |
| **REB-3** | we do not generate an SBOM |
| **REB-4** | we do not sign the SBOM |

The hash in `build-provenance.json` says *"these bytes came from this source"*.
A signature would say *"and it was really us"*. Worth closing before the module
ships to people at scale.

Also open, and honest about it: **no external cryptographic audit** has been
performed on this wrapper, and byte-identical reproducibility holds only in the
canonical container environment — see `REPRODUCIBILITY.md`.

## Obligations this fork puts on us

- **AGPL-3.0.** The WASM is downloaded into each user's browser, which is
  distribution of object code, so corresponding source must be offered for it.
  This public repository is that offer. Whoever ships the module must link
  here from the application.
- **Vulnerability disclosure.** [OpenSSF guidance](https://best.openssf.org/Vendored-Dependencies-Guide.html)
  for projects that vendor dependencies: if we fix a vulnerability here, we
  issue our own advisory, assign the existing CVE ID to our software, and
  describe the impact in the context of *our* use. Forking makes us a link in
  the disclosure chain, not just a consumer.

## Who to ask

Tabula Meta — MetaEcosystem. Decisions about this fork's direction, publication
and licence posture are recorded in the main project's documentation under
`docs/ops/security/`, starting with the adapter decision of 2026-08-14 and the
browser-crypto landscape review of 2026-08-15.
