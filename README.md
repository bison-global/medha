# Medha

Offline, on-device AI chat. Pick a subject, download a small open model once, and chat with it privately — nothing leaves the phone.

This repository is the Flutter app. The design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

**Status: v1.0 feature-complete (M1–M4), not yet tested on devices.**
- **Subjects:** Math, Science, Coding, Exam Prep, Wellness, General, Writing, Spoken English and Farming, each in Lite (≈2B) and Pro (≈4–5B). Translate is shown as "Coming soon".
- **Models:** download, SHA-256 check and a test load before first use. Each subject has its own system prompt and optional LoRA add-on. A RAM check picks a smaller fallback model or warns when Pro won't fit.
- **Chat:** streaming replies with Stop; reasoning shown under "Show steps". History is kept in an encrypted database, with delete + undo and delete all. A "Save chat history" switch keeps chats only until the app closes.
- **Projects:** group chats and add up to 5 files (PDF, DOCX, TXT, MD; 10 MB total). Files are searched on the phone (keyword + vector search with Qwen3-Embedding-0.6B), and replies list the files they used.
- **Attachments:** attach one file to a chat (5 MB).
- **Voice chat:** uses the phone's offline speech recognition and text-to-speech, in English, Hindi, Tamil or Kannada.
- **App lock:** fingerprint/face or a 4–6 digit PIN, with auto-lock (instant, 1 min, 5 min), a lockout after wrong PINs, and a privacy cover in the app switcher.
- **Safety and reporting:** content safety layer (§9.4), red-team release gates (§11.1), "Report this reply" (§9.5), licences and AI disclosure.

## Getting started

Requires Flutter (stable, 3.35 or newer), and for device builds the Android NDK or Xcode.

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

1. **Get the models.** Download the GGUF files listed in `assets/catalog/catalog.dev.json` (`baseModels`: the chat models, Qwen3Guard-Gen-0.6B and Qwen3-Embedding-0.6B) and host them somewhere the phone can reach. You only need the models for the subjects you want to test, plus the guard and the embedding model.
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
5. **Optional:** send "Report this reply" submissions to your server with `--dart-define=MEDHA_REPORT_URL=https://your-api/reports`. Without it, reports stay queued on the phone.
6. **iOS only:** build the llama.cpp framework once on a Mac:
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

## Known gaps

- **Not built on devices yet.** CI runs `flutter analyze`, the unit tests and a Linux compile of the llama.cpp bridge. Android and iOS builds still need to be run on real devices, and the RAM limits in the catalog need checking on real phones.
- **Guard prompt.** The guard prompt in the dev catalog is written from Qwen3Guard's published format. Before release, replace it with an exact rendering of the model's own chat template.
- **Fixed chat templates.** Chat templates fall back to ChatML or Gemma when llama.cpp can't apply the model's own template natively. Check each model's output format, including the thinking tags.
- **No LoRA add-ons yet.** The app can load add-ons, but none are trained, so the catalog has none.
- **Uploaded files aren't encrypted separately.** Their text and vectors are in the encrypted database, but the copied original file is protected only by the app's private storage. Per-file encryption (§9.2) is a follow-up.
- **Scanned PDFs.** PDFs with no text layer are marked "No text found"; there is no OCR.
- **Voice depends on the phone.** Offline recognition needs the phone's offline speech pack for the chosen language. Some phones fall back to online recognition or don't support a language.
- **Storage library.** Storage uses `sqlite3` + SQLCipher directly instead of drift, so the app doesn't need code generation. Switching to drift with SQLite3MultipleCiphers (§7) is a follow-up.
- **Bundled fonts.** Sora and Inter aren't bundled yet, so the app uses system fonts for now.
