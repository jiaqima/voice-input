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

## Permissions

On first launch the app requests:
- **Microphone** — for audio capture
- **Speech Recognition** — for transcription
- **Accessibility** — for the Fn key event tap and simulated paste

## LLM Refinement (optional)

Open **Settings** from the menu bar icon to configure an OpenAI-compatible endpoint (base URL, API key, model). Works with OpenAI, Ollama, LM Studio, or any compatible provider. Leave unconfigured to use raw speech recognition output.
