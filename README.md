# VoiceInput

A macOS background app that lets you dictate text into any application using the Fn key.

Tap **Fn** once, then press and hold it again for 0.5 seconds to start recording. Release the second hold to stop — the transcribed text is pasted into whatever is active. A floating capsule panel shows recording status and live waveform.

## Features

- **Fn key trigger** — tap Fn once, then press and hold it again; the app observes Fn globally and does not suppress macOS's single-Fn behavior
- **Multiple languages** — English, Simplified Chinese, Traditional Chinese, Japanese, Korean
- **LLM refinement** — optionally polish the transcript via any OpenAI-compatible API (fixes homophones, misheard technical terms)
- **CJK-safe paste** — automatically switches to ASCII input mode before pasting, then restores your input method
- **Two speech backends** — Apple Speech (online, streaming) or whisper.cpp (fully offline, local)
- **No Swift dependencies** — pure Swift using system frameworks + whisper.cpp (C library, bundled)

## Usage

1. Launch VoiceInput — it runs as a menu bar icon (microphone) with no dock icon.
2. Click the menu bar icon to select your recognition language or configure LLM refinement.
3. In any application, **tap the Fn (Globe) key once**, then press and hold it again within about half a second. Recording starts after the second hold reaches about half a second, and a floating capsule with a live waveform confirms recording is active.
4. Speak your text, then **release the second Fn hold** to stop recording. The transcribed text is automatically pasted into the active text field.
5. A single Fn press or a single long Fn hold does not start dictation. VoiceInput observes Fn globally, so the first tap still reaches macOS or any other Fn-based behavior you already use.

## Requirements

- macOS 14+
- Apple Silicon (arm64)
- cmake (for building whisper.cpp): `brew install cmake`

## Build & Install

```bash
make download-model   # download default whisper model (large-v3-turbo-q8_0, ~874MB, one-time)
make install          # builds whisper.cpp + app, copies to ~/Applications
```

Or just run locally:

```bash
make run
```

To use a different whisper model: `make download-model DEFAULT_MODEL=small.en`

### Stable signing (optional)

By default the app is ad-hoc signed, which means macOS resets all permission grants after every rebuild. To avoid re-granting permissions each time, create a self-signed certificate:

1. Open **Keychain Access** → **Certificate Assistant** → **Create a Certificate…**
2. Name: `VoiceInput Dev`, Identity Type: **Self Signed Root**, Certificate Type: **Code Signing**
3. Build with the certificate:
   ```bash
   make install SIGN_IDENTITY="VoiceInput Dev"
   ```

## Permissions

On first launch the app requests:
- **Microphone** — for audio capture
- **Speech Recognition** — for transcription
- **Accessibility** — for reading the focused text field and inserting text via the Accessibility API
- **Input Monitoring** — fallback for simulated Cmd+V paste (add manually in System Settings > Privacy & Security > Input Monitoring if the clipboard fallback doesn't work)

> **Note:** The app is ad-hoc signed, so macOS invalidates permission grants after each rebuild. You may need to re-grant Accessibility and Input Monitoring permissions after running `make install`.

## LLM Refinement (optional)

Open **Settings** from the menu bar icon to configure an OpenAI-compatible endpoint (base URL, API key, model). Works with OpenAI, Ollama, LM Studio, or any compatible provider. Leave unconfigured to use raw speech recognition output.

VoiceInput treats refinement as best-effort and falls back to the raw transcript if the model does not respond within about 2 seconds. Fast instruction models work best here; slower reasoning models such as `deepseek-r1` may time out more often.

## Acknowledgement

This project is inspired by this [repo](https://github.com/yetone/voice-input-src).
