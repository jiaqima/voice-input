# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make whisper-lib   # Build whisper.cpp static library (requires cmake)
make download-model  # Download default whisper model (large-v3-turbo-q8_0, ~874MB)
make build         # Compile to .build/VoiceInput.app (builds whisper-lib if needed)
make run           # Build and run
make install       # Install to ~/Applications/VoiceInput.app
make clean         # Remove build directory and whisper build
```

Download a different model: `make download-model DEFAULT_MODEL=small.en`

No test suite or linter is configured.

`vendor/whisper.cpp` is a git submodule. The Makefile now initializes it automatically on first use for `make whisper-lib`, `make build`, `make run`, and `make install`. If auto-init fails, run `git submodule update --init --recursive vendor/whisper.cpp` manually.

## Architecture

VoiceInput is a macOS background app (no dock icon) that maps **Fn double-press-and-hold → audio capture → speech recognition → optional LLM refinement → text injection** into the active application.

**AppDelegate** is the central orchestrator. It owns all components and drives the recording lifecycle:
1. `KeyMonitor` detects a short Fn tap followed by a second Fn press held for 0.5 seconds via `NSEvent.addGlobalMonitorForEvents` (accessibility permission required). Single Fn holds are ignored, and the first tap still reaches macOS because the app observes Fn globally rather than suppressing it. Pressing Shift while Fn is held fires `onEditRequested`; a local flagsChanged monitor mirrors the global one so Fn still works while the app's own edit panel is key.
2. `AudioRecorder` captures PCM audio via `AVAudioEngine`, emitting RMS levels for the waveform UI.
3. **Speech recognition** uses `SpeechRecognizerProtocol` — two backends:
   - `SpeechRecognizer` (default): wraps Apple `SFSpeechRecognizer`, streams via `SFSpeechAudioBufferRecognitionRequest`
   - `WhisperSpeechRecognizer`: uses whisper.cpp (C library linked as static `.a`). Resamples audio from device rate to 16kHz mono via `AVAudioConverter`, accumulates samples, runs inference every 2s for partial results and on stop for final result. `WhisperBridge` wraps the C API.
   - Recognizers take a `RecognitionLanguage` (`.locale(Locale)` or `.autoChineseEnglish`, stored in settings as `"auto-zh-en"`). Auto mode is Whisper-only: it runs whisper's language detector, picks `zh` unless the audio is clearly English (zh-biased threshold), locks the choice after 3s of audio, and passes a Simplified-Chinese `initial_prompt` so English terms inside Chinese sentences stay English. Apple Speech falls back to zh-CN in auto mode.
4. `LLMClient` (optional) refines the transcript using an OpenAI-compatible API — aimed at fixing speech recognition errors (CJK homophones, misheard English terms).
5. `TextInjector` switches the active input method to ASCII (for CJK contexts), injects text via CGEvent typing simulation (same mechanism as macOS Dictation), falling back to clipboard + simulated Cmd+V if CGEvent fails, then restores the input method.

**UI** runs as a floating `NSPanel` (HUD material, glass morphism) with a `WaveformView` animated at 60 fps via `CVDisplayLink`. `EditPanel` is a second non-activating panel (can become key without activating the app) that shows an editable transcript when Shift was pressed during recording: Return commits to injection, Shift+Return inserts a newline, Escape discards. In edit mode `AppDelegate` waits up to 3s for the recognizer's final result (Apple's `stop()` uses `finish()` so a final result is delivered) before opening the editor; the direct-inject path still uses the latest partial immediately.

**Settings** (UserDefaults) stores: recognition language, STT backend, whisper model path, LLM base URL/API key/model, and whether LLM refinement is enabled.

## Key Design Decisions

- **No external Swift dependencies** — pure Swift using system frameworks + whisper.cpp linked as a static C library.
- **whisper.cpp** is a git submodule under `vendor/whisper.cpp`, built via cmake into static libraries. The bridging header at `Sources/Bridge/whisper-bridging-header.h` imports `whisper.h`. The Makefile initializes the submodule automatically on first use and builds it with the Xcode toolchain (needed for C++ headers on some systems).
- **Text injection** (`TextInjector`) uses CGEvent typing simulation as the primary method, with clipboard + simulated Cmd+V as fallback.
- **LLM base URL is configurable** — any OpenAI-compatible provider (OpenAI, Ollama, LM Studio, etc.) works.
- **CJK input method switching** (`InputMethodManager`) detects 9+ input method variants and must switch to ASCII before paste to avoid double-conversion.
- **Swift 6 / macOS 14+** — the package targets arm64 with swift-version 5 compiler flags.

## Permissions

The app requests three permissions at startup (`Permissions.swift`): microphone, speech recognition, and accessibility. `NSEvent.addGlobalMonitorForEvents` returns nil without accessibility access. The CGEvent-based paste fallback additionally requires Input Monitoring permission (macOS 15+). Because the app is ad-hoc signed by default, all TCC grants are invalidated on every rebuild — permissions must be re-granted after `make install`. Passing `SIGN_IDENTITY="<certificate name>"` keeps them; the Makefile re-signs the bundle on every `build`/`run`/`install` so a stale ad-hoc signature never leaks into an install. If the signature changes and dictation stops typing text while System Settings still shows Accessibility enabled, reset the stale TCC entries with `tccutil reset Accessibility|ListenEvent|PostEvent com.voiceinput.app` and re-grant.
