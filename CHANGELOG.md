# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-07-17

### Changed
- **libsignal**: Updated all five libsignal dependencies (`libsignal-protocol`, `libsignal-core`, `signal-crypto`, `zkgroup`, `zkcredential`) from tag `v0.93.1` to `main` @ [`b5121d0`](https://github.com/signalapp/libsignal/commit/b5121d07c72f9e631f178d907ca892587f64f9e2) (2026-07-16, upstream workspace version 0.97.4).
  - Covers ~60 upstream commits, including the session/state/storage refactor (`session.rs` split into `session_management.rs`, `state/`, `storage/`), dynamic `InvalidMessage` error descriptions, removal of `SignalMessage.verifyMac`, the ML-KEM parameter key-type fix, and SPQR integration.
  - New transitive dependency: `spqr` v1.5.1 (Sparse Post-Quantum Ratchet), pulled in by `libsignal-protocol`.
  - **No changes to `src/lib.rs` were required** — every libsignal API used by the wrapper remained source-compatible, and the public JavaScript/WASM API is unchanged.
- **Dependencies**: Bumped all crates within semver-compatible ranges (`cargo update`), notably `wasm-bindgen` 0.2.106 → 0.2.126, `uuid` 1.19 → 1.24, `zeroize` 1.8 → 1.9, `prost` 0.14.3 → 0.14.4, `rand` 0.9.4 → 0.9.5.

### Notes
- The getrandom "diamond dependency" (v0.2 + v0.3) is **still required** after the update: `getrandom` 0.2 (feature `js`) is pulled in by `rand_core` 0.6 consumers (`curve25519-dalek` 4.1.3, `x25519-dalek`, `password-hash`, `aes-gcm-siv` 0.11.1 via `crypto-common`), while `getrandom` 0.3 (feature `wasm_js`) serves `rand` 0.9 users (`libsignal-core`, `uuid`). Both pins remain in `Cargo.toml`.
- Verified with `cargo build` (host), `cargo build --target wasm32-unknown-unknown --release`, `cargo clippy --target wasm32-unknown-unknown` (no new warnings), and `wasm-pack test --headless --chrome` (all tests passing).

## [0.2.0] - 2026-05-03

### Removed
- **BREAKING**: Removed `SignalClient` entirely. There is no monolithic client object anymore.

### Added
- **Granular Crypto Primitives**: Exported `PrivateKey`, `PublicKey`, and `IdentityKeyPair` as standalone types.
  - `PrivateKey.generate()` — generates a new private key (no device ID required).
  - `PrivateKey.getPublicKey()` — derives the corresponding public key.
  - `IdentityKeyPair` constructor takes `(PublicKey, PrivateKey)`.
- **Protocol Address**: Exported `ProtocolAddress` as a standalone type. Device IDs are now scoped **only** to addressing.
- **Individual Stores**: Exported first-class store types:
  - `InMemIdentityKeyStore`
  - `InMemSessionStore`
  - `InMemPreKeyStore`
  - `InMemSignedPreKeyStore`
  - `InMemKyberPreKeyStore`
  - `InMemSenderKeyStore`
  - Each store supports import/export methods for IndexedDB persistence.
- **Standalone Protocol Operations**: All messaging operations are now standalone async functions:
  - `processPreKeyBundle()`
  - `encryptMessage()`
  - `decryptMessage()`
  - `createSenderKeyDistribution()` / `processSenderKeyDistribution()`
  - `encryptGroupMessage()` / `decryptGroupMessage()`
  - `generateSafetyNumber()` / `verifySafetyNumber()`
- **Standalone Key Generation**:
  - `generatePreKeys(startId, count, prekeyStore)` → `Promise<WasmPreKey[]>`
  - `generateSignedPreKey(keyId, identityKeyPair, signedPrekeyStore)` → `Promise<WasmSignedPreKey>`
  - `generateKyberPreKey(keyId, identityKeyPair, kyberPrekeyStore)` → `Promise<WasmKyberPreKey>`
  - `generateRegistrationId()`

### Changed
- **Identity generation no longer requires a device ID**. This eliminates the temp-device-ID problem at the architectural level.
- Store counters (`nextPreKeyId`, `nextSignedPreKeyId`, `nextKyberPreKeyId`) are now managed by the consumer, not an internal client state.
- **Async key generation**: `generatePreKeys`, `generateSignedPreKey`, and `generateKyberPreKey` are now `async` (return `Promise`).
- **libsignal v0.93.1**: Updated all libsignal dependencies from v0.92.0 to v0.93.1.
- **Safety numbers**: `generateSafetyNumber` now accepts any string identifier (Firebase UIDs, usernames, UUIDs).
- **PreKey ID wrapping**: IDs now wrap at 24 bits (`0x00FF_FFFF`) to match Signal behaviour.
- Demo app (`signal-wasm-demo`) rewritten to use the new granular API.
- All tests rewritten to use the new granular API.

### Security
- Replaced hardcoded `CiphertextMessageType` magic numbers (`2`, `3`, `7`) with upstream enum constants.
- Added `MAX_PREKEY_BATCH_SIZE` limit (500) and `MAX_RANDOM_BYTES_LENGTH` limit (1 MiB).
- Removed `futures::executor::block_on` from synchronous WASM functions — now fully async.
- Constants for fingerprint version (`2`) and iterations (`5200`) are now explicit rather than inline literals.

### Migration
```typescript
// Before (monolithic SignalClient)
const client = new SignalClient(uuid, deviceId);
const keyPair = client.get_identity_key_pair();
client.generate_pre_keys(100);
const ciphertext = await client.encrypt_message(recipientUuid, recipientDeviceId, plaintext);

// After (granular libsignal-style API)
const privateKey = PrivateKey.generate();
const publicKey = privateKey.getPublicKey();
const identityKeyPair = new IdentityKeyPair(publicKey, privateKey);
const registrationId = generateRegistrationId();
const identityStore = new InMemIdentityKeyStore(identityKeyPair, registrationId);
const sessionStore = new InMemSessionStore();
const localAddress = new ProtocolAddress(uuid, deviceId);
const recipientAddress = new ProtocolAddress(recipientUuid, recipientDeviceId);
const preKeys = await generatePreKeys(1, 100, prekeyStore);
const ciphertext = await encryptMessage(plaintext, recipientAddress, localAddress, sessionStore, identityStore);
```

## [0.1.2] - 2026-04-09

### Security
- Updated libsignal from v0.86.11 to v0.92.0, incorporating security enhancements including MAC sender ID verification for replay attack prevention
- SPQR v1 is now enforced for all newly initiated sessions, ensuring post-quantum security

### Changed
- **Internal**: Updated `message_encrypt` calls to include `local_address` parameter for recipient verification (required by libsignal v0.92.0)
- **Internal**: Updated `message_decrypt` calls to include `local_address` parameter for recipient verification (required by libsignal v0.92.0)
- Updated all libsignal dependencies to v0.92.0:
  - `libsignal-protocol`
  - `libsignal-core`
  - `signal-crypto`
  - `zkgroup`
  - `zkcredential`

### Notes
- No breaking changes to the public JavaScript/WASM API
- Fully backward compatible with messages from older clients

## [0.1.1] - 2026-01-28

### Added
- Support for Firebase UIDs and arbitrary strings as client IDs
- Deterministic Group UUID mapping for Stream Chat integration
- GV2 Private Group support (`WasmGroupMasterKey`, `WasmGroupIdentifier`, `WasmGroupSecretParams`)

### Changed
- Renamed package to `@getmaapp/signal-wasm`
- Updated package metadata and documentation

## [0.1.0] - 2026-01-14

### Added
- Initial release of signal-wasm
- Signal Protocol implementation compiled to WebAssembly
- X3DH key agreement protocol
- Double Ratchet messaging protocol
- Post-quantum Kyber1024 (PQXDH) support
- Group messaging via Sender Keys (GV1)
- Safety number generation and verification
- State persistence for IndexedDB
- Complete TypeScript definitions

[Unreleased]: https://github.com/getmaapp/signal-wasm/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/getmaapp/signal-wasm/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/getmaapp/signal-wasm/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/getmaapp/signal-wasm/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/getmaapp/signal-wasm/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/getmaapp/signal-wasm/releases/tag/v0.1.0
