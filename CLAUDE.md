# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make build    # Compile to .build/VoiceInput.app
make run      # Build and run
make install  # Install to ~/Applications/VoiceInput.app
make clean    # Remove build directory
```

No test suite or linter is configured.

## Architecture

VoiceInput is a macOS background app (no dock icon) that maps **Fn key hold → audio capture → speech recognition → optional LLM refinement → clipboard paste** into the active application.

**AppDelegate** is the central orchestrator. It owns all components and drives the recording lifecycle:
1. `KeyMonitor` detects a 0.5-second Fn key hold via `NSEvent.addGlobalMonitorForEvents` (accessibility permission required). Short presses are ignored to preserve the macOS emoji picker.
2. `AudioRecorder` captures PCM audio via `AVAudioEngine`, emitting RMS levels for the waveform UI.
3. `SpeechRecognizer` wraps `SFSpeechRecognizer` and reports partial/final transcriptions.
4. `LLMClient` (optional) refines the transcript using an OpenAI-compatible API — aimed at fixing speech recognition errors (CJK homophones, misheard English terms).
5. `TextInjector` switches the active input method to ASCII (for CJK contexts), writes text to the clipboard, simulates Cmd+V, then restores the original clipboard and input method.

**UI** runs as a floating `NSPanel` (HUD material, glass morphism) with a `WaveformView` animated at 60 fps via `CVDisplayLink`.

**Settings** (UserDefaults) stores: recognition language, LLM base URL/API key/model, and whether LLM refinement is enabled.

## Key Design Decisions

- **No external dependencies** — pure Swift using only system frameworks (AppKit, AVFoundation, Speech, Carbon, CoreGraphics, QuartzCore).
- **Clipboard injection** (`TextInjector`) is application-agnostic; direct accessibility API text insertion is not used.
- **LLM base URL is configurable** — any OpenAI-compatible provider (OpenAI, Ollama, LM Studio, etc.) works.
- **CJK input method switching** (`InputMethodManager`) detects 9+ input method variants and must switch to ASCII before paste to avoid double-conversion.
- **Swift 6 / macOS 14+** — the package targets arm64 with swift-version 5 compiler flags.

## Permissions

The app requests three permissions at startup (`Permissions.swift`): microphone, speech recognition, and accessibility. `NSEvent.addGlobalMonitorForEvents` returns nil without accessibility access.
