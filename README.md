# Speech - OpenAI Text-to-Speech GUI

![PURE VIBE CODING](https://img.shields.io/badge/PURE-VIBE_CODING-magenta)

A Crystal GUI application using the OpenAI Text-to-Speech API. Enter text, choose voice/model/format, optionally add instructions, then generate and play AI‑generated speech.

## Features

- Uses OpenAI GPT-4o-mini-TTS / tts-1 / tts-1-hd models
- 11 built‑in voices selectable
- Multiple audio output formats (mp3, wav, pcm, opus, flac, aac)
- Optional instruction prompt to change tone / style
- Save-to-file option with custom path
- Simple, compact cross‑platform GUI using VLC (libVLC) for playback

## Prerequisites

1. Crystal language installed
2. OpenAI API key (https://platform.openai.com/api-keys)
3. VLC (libVLC) runtime installed

Examples to install libVLC:
- Ubuntu/Debian: `sudo apt install vlc libvlc-dev`
- Fedora: `sudo dnf install vlc vlc-devel`
- Arch: `sudo pacman -S vlc`
- macOS (Homebrew): `brew install vlc`

## Install dependencies

```bash
shards install
```

## Build

```bash
# Speech - OpenAI TTS GUI

Minimal Crystal GUI for OpenAI Text-to-Speech. Type text, pick voice / model / format, optionally add instructions, then generate & play (or save) audio.

## Highlights
* Models: gpt-4o-mini-tts / tts-1 / tts-1-hd
* Voices (11): alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer
* Formats: mp3 (default), wav, pcm, opus, flac, aac
* Optional instructions & save-to-file

## Quick Start
Prerequisites: Crystal, OpenAI API key, VLC (libVLC) installed.

```bash
shards install
export OPENAI_API_KEY="your-api-key"
shards build --release -Dpreview_mt
bin/speech
```

## Usage
1. Select Voice / Model / Format
2. (Optional) Enter instructions (e.g. "Warm, calm")
3. Enter text
4. (Optional) Enable "Save file" and choose a path
5. Click "Generate & Play"

## Notes
* Playback uses VLC (libVLC). Ensure libVLC is installed and linkable on your system.
* Disclose to users the voice is AI-generated
* API usage may incur cost
* Requires internet

## Dev
```bash
crystal run src/speech.cr
```
Dependencies: [uing](https://github.com/kojix2/uing), [openai](https://github.com/kojix2/crystal-openai).

## License
MIT
- [uing](https://github.com/kojix2/uing) – GUI toolkit
