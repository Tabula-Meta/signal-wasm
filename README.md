# signal-wasm — Tabula Meta fork

> Signal Protocol compiled to WebAssembly for browser-based E2EE messaging

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![WASM](https://img.shields.io/badge/WASM-Ready-green)](https://webassembly.org/)
[![Version](https://img.shields.io/badge/Version-0.6.0-blue)](Cargo.toml)

> ### This is a maintained fork, not the original
>
> Forked from [`getmaapp/signal-wasm`](https://github.com/getmaapp/signal-wasm)
> at commit `71428b7`, maintained by [Tabula Meta](https://tabula-meta.io) for
> its Secret Chat feature.
>
> **The cryptography is not ours and is unchanged.** It is
> [libsignal](https://github.com/signalapp/libsignal)'s — Signal Technology
> Foundation's own implementation — reached through a pinned git dependency. We
> did not write a single primitive and we do not intend to.
>
> **What the fork adds is everything needed to trust the build**: a pinned
> compiler, a documented and asserted `protoc`, an artifact with no host paths
> baked into it, CI on a machine that belongs to nobody, and a test suite that
> actually runs (upstream's 34 tests could not be executed at all).
>
> | if you want to know | read |
> | --- | --- |
> | why this fork exists and what changed | [`FORK.md`](FORK.md) |
> | **how to keep it alive — updating libsignal, releases, invariants** | [**`MAINTENANCE.md`**](MAINTENANCE.md) |
> | what is and is not proven about the build | [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md) |
> | exact pinned inputs and the artifact hash | [`build-provenance.json`](build-provenance.json) |
>
> Not affiliated with, endorsed by, or reviewed by Signal Technology Foundation.
> No external cryptographic audit has been performed.

## Features

- 🔐 **End-to-End Encryption** — Signal Protocol (X3DH + Double Ratchet)
- 🛡️ **Post-Quantum Ready** — Kyber1024 (PQXDH) support
- 👥 **Group Messaging** — Sender Keys and Private Groups (GV2)
- 🆔 **Flexible Identities** — Any string identifier (Firebase UIDs, usernames, UUIDs)
- 🔢 **Safety Numbers** — Identity verification fingerprints
- 💾 **Serialisation** — Export/import for IndexedDB persistence
- 🌐 **Browser-First** — Uses Web Crypto API for randomness

## Installation

```bash
npm install @getmaapp/signal-wasm
```

## Quick Start

```typescript
import init, {
  PrivateKey,
  IdentityKeyPair,
  ProtocolAddress,
  InMemIdentityKeyStore,
  InMemSessionStore,
  InMemPreKeyStore,
  InMemSignedPreKeyStore,
  InMemKyberPreKeyStore,
  generateRegistrationId,
  generatePreKeys,
  generateSignedPreKey,
  generateKyberPreKey,
  processPreKeyBundle,
  encryptMessage,
  decryptMessage,
} from "@getmaapp/signal-wasm";

// 1. Initialise the WASM module
await init();

// 2. Generate an identity (no device ID required)
const privateKey = PrivateKey.generate();
const publicKey = privateKey.getPublicKey();
const identityKeyPair = new IdentityKeyPair(publicKey, privateKey);
const registrationId = generateRegistrationId();

// 3. Create stores
const identityStore = new InMemIdentityKeyStore(identityKeyPair, registrationId);
const sessionStore = new InMemSessionStore();
const prekeyStore = new InMemPreKeyStore();
const signedPrekeyStore = new InMemSignedPreKeyStore();
const kyberPrekeyStore = new InMemKyberPreKeyStore();

// 4. Generate keys for registration
const prekeys = await generatePreKeys(1, 100, prekeyStore);
const signedPreKey = await generateSignedPreKey(1, identityKeyPair, signedPrekeyStore);
const kyberPreKey = await generateKyberPreKey(1, identityKeyPair, kyberPrekeyStore);

// 5. Addressing (device ID is only used here)
const localAddress = new ProtocolAddress("alice-firebase-uid", 1);
const bobAddress = new ProtocolAddress("bob-firebase-uid", 1);

// 6. Establish a session (Alice processes Bob's PreKey bundle)
await processPreKeyBundle(
  bobAddress,
  localAddress,
  bobRegistrationId,
  bobIdentityKey,
  bobSignedPreKey.id,
  bobSignedPreKeyPublic,
  bobSignedPreKey.signature,
  bobPreKey.id,
  bobPreKey.public_key,
  bobKyberPreKey.id,
  bobKyberPreKey.public_key,
  bobKyberPreKey.signature,
  sessionStore,
  identityStore,
);

// 7. Encrypt a message
const plaintext = new TextEncoder().encode("Hello Bob! 🔒");
const ciphertext = await encryptMessage(
  plaintext,
  bobAddress,
  localAddress,
  sessionStore,
  identityStore,
);

// 8. Decrypt a message
const result = await decryptMessage(
  ciphertext.body,
  ciphertext.message_type,
  aliceAddress,
  bobAddress,
  sessionStore,
  identityStore,
  prekeyStore,
  signedPrekeyStore,
  kyberPrekeyStore,
);
const plaintext2 = result.plaintext;

// 9. Tombstone any one-time keys the decrypt consumed (M27). All id fields
//    are `undefined` when nothing was consumed (e.g. non-prekey messages).
if (result.kyberPreKeyId !== undefined) {
  // delete kyber prekey result.kyberPreKeyId from your durable store
}
if (result.oneTimePreKeyId !== undefined) {
  // delete X25519 prekey result.oneTimePreKeyId from your durable store
}
```

## API Reference

### Crypto Primitives

| Class | Methods |
|-------|---------|
| `PrivateKey` | `generate()`, `getPublicKey()`, `serialize()`, `deserialize(data)` |
| `PublicKey` | `serialize()`, `deserialize(data)` |
| `IdentityKeyPair` | `constructor(publicKey, privateKey)`, `serialize()`, `deserialize(data)` |

### Protocol Address

| Class | Description |
|-------|-------------|
| `ProtocolAddress` | `constructor(name, deviceId)` — `name` can be any string (Firebase UID, UUID, etc.) |

### Stores (In-Memory)

All stores support import/export for IndexedDB persistence.

| Store | Constructor | Import/Export Methods |
|-------|-------------|----------------------|
| `InMemIdentityKeyStore` | `new(identityKeyPair, registrationId)` | — |
| `InMemSessionStore` | `new()` | `export_session(address)`, `import_session(address, bytes)`, `has_session(address)`, `archive_session(address)` |
| `InMemPreKeyStore` | `new()` | `export_pre_key(id)`, `import_pre_key(id, bytes)` |
| `InMemSignedPreKeyStore` | `new()` | `export_signed_pre_key(id)`, `import_signed_pre_key(id, bytes)` |
| `InMemKyberPreKeyStore` | `new()` | `export_kyber_pre_key(id)`, `import_kyber_pre_key(id, bytes)`, `export_kyber_usage()`, `import_kyber_usage(bytes)` |
| `InMemSenderKeyStore` | `new()` | `export_sender_key(address, distributionId)`, `import_sender_key(address, distributionId, bytes)`, `remove_sender_key(address, distributionId)` |

> **Since 0.4.0:** every `distributionId` must be a caller-minted **UUID string**
> (e.g. `crypto.randomUUID()`). The wrapper no longer derives an id from
> arbitrary group strings. `remove_sender_key(address, distributionId)` deletes
> the sender-key record (returns `boolean`) and must be called before
> re-creating a distribution on member removal/compromise, otherwise libsignal
> reuses the existing chain and removed members keep decrypting.

> **Since 0.6.0:** `InMemKyberPreKeyStore` also carries the kyber **anti-replay
> memory** — the set of `(kyberId, signedPreKeyId, senderBaseKey)` triples the
> engine has already seen. Persist it (`export_kyber_usage()` → bytes,
> `import_kyber_usage(bytes)` at hydration) alongside the kyber records.
> Without it the replay guard resets on every reload and a replayed
> PreKeySignalMessage against a live last-resort key decapsulates again (L16).
> This matches what Signal's own clients persist (Signal-iOS's
> `KyberPreKeyUseRecord` table, Signal-Desktop's `kyberPreKey_triples`).

### Key Generation

| Function | Returns | Description |
|----------|---------|-------------|
| `generatePreKeys(startId, count, store)` | `Promise<WasmPreKey[]>` | Batch-generate one-time PreKeys |
| `generateSignedPreKey(id, identityKeyPair, store)` | `Promise<WasmSignedPreKey>` | Generate a signed PreKey |
| `generateKyberPreKey(id, identityKeyPair, store)` | `Promise<WasmKyberPreKey>` | Generate a Kyber PreKey (PQXDH) |
| `generateRegistrationId()` | `number` | Generate unbiased registration ID (1–16380) |

### Protocol Operations

| Function | Returns | Description |
|----------|---------|-------------|
| `processPreKeyBundle(...)` | `Promise<void>` | Establish a session from a PreKey bundle |
| `encryptMessage(plaintext, recipient, localAddress, sessionStore, identityStore)` | `Promise<WasmCiphertext>` | Encrypt a 1:1 message |
| `decryptMessage(ciphertext, type, sender, localAddress, sessionStore, identityStore, prekeyStore, signedPrekeyStore, kyberPrekeyStore)` | `Promise<WasmDecryptResult>` | Decrypt a 1:1 message. Result getters: `plaintext` (`Uint8Array`), plus `kyberPreKeyId` / `oneTimePreKeyId` / `signedPreKeyId` — the one-time pre-key ids consumed establishing a new session (`undefined` when none). Tombstone consumed ids in your durable store (M27) |
| `createSenderKeyDistribution(localAddress, distributionId, senderKeyStore)` | `Promise<Uint8Array>` | Create a sender key distribution message (`distributionId` must be a UUID string) |
| `processSenderKeyDistribution(senderAddress, distMessage, senderKeyStore)` | `Promise<void>` | Process a sender key distribution message (id read from the message) |
| `encryptGroupMessage(localAddress, distributionId, plaintext, senderKeyStore)` | `Promise<Uint8Array>` | Encrypt a group message (`distributionId` must be a UUID string) |
| `decryptGroupMessage(senderAddress, ciphertext, senderKeyStore)` | `Promise<Uint8Array>` | Decrypt a group message (id read from the ciphertext) |

### Error Handling

Every rejected promise throws a real JS `Error` with:

- `message` — `"SignalError: <detail>"` in debug builds; flattened to
  `"SignalError: Operation failed"` in release builds (unchanged behaviour).
- `code` — a stable machine-readable string, matched on the libsignal error
  **type** so it stays specific even in release builds:

| `code` | Meaning |
|--------|---------|
| `NoSenderKeyState` | No sender-key record for the message's distribution id (e.g. SKDM not processed yet — retry after pull) |
| `DuplicatedMessage` | Message counter already seen (replay/duplicate; usually benign) |
| `ReusedKyberBaseKey` | Kyber anti-replay rejection: this sender base key was already used with this `(kyberId, signedPreKeyId)` pair — a replayed PreKeySignalMessage |
| `UntrustedIdentity` | Sender identity key not trusted for the address |
| `InvalidKyberPreKeyId` | Referenced Kyber pre-key id is invalid/missing |
| `InvalidPreKeyId` | Referenced pre-key id is invalid/missing |
| `InvalidSignedPreKeyId` | Referenced signed pre-key id is invalid/missing |
| `FingerprintVersionMismatch` | Scanned QR fingerprint version differs from ours (thrown by `verifyScannableFingerprint`) |
| `FingerprintParsingError` | Scanned QR fingerprint payload is undecodable or malformed |
| `Generic` | Everything else, including wrapper-side validation failures |

Note: `String(err)` now yields `"Error: SignalError: …"` (standard `Error`
stringification) instead of the bare message, because the thrown value is a
real `Error` rather than a string. Catch sites reading `err.message` are
unaffected.

### Safety Numbers

| Function | Returns | Description |
|----------|---------|-------------|
| `generateSafetyNumber(localUuid, localIdentityKey, contactUuid, contactIdentityKey)` | `WasmSafetyNumber` | Generate a safety number fingerprint (`displayable` string + `scannable` QR payload) |
| `verifyScannableFingerprint(scanned, localUuid, localIdentityKey, contactUuid, contactIdentityKey)` | `boolean` | **Since 0.5.0.** Canonical cross-perspective QR verification (`ScannableFingerprint::compare`): checks their.local == our.remote AND their.remote == our.local in constant time. Throws `FingerprintVersionMismatch` on version mismatch, `FingerprintParsingError` on an undecodable payload |
| ~~`verifySafetyNumber(...)`~~ | `boolean` | **Deprecated since 0.5.0.** Recomputes our own fingerprint and byte-compares — it can never validate a cross-perspective scan. Kept for API compatibility; use `verifyScannableFingerprint` |

### Identity Proof-of-Possession

Server-verifiable proof-of-possession of an identity key (e.g. to authorise a
re-key). XEdDSA over the X25519 identity key, canonical libsignal signing.

| Function | Returns | Description |
|----------|---------|-------------|
| `signWithIdentityKey(identityPrivateKey, message)` | `Uint8Array` | Sign `message` with the identity private key (64-byte signature) |
| `verifyIdentitySignature(identityPublicKey, message, signature)` | `boolean` | Constant-time verification; `false` for wrong key/message or malformed signature |

### GV2 (Private Groups)

| Class | Methods |
|-------|---------|
| `WasmGroupMasterKey` | `generate()`, `from_bytes(bytes)`, `derive_identifier()`, `derive_secret_params()` |
| `WasmGroupIdentifier` | `serialize` |
| `WasmGroupSecretParams` | `serialize_master_key` (since 0.5.0; returns the 32-byte **master key**, not the full params encoding), `get_identifier()` |

### Data Structures

| Struct | Properties |
|--------|------------|
| `WasmPreKey` | `id`, `public_key`, `record` |
| `WasmSignedPreKey` | `id`, `public_key`, `signature`, `timestamp`, `record` |
| `WasmKyberPreKey` | `id`, `public_key`, `signature`, `timestamp`, `record` |
| `WasmCiphertext` | `message_type`, `body` |
| `WasmSafetyNumber` | `displayable` (string), `scannable` (Uint8Array) |

### Utility Functions

| Function | Description |
|----------|-------------|
| `generate_random_bytes(length)` | Generate CSPRNG random bytes (max 1 MiB) |
| `generate_uuid()` | Generate a UUID v4 (returns 16 bytes) |
| `uuid_to_string(bytes)` | Convert 16 bytes to UUID string |
| `uuid_from_string(str)` | Convert UUID string to 16 bytes |
| `message_type_signal()` | Normal Signal message type constant |
| `message_type_pre_key()` | PreKey message type constant |
| `message_type_sender_key()` | Sender key message type constant |

## Vite Configuration

```typescript
// vite.config.ts
import wasm from "vite-plugin-wasm";
import topLevelAwait from "vite-plugin-top-level-await";

export default defineConfig({
  plugins: [wasm(), topLevelAwait()],
});
```

## Testing

34 `#[wasm_bindgen_test]` cases run in a real headless Chrome.

```bash
./scripts/test.sh
```

Do **not** use `wasm-pack test --headless --chrome` directly. wasm-pack
downloads the newest ChromeDriver into its own cache and passes that path to
cargo, overriding any `CHROMEDRIVER` you set. The moment that driver's major
version differs from your installed Chrome — measured here: driver 152 against
Chrome 151 — the run dies with a bare `http status: 404` and a SIGKILLed
driver, which reads like a broken test harness rather than a version mismatch.
That is why these tests went unrun for so long. `scripts/test.sh` resolves the
driver that matches *your* Chrome and invokes the runner directly.

## Build from Source

### Prerequisites

| | version | why it is pinned |
| --- | --- | --- |
| rustc / cargo | from `rust-toolchain.toml` | rustup installs it for you |
| wasm-pack | `0.15.0` | it pins `wasm-opt` and the wasm-bindgen CLI |
| **protoc** | see `build-provenance.json` | **build dependency of libsignal itself** |

⚠️ **`protoc` is required and is not obvious.** libsignal generates Rust from
`.proto` files during the build (`prost-build`), so without `protoc` the build
fails partway through with an error that names neither libsignal nor protobuf.
Install it before your first build:

```bash
brew install protobuf          # macOS
apt-get install -y protobuf-compiler   # Debian/Ubuntu (check the version)
```

### Build

```bash
./scripts/build.sh            # build and print the artifact hash
./scripts/build.sh --check    # additionally fail if the hash drifted
```

Use the script rather than bare `wasm-pack build`. Rust embeds the absolute
path of every file it compiles into the binary, so a plain build bakes the
building machine's home directory into the shipped `.wasm` — we measured
`/Users/<name>/.cargo/...` throughout the artifact. That makes the build
unreproducible anywhere else by construction, and ships a developer's username
to every browser that loads the module. The script sets `--remap-path-prefix`
to fix both, and then verifies no host paths survived.

## Reproducible builds

`build-provenance.json` records every input that changes the artifact together
with the hash they produce, and CI rebuilds on a machine that belongs to nobody
and fails if the hash drifts. See [`REPRODUCIBILITY.md`](REPRODUCIBILITY.md)
for what is proven, what is not, and the measurements behind both.

## Security

- ✅ `#![deny(unsafe_code)]` — No unsafe Rust
- ✅ Input validation on all WASM-bound parameters
- ✅ Bounded allocations (`generate_random_bytes` limited to 1 MiB)
- ✅ PreKey batch generation limited to 500 keys
- ✅ 24-bit PreKey ID wrapping (matches Signal behaviour)
- ✅ CSPRNG via Web Crypto API
- ✅ Generic error messages in production builds
- ✅ Secret-bearing wrapper buffers zeroised on drop (`zeroize::Zeroizing`) — see caveats below
- ✅ `log_to_console` debug helper is compiled out of release builds

### Memory Safety & Zeroization

- Secret-bearing buffers owned by the wrapper are wrapped in
  `zeroize::Zeroizing` and are overwritten with zeroes on drop: serialized
  PreKey/SignedPreKey/KyberPreKey records (each contains the private half),
  and the group master-key bytes held by `WasmGroupMasterKey` /
  `WasmGroupSecretParams`.
- **Limitations.** The long-term identity key itself is a libsignal
  `PrivateKey` — an upstream `Copy` type over a `[u8; 32]` that libsignal does
  not zero on drop, so the wrapper cannot guarantee erasure of the identity
  scalar while it lives in WASM linear memory. And **any bytes exported to
  JavaScript** (via `serialize()`, getters, etc.) are copies in JS memory
  subject to the browser's garbage collector; they cannot be erased from
  Rust. Treat exported keys with extreme care.

### ⚠️ Panics Brick the Instance

Release builds use `panic = "abort"` (there is no unwinding across the WASM
boundary). A Rust panic therefore **permanently bricks the WASM instance** —
every subsequent call traps — and surfaces to JS as the flattened
`SignalError: Operation failed` with no recoverable detail (the M25
error-flattening residual). A page reload (fresh instance) is the only
remedy. Debug builds register `console_error_panic_hook` so panics are
visible in the console during development.

## Licence

AGPL-3.0 — See [LICENSE](LICENSE)

This package is built on [libsignal](https://github.com/signalapp/libsignal) v0.97.4 (commit [`b5121d0`](https://github.com/signalapp/libsignal/commit/b5121d07c72f9e631f178d907ca892587f64f9e2)) by Signal Technology Foundation.

## Disclaimer

This package is not affiliated with or endorsed by Signal Technology Foundation. Signal and the Signal Protocol are trademarks of Signal Technology Foundation.
