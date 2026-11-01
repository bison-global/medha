# Medha

Offline, on-device AI chat. Pick a subject, download a small open model once, and chat with it privately — nothing leaves the phone.

This repository is the Flutter app. The design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

**Status: M1 (core chat).**
- Onboarding: welcome, subject picker, size picker, download.
- Math Lite (MiniCPM5-2B), with the other subjects shown as "Coming soon".
- Model download, SHA-256 verification and a test load before first use.
- Streaming chat with a Stop button and reasoning shown under "Show steps".
- Chat history in an encrypted database, with delete + undo and delete all.
- Content safety layer (§9.4) and red-team release gates (§11.1).
- Licences screen and AI disclosure (§9.5).

App lock, projects, document uploads, voice and the remaining subjects come in later milestones (§12).

## Layout

```
lib/
  app/            services wiring, router, theme
  core/
    catalog/      signed model catalog (models, subjects, safety config)
    inference/    InferenceEngine, llama.cpp isolate engine, prompt/context building
    safety/       phrase rules, guard model, safety pipeline, red-team scoring
    storage/      encrypted SQLite (SQLCipher) and repositories
    download/     background downloads, checksum verification, installer
  features/       onboarding, chat, settings screens
packages/medha_llama/   FFI plugin: C shim over llama.cpp (Android CMake, iOS xcframework)
native/llama.cpp/       pinned llama.cpp (git submodule)
tool/                   catalog builder, platform setup, iOS framework build
integration_test/       on-device red-team run
```

## Getting started

Requires Flutter (stable, 3.32 or newer), and for device builds the Android NDK or Xcode.

```bash
git clone --recurse-submodules https://github.com/bison-global/medha
cd medha
./tool/setup_platforms.sh        # generates android/ and ios/ with Medha's settings
flutter pub get
flutter test
```

### Try the UI without models (demo mode)

Demo mode uses a scripted engine and simulated downloads, so you can work on the UI without any model files. The safety phrase rules still run.

```bash
flutter run --dart-define=MEDHA_FAKE_ENGINE=true
```

### Run with real models

1. **Get the models.** Download the GGUF files (Q4_K_M) for MiniCPM5-2B and Qwen3Guard-Gen-0.6B and host them somewhere the phone can reach.
2. **Build a catalog** with their real sizes and checksums. The bundled `assets/catalog/catalog.dev.json` has none, so the installer refuses to download until you do this.
   ```bash
   dart run tool/make_catalog.dart --gen-key --key-out catalog_signing.seed   # once; keep it secret
   dart run tool/make_catalog.dart \
     --model minicpm5-2b-q4km=/path/MiniCPM5-2B-Q4_K_M.gguf=https://your-cdn/minicpm5-2b-q4_k_m.gguf \
     --model qwen3guard-gen-0_6b-q4km=/path/Qwen3Guard-Gen-0.6B-Q4_K_M.gguf=https://your-cdn/qwen3guard-gen-0.6b-q4_k_m.gguf \
     --version 2 --key catalog_signing.seed --key-id medha-2026-1 --out catalog.json
   ```
3. **Trust the key.** Add the printed public key to `kCatalogPublicKeys` in `lib/core/catalog/catalog_service.dart`.
4. **Point the app at the catalog** and run it:
   ```bash
   flutter run --dart-define=MEDHA_CATALOG_URL=https://your-cdn/catalog.json
   ```
5. **iOS only:** build the llama.cpp framework once on a Mac:
   ```bash
   ./tool/build_ios_llama.sh
   ```

Release builds only accept catalogs signed with a key in `kCatalogPublicKeys`. Debug builds also accept the unsigned dev catalog.

## Safety

Every message goes through the layers in ARCHITECTURE.md §9.4:
1. The signed phrase list.
2. The Qwen3Guard safety model.
3. The safety system prompt.
4. A check of the streamed reply.

If the safety model can't run, Medha fails closed and doesn't answer.

### Red-team testing

The red-team attack set is private: never commit it here (`.gitignore` blocks `redteam/` and `*.redteam.jsonl`). To run it on a device that has Math Lite installed:

```bash
adb push medha.redteam.jsonl /data/local/tmp/
flutter test integration_test/redteam_test.dart \
  --dart-define=MEDHA_REDTEAM_FILE=/data/local/tmp/medha.redteam.jsonl
```

The run fails unless every release gate in §11.1 passes.

Case format, one JSON object per line:

```json
{"id": "w-001", "category": "weapons", "language": "en", "technique": "fiction", "expect": "refuse", "text": "…"}
{"id": "c-001", "category": "crisis", "language": "hi", "technique": "indirect", "expect": "crisis", "turns": ["…", "…"], "forbidden": ["…"]}
```

## Known gaps in M1

- **Not built on devices yet.** CI runs `flutter analyze`, the unit tests and a Linux compile of the llama.cpp bridge. Android and iOS builds still need to be run on real devices.
- **Guard prompt.** The guard prompt in the dev catalog is written from Qwen3Guard's published format. Before release, replace it with an exact rendering of the model's own chat template.
- **Fixed chat templates.** Chat templates fall back to ChatML or Gemma when llama.cpp can't apply the model's own template natively. Check each model's output format, including the thinking tags.
- **No memory check yet.** RAM-based model gating and the low-memory fallback model (§5.3, §10) are not implemented.
- **Storage library.** Storage uses `sqlite3` + SQLCipher directly instead of drift, so M1 doesn't need code generation. Switching to drift with SQLite3MultipleCiphers (§7) is a follow-up.
- **Bundled fonts.** Sora and Inter aren't bundled yet, so the app uses system fonts for now.
