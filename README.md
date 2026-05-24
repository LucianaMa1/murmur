# Murmur

Murmur is a macOS voice keyboard for people who think faster than they type. Hold one key, speak, release, and your words appear in the app you were already using.

- **Hold Fn** → raw local transcription
- **Hold Fn + Control** → transcription plus AI rewrite/polish
- **Release** → Murmur auto-pastes into the active app
- **Highlight text first** → AI mode uses the selection as context

Launch page: <https://murmur.luciana.digital>

## Demo Video Script

“Murmur is a voice keyboard for Mac. Hold `Fn`, speak, release, and your words appear right where your cursor is.”

“For rough thoughts, hold `Fn + Control`. Murmur transcribes, rewrites with AI, and pastes the polished version.”

“If I highlight text first, Murmur uses that selection as context. I can say, ‘reply warmly and ask if Friday works,’ and it writes the response for me.”

“Raw dictation runs locally. AI mode sends text, not audio. Murmur is not a meeting recorder; it is a faster way to write inside the apps I already use.”

## Why Murmur

Murmur is built for the small but constant friction of writing on a Mac: the half-written Slack reply, the email you keep postponing, the thought you lose while switching tabs, and the prompt that needs to sound more polished than your first draft.

### Three Things It Makes Better

- **Capture thoughts before they disappear.** Hold `Fn`, say the sentence, release, and Murmur drops clean text into the current field. No separate recorder, no transcript window to manage, no copy/paste ritual.
- **Turn rough speech into usable writing.** Hold `Fn + Control` when you want Murmur to rewrite the transcript with your prompt, so a messy spoken note can become a clear email, reply, task, or AI prompt.
- **Respond with context.** Highlight text in the current app, hold `Fn + Control`, and say what you want. Murmur uses the selected text as context, so "make this warmer" or "reply yes and ask for Friday" can produce a finished response.
- **Keep your workflow intact.** Murmur runs from the menu bar, uses local Whisper transcription for raw dictation, restores your clipboard after paste, and keeps vocabulary files plain-text so names, commands, and domain jargon stay under your control.

### Who It Helps

- **Everyone** who answer messages all day and need to move from thought to polished text without opening another tool.


### Positioning

Murmur is a lightweight voice keyboard: a faster way to put words exactly where your cursor already is, with optional AI polish when the first spoken version is not the final one.

## Requirements

- macOS 14+
- Apple Silicon recommended
- Xcode / Swift toolchain to build from source
- OpenAI API key for `Fn + Control` polish mode

## Install Murmur

```bash
curl -fsSL https://raw.githubusercontent.com/LucianaMa1/murmur/main/install.sh | bash
```

First launch setup:

1. Grant Microphone access when prompted.
2. Open System Settings → Privacy & Security and enable Murmur for Input Monitoring and Accessibility.
3. Quit and relaunch Murmur after granting permissions.
4. Add your OpenAI key from the menu-bar icon → Settings if you want `Fn + Control` polish mode.

Selection context requires Accessibility permission and depends on whether the frontmost app exposes highlighted text to macOS Accessibility. If an app does not expose the selection, Murmur continues without context and logs the reason in the Debug Panel.

## Build locally

```bash
swift build
./build.sh
open dist/Murmur.app
```

## Launch copy

Product Hunt launch assets live in [`launch-kit/producthunt-launch-kit.md`](launch-kit/producthunt-launch-kit.md).
