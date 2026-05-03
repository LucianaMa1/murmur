# Murmur

> *Hold a key. Speak quietly. Watch your words appear.*

A voice keyboard for macOS. Hold F5 anywhere on your system, speak, release — your transcribed words appear at the cursor. Hold F6 instead to additionally route the transcript through GPT for light polishing (filler words, punctuation, jargon corrections).

```
hold F5  →  speak  →  release  →  raw text appears at your cursor
hold F6  →  speak  →  release  →  polished text appears at your cursor
```

Powered by [WhisperKit] running on the Apple Neural Engine — your audio never leaves your device. F6 sends only the transcribed text (not audio) to OpenAI for polishing.

**Murmur is a tool, not a transcription studio.** It doesn't manage files, save history, identify speakers, or chat with your transcripts. It does one thing — turn held-key + voice into text at the cursor — and stays out of your way the rest of the time.

[WhisperKit]: https://github.com/argmaxinc/WhisperKit

---

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/lucianaMa/murmur/main/install.sh | bash
```

This will:
1. Clone the repo to `~/.murmur`
2. Build a `Murmur.app` bundle (~2 minutes the first time)
3. Move it to `/Applications`
4. Launch it

After install, look for the 〰️ icon in your menu bar.

> **Requirements**: macOS 14+, Apple Silicon, Xcode Command Line Tools (`xcode-select --install` if missing).

---

## First-time setup

Murmur needs three permissions — macOS will prompt for each:

| Permission | Why | Where to grant |
|---|---|---|
| **Microphone** | Capture your voice | First launch prompt |
| **Input Monitoring** | Listen for F5/F6 globally | System Settings → Privacy & Security → Input Monitoring |
| **Accessibility** | Paste text into the active app | System Settings → Privacy & Security → Accessibility |

After granting Input Monitoring or Accessibility, **quit and relaunch the app** — macOS doesn't apply TCC changes to running processes.

Then click the menu bar icon → **Settings** → paste your OpenAI API key (only required if you want F6 polishing; F5 works offline forever).

---

## Usage

| Hotkey | What it does |
|---|---|
| Hold **F5** | Records, transcribes locally with Whisper, pastes the raw text |
| Hold **F6** | Records, transcribes, sends to GPT for polish, pastes the polished text |

Both keys work the same way: hold to record, release to process. There's no toggle — your finger on the key is the recording indicator.

The menu bar icon shows what's happening:

| Icon | State |
|---|---|
| 〰️ gray | Idle |
| 🔴 pulsing | Recording (F5 — raw mode) |
| 🟣 pulsing | Recording (F6 — polish mode) |
| 🔵 cycling | Transcribing or calling GPT |
| 🟠 warning | Error (hover the icon for details) |

---

## How it works

```
F5/F6 pressed
    │
    ▼
┌──────────────────┐
│ AVAudioEngine    │  Capture mic at 16 kHz mono PCM
└────────┬─────────┘
         ▼
┌──────────────────┐
│ WhisperKit       │  Local transcription on the ANE
│ (base.en, 74 MB) │  ~1 sec for 5 sec of audio on M-series
└────────┬─────────┘
         │
    ┌────┴────┐
    │         │
   F5        F6
    │         ▼
    │   ┌─────────────────┐
    │   │ OpenAI API      │  Polish transcript (text only —
    │   │ gpt-4o-mini     │   audio never leaves the device)
    │   └────────┬────────┘
    │            │
    └────────┬───┘
             ▼
   ┌──────────────────┐
   │ NSPasteboard     │  Copy text
   │ + simulated ⌘V   │  Paste into frontmost app
   │ + restore prev   │  Restore your previous clipboard
   └──────────────────┘
