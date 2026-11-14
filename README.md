# Ghillie mobile

Ghillie for iPhone, iPad and Android: the [CAMO](https://camocoin.org) wallet. Status: **groundwork** (Nov 2026).
Planned release: Q1 2027, after CAMO mainnet (Dec 15, 2026). Desktop Ghillie lives in
[thedifference7717-sys/ghillie](https://github.com/thedifference7717-sys/ghillie).

## Rules (same as desktop Ghillie)
- **No new cryptography.** Keys, addresses, decoy selection, signing and transaction building all happen in CAMO's
  wallet library (`src/wallet/api` in the camo repository, from Monero, unchanged). This app is screens plus a thin
  C bridge (`native/camo_wallet_ffi.*`).
- **No fee on sends, ever** ("Ghillie fee: 0 · never"): an extra output would make Ghillie transactions stand out.
- **No third-party calls**: no analytics, no price lookups, no update checks. It talks only to the CAMO node you pick.
- **Phones never mine.** Remote control of mining on your own computers comes later (2027).
- Look: the approved mockups (night-ops palette, VT323 pixel headings and balance, Inter body text, notched corners,
  pixel-camo card; the Ghillie logo stays smooth).

## What works now
- Opening screen: the camocoin.org scope (living pixel-camo field, hidden CAMO, drag to aim, tap to enter; Skip;
  still when the phone asks for reduced motion).
- Screens: wallet home, send (with review), receive (QR, `camo:` links, a fresh address per payer), rigs (preview),
  settings. They run on **demo data** (`lib/wallet/demo_wallet.dart`) and show a DEMO badge.
- `camo:` payment links (build/parse; `monero:` refused), CAMO amounts (exact, 12 decimals, BigInt), address shape
  hints per network (C mainnet, Q stagenet, K/L testnet; Monero addresses get a clear message).
- Wallet setup: create (password of 8+ characters, the 25 words shown once with a warning, then 3 of them checked),
  restore from the 25 words with a restore height, unlock with the password (wrong password refused).
- 13 tests (`flutter test`), CI builds a demo Android APK and an unsigned iOS app.

## Plan
1. **Wallet bridge** (`native/`): C functions over `wallet2_api.h` (create/restore/open, subaddresses, sync,
   balance, history, prepare/commit send). **Done Nov 14**: `native/test/run-regtest-smoke.sh` links it against CAMO's
   real library and passes on a private regtest chain (sync, 5 CAMO to a new labelled subaddress, fee 0.00123462 like
   desktop Ghillie, txid returned, receiver gets exactly 5.000000000000).
2. **Linux dev build with the real library**: **done Nov 14** (`lib/wallet/ffi_wallet.dart`, see below): create with
   a password, wrong password refused, restore from the 25 words gives the same address, send 5 CAMO, receive exactly 5.
3. **Android**: **engine done Nov 14**: `android-lib.yml` builds camo's wallet library with `contrib/depends`
   (NDK r17b) and links the bridge into `libcamo_wallet.so` (arm64-v8a, 17.7 MB, exactly the 33 `camo_*` functions,
   only Android system libraries needed). CI's APK bundles it (`ghillie-android-stagenet`); without it: demo APK.
4. **iOS**: **engine done Nov 14**: `ios-lib.yml` runs `native/ios/build-ios-lib.sh` on a macOS runner: OpenSSL,
   libsodium, expat, unbound, ZeroMQ, Boost 1.84 from pinned, checksummed sources, then camo's wallet library, all in
   one static `libcamo_wallet.a` (arm64, iOS 15+); an iPhone test executable links against it. Build-only patch:
   `camo-ios-miner.patch` (miner.cpp's macOS battery API; phones never mine), and `ios_shims.c` (`__clear_cache`
   for RandomX's JIT, never run by the wallet). CI's iOS app links it via `ios/Flutter/Engine.xcconfig` and the Dart
   side finds it with `DynamicLibrary.process()`.
5. **Node**: a phone can't hold the chain, so it uses a remote node in untrusted mode. Needs a public,
   rate-limited `--restricted-rpc` CAMO node (decision pending: the free Google seed has only 1 GB/month egress).
6. **Security before release**: wallet files encrypted by the library with the user's password (done); seed screens
   protected (done Nov 14: Android FLAG_SECURE, covered in app switchers on all platforms); QR scanning on Send (done
   Nov 14, on-device decoding); still to do: optional Face ID / fingerprint unlock via iOS Keychain / Android Keystore,
   the printed recovery sheet.
7. **Distribution**: test builds are free (Android APK; iOS via Xcode with a free Apple ID on the owner's device,
   7-day signing). Store releases need Apple's Developer Program ($99/yr) and Google Play ($25 once): owner's call.

## Develop
```
flutter pub get
flutter test
flutter run -d linux        # phone-sized window
```

## Real wallet (development)
`lib/wallet/ffi_wallet.dart` runs the screens on CAMO's real wallet library through `native/camo_wallet_ffi`.
Linux dev build: set `CAMO_WALLET_LIB` (libcamo_wallet.so), `CAMO_WALLET` (wallet file), `CAMO_NODE` (host:port) and
optionally `CAMO_NETWORK` (default stagenet); without them the app shows demo data.
With them, the setup / unlock screens come first. Test: `bash native/test/run-regtest-dart.sh <libcamo_wallet.so> <dir with camod>`. Passed Nov 14, 2026: 5 CAMO sent
to a labelled subaddress, fee 0.00123462, txid returned, receiver exactly 5.

## Tested on iPhone (simulator), Nov 14, 2026
On the owner's Intel iMac (Xcode 26.5, iOS 26.5 simulator, x86_64 engine from `ios-lib.yml`): created a wallet with the
real library, synced through the public stagenet phone node `3.134.132.214:39749`, received 5 CAMO from a miner, then
sent 1 CAMO back (fee 0.00086355, Ghillie fee 0). Local setup: engines in `ios/Engine/` (device) and `ios/Engine/sim/`
(simulator), linked by a git-ignored `ios/Flutter/Engine.xcconfig`:
```
OTHER_LDFLAGS[sdk=iphoneos*] = $(inherited) -force_load "$(PROJECT_DIR)/Engine/libcamo_wallet.a" -lc++ -liconv -lz -framework Security -framework SystemConfiguration
OTHER_LDFLAGS[sdk=iphonesimulator*] = $(inherited) -force_load "$(PROJECT_DIR)/Engine/sim/libcamo_wallet.a" -lc++ -liconv -lz -framework Security -framework SystemConfiguration
```
