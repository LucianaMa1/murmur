# Murmur

Murmur is a macOS menu-bar dictation app for getting thoughts into text without leaving the app you are already using.

- **Hold F5** → raw local transcription
- **Hold F6** → transcription plus LLM polish
- **Release** → Murmur auto-pastes into the active app

Launch page: <https://murmur.luciana.digital>

## Features

- Menu-bar-only macOS app
- Global hold-to-record hotkeys
- Local Whisper transcription via WhisperKit
- Optional OpenAI polish mode
- Auto-paste into the active text field
- Plain-text vocabulary files for names, commands, and domain jargon

## Requirements

- macOS 14+
- Apple Silicon recommended
- Xcode / Swift toolchain to build from source
- OpenAI API key for F6 polish mode

## Install prototype

```bash
curl -fsSL https://raw.githubusercontent.com/LucianaMa1/murmur/main/install.sh | bash
```

First launch setup:

1. Grant Microphone access when prompted.
2. Open System Settings → Privacy & Security and enable Murmur for Input Monitoring and Accessibility.
3. Quit and relaunch Murmur after granting permissions.
4. Add your OpenAI key from the menu-bar icon → Settings if you want F6 polish mode.

## Build locally

```bash
swift build
./build.sh
open dist/Murmur.app
```

## Launch copy

Product Hunt launch assets live in [`launch-kit/producthunt-launch-kit.md`](launch-kit/producthunt-launch-kit.md).