```

A few design decisions worth calling out:

- **F5 is fully local.** No API key required, no network needed. Useful when you want privacy or are working offline.
- **F6 is opt-in cloud.** Only the transcribed *text* is sent to OpenAI — never the audio. The polish prompt is fully customizable in Settings.
- **Clipboard restoration.** After auto-paste, your previous clipboard contents are restored, so dictation doesn't clobber what you copied earlier. (Same approach Raycast and Superwhisper take.)
- **Hold-to-talk.** No accidental activation, no end-of-speech detection latency. Your finger on the key is the start/stop signal.
- **CGEventTap at HID level.** Murmur intercepts F5/F6 before any other listener sees them, including macOS's own dictation shortcut on F5. While Murmur is running, those keys belong to it.

---

## Configuration

Open the menu bar icon → **Settings**.

- **OpenAI API Key** — stored in macOS Keychain, never in plain text.
- **Model** — `gpt-4o-mini` (fast, cheap, default), `gpt-4o`, or `gpt-4-turbo`.
- **Auto-paste** — toggle off to copy-only.
- **LLM Prompt** — fully customizable. Default is a "polish, don't rewrite" prompt tuned for dictation.

To change the Whisper model size, edit `Sources/Transcriber.swift`:

```swift
init(modelName: String = "openai_whisper-base.en") {
//                       ^^^^^^^^^^^^^^^^^^^^^^^
// Options: tiny.en (39MB), base.en (74MB), small.en (244MB),
//          large-v3-turbo (1.5GB, most accurate)
```

Models download automatically on first use to `~/Library/Application Support/`.

---

## Teaching Murmur your jargon

Whisper sometimes mishears technical terms. "kubectl" becomes "cubicle". "k8s" becomes "k aids". Your colleague's name becomes a different name. The fix is a vocabulary file Murmur reads on every F6 polish.

**The file lives at `~/.murmur/vocabulary.txt`** and looks like this:

```
# One term per line. Lines starting with # are ignored.

# Plain term — Murmur preserves spelling and casing exactly:
kubectl
GraphQL
k8s
gpt-4o-mini
LangSmith

# Mishearing fix — replace 'cubicle' with 'kubectl' when polishing:
cubicle => kubectl
k aids  => k8s
```

Edit it from the menu bar (`Edit Vocabulary…`) or directly in any editor. Every entry gets injected into the F6 polish prompt as authoritative spelling — Whisper still does the raw transcription, but the LLM corrects mishearings using your list.

This works because LLMs have huge context windows (the prompt holds hundreds of terms easily) and actually understand context — they know "deploy to the cubicle cluster" makes no sense and your vocabulary explains what you actually meant.

### Optional: learn from corrections

In Settings, enable **Learn from corrections**. When you use F6 and the LLM makes a non-trivial substitution (like `cubicle → kubectl`), Murmur appends it to `~/.murmur/learned.txt`.

That file is plain text. You can read it, edit it, version-control it, sync it across machines, or wipe it whenever you like. Murmur won't ever surprise you with what it has learned — the answer is always one `cat ~/.murmur/learned.txt` away.

This is **off by default**. Murmur stores nothing about you unless you turn this on.

---

## Building from source

```bash
git clone https://github.com/lucianaMa/murmur.git
cd murmur
./build.sh
open dist/Murmur.app
```

`build.sh` runs `swift build -c release`, assembles a proper `.app` bundle with `Info.plist`, and ad-hoc signs it.

---

## Project layout

```
murmur/
├── Package.swift                  # SPM manifest
├── build.sh                       # Compile → .app bundle
├── install.sh                     # One-shot installer
├── README.md
└── Murmur/
    ├── Info.plist                 # Bundle metadata + permission strings
    └── Sources/
        ├── MurmurApp.swift                # @main, AppDelegate
        ├── HotkeyManager.swift            # F5/F6 via CGEventTap
        ├── AudioRecorder.swift            # AVAudioEngine → 16kHz WAV
        ├── Transcriber.swift              # WhisperKit wrapper
        ├── OpenAIClient.swift             # /v1/chat/completions
        ├── ClipboardWriter.swift          # NSPasteboard + sim ⌘V
        ├── DictationCoordinator.swift     # Pipeline orchestration
        ├── StatusBarController.swift      # Menu bar icon + states
        └── SettingsWindowController.swift # SwiftUI settings + Keychain
```

---

## Troubleshooting

**The menu bar icon doesn't appear.** Make sure you granted Input Monitoring permission and **relaunched** the app afterwards. Check Console.app for "Failed to create CGEventTap" messages.

**F5/F6 do nothing.** Check the menu bar icon — does it turn red/purple when you hold the key? If not, Input Monitoring isn't granted. If yes but no text appears, Accessibility isn't granted (paste is blocked).

**"OpenAI API key not set" error on F6.** Open Settings from the menu bar icon and paste your key. F5 doesn't need a key.

**Audio is empty / nothing transcribed.** Microphone permission may have been denied. Check System Settings → Privacy & Security → Microphone.

**F5 conflicts with another app's shortcut.** Murmur consumes F5/F6 system-wide while running, so other apps won't see them. Quit Murmur from the menu bar to restore them.

---

## License

MIT — see [LICENSE](LICENSE).

---

*Built by [@lucianaMa](https://github.com/lucianaMa).*
