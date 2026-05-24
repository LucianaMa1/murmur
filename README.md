# Murmur

Murmur is an open-source macOS voice keyboard.

Hold **Fn**, speak, release — text appears where your cursor is.  
Hold **Fn + Control** to rewrite with AI.  
Select text first to use it as context.

**English only. Free. Open source.**

Website: <https://murmur.luciana.digital>

## Why it exists

Typing interrupts thought. Murmur lets you speak into the app you are already using.

Use it for:

- Slack replies
- emails
- notes
- tasks
- AI prompts

## How it works

| Action | Result |
|---|---|
| Hold **Fn** | local dictation |
| Hold **Fn + Control** | AI rewrite |
| Select text + **Fn + Control** | context-aware rewrite |
| Release | paste into the active app |

Raw dictation runs locally with WhisperKit. AI mode sends text, not audio, to OpenAI.

AI rewrite mode also supports:

- Style Profiles for Email, Work, Casual, and Other apps
- Tone and length preferences per profile
- A Dictionary UI for names, tools, commands, and mishearing fixes

## Install

Requires macOS 14+. Apple Silicon recommended.

```bash
curl -fsSL https://raw.githubusercontent.com/LucianaMa1/murmur/main/install.sh | bash
```

Then grant:

- Microphone
- Input Monitoring
- Accessibility

Add an OpenAI API key in Settings for AI rewrite mode.

## Build from source

```bash
swift build
./build.sh
open dist/Murmur.app
```

## Repo structure

```text
Sources/       macOS app source
Resources/     app icon assets
launch-site/   public website
scripts/       icon generation helper
```

## License

MIT
