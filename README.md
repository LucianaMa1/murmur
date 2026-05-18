# Murmur

Murmur is a macOS voice keyboard for people who think faster than they type. Hold one key, speak, release, and your words appear in the app you were already using.

- **Hold Fn** → raw local transcription
- **Hold Fn + Control** → transcription plus AI rewrite/polish
- **Release** → Murmur auto-pastes into the active app

Launch page: <https://murmur.luciana.digital>

## Why Murmur

Murmur is built for the small but constant friction of writing on a Mac: the half-written Slack reply, the email you keep postponing, the thought you lose while switching tabs, and the prompt that needs to sound more polished than your first draft.

### Three Things It Makes Better

- **Capture thoughts before they disappear.** Hold `Fn`, say the sentence, release, and Murmur drops clean text into the current field. No separate recorder, no transcript window to manage, no copy/paste ritual.
- **Turn rough speech into usable writing.** Hold `Fn + Control` when you want Murmur to rewrite the transcript with your prompt, so a messy spoken note can become a clear email, reply, task, or AI prompt.
- **Keep your workflow intact.** Murmur runs from the menu bar, uses local Whisper transcription for raw dictation, restores your clipboard after paste, and keeps vocabulary files plain-text so names, commands, and domain jargon stay under your control.

### Who It Helps

- **Founders and operators** who answer messages all day and need to move from thought to polished text without opening another tool.
- **Builders and technical teams** who dictate jargon-heavy notes, commands, tickets, changelogs, and prompts that normal dictation often mangles.
- **Creators and students** who want a quiet thinking companion for drafts, outlines, reflections, and quick capture.

### Positioning

Murmur is not a meeting transcription suite or a note database. It is a lightweight voice keyboard: a faster way to put words exactly where your cursor already is, with optional AI polish when the first spoken version is not the final one.

## Requirements

- macOS 14+
- Apple Silicon recommended
- Xcode / Swift toolchain to build from source
- OpenAI API key for `Fn + Control` polish mode

## Install prototype

```bash
curl -fsSL https://raw.githubusercontent.com/LucianaMa1/murmur/main/install.sh | bash
```

First launch setup:

1. Grant Microphone access when prompted.
2. Open System Settings → Privacy & Security and enable Murmur for Input Monitoring and Accessibility.
3. Quit and relaunch Murmur after granting permissions.
4. Add your OpenAI key from the menu-bar icon → Settings if you want `Fn + Control` polish mode.

## Build locally

```bash
swift build
./build.sh
open dist/Murmur.app
```

## Launch copy

Product Hunt launch assets live in [`launch-kit/producthunt-launch-kit.md`](launch-kit/producthunt-launch-kit.md).
