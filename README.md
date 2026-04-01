# VoiceInput

A macOS background app that lets you dictate text into any application using the Fn key.

Hold **Fn** for 0.5 seconds to start recording. Release to stop — the transcribed text is pasted into whatever is active. A floating capsule panel shows recording status and live waveform.

## Features

- **Fn key trigger** — short presses still open the macOS emoji picker
- **Multiple languages** — English, Simplified Chinese, Traditional Chinese, Japanese, Korean
- **LLM refinement** — optionally polish the transcript via any OpenAI-compatible API (fixes homophones, misheard technical terms)
- **CJK-safe paste** — automatically switches to ASCII input mode before pasting, then restores your input method
- **No dependencies** — pure Swift using only system frameworks

## Usage

1. Launch VoiceInput — it runs as a menu bar icon (microphone) with no dock icon.
2. Click the menu bar icon to select your recognition language or configure LLM refinement.
3. In any application, **hold the Fn (Globe) key** for about half a second to start recording. A floating capsule with a live waveform appears to confirm recording is active.
4. Speak your text, then **release the Fn key** to stop recording. The transcribed text is automatically pasted into the active text field.
5. Short Fn presses (under 0.5 seconds) are ignored, so the macOS emoji picker still works normally.

## Requirements

- macOS 14+
- Apple Silicon (arm64)

## Build & Install

```bash
make install   # builds and copies to ~/Applications/VoiceInput.app
```

Or just run locally:

```bash
make run
```

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
