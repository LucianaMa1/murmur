# Murmur

Murmur is an open-source macOS voice keyboard.

Hold **Fn**, speak, release — text appears where your cursor is.  
Hold **Fn + Control** to rewrite with AI.  
Select text first to use it as context.

**English-first. Free. Open source.**

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

For noisy rooms, open Settings → **Speed vs Quality** and switch from **Fast** to **Noisy room**.
Murmur shows model download progress in the floating controls, menu bar tooltip, and Debug. If a larger model is not ready, it falls back to the best available local model.

## Model options

Choose a local transcription model in **Settings → Speed vs Quality → Optimize**.

| Setting | Model | Download size | Best for | Languages |
|---|---|---:|---|---|
| Fast | `openai_whisper-base.en` | ~142 MB | Lowest latency in quiet rooms | English only |
| Noisy room | `openai_whisper-small.en` | ~244 MB | Better English accuracy with background noise | English only |
| Best quality | `openai_whisper-large-v3-v20240930_turbo_632MB` | ~632 MB | Difficult audio, accents, and noisy environments | Multilingual model; Murmur currently runs English mode |

Murmur currently exposes English dictation only. The Best quality model is multilingual-capable, but language selection and auto-detection are not yet productized in the app.

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
