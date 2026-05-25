#!/bin/bash
# install.sh — one-shot installer for Murmur.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/LucianaMa1/murmur/main/install.sh | bash

set -e

REPO="${MURMUR_REPO:-LucianaMa1/murmur}"
BRANCH="${MURMUR_BRANCH:-main}"
SOURCE_DIR="${MURMUR_SOURCE_DIR:-$HOME/Library/Caches/Murmur/source}"

echo "🌊 Installing Murmur…"
echo ""

# Pre-flight checks ------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ Murmur is macOS-only."
    exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "⚠️  Murmur is optimized for Apple Silicon. Intel Macs may work but will be slow."
fi

if ! command -v swift &> /dev/null; then
    echo "❌ Swift not found. Install Xcode Command Line Tools first:"
    echo "   xcode-select --install"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "❌ git is required."
    exit 1
fi

# Fetch source -----------------------------------------------------------------
mkdir -p "$(dirname "$SOURCE_DIR")"
if [[ -d "$SOURCE_DIR/.git" ]]; then
    echo "📥 Updating existing checkout…"
    cd "$SOURCE_DIR"
    git fetch origin "$BRANCH"
    git reset --hard "origin/$BRANCH"
else
    echo "📥 Cloning $REPO…"
    rm -rf "$SOURCE_DIR"
    git clone --branch "$BRANCH" "https://github.com/$REPO.git" "$SOURCE_DIR"
    cd "$SOURCE_DIR"
fi

# Build ------------------------------------------------------------------------
echo ""
echo "🔨 Building (this takes ~2 minutes the first time)…"
chmod +x build.sh
./build.sh

# Install ----------------------------------------------------------------------
echo ""
echo "📦 Installing to /Applications…"
echo "🛑 Stopping any running Murmur instance…"
osascript -e 'tell application "Murmur" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x "Murmur" >/dev/null 2>&1 || true
sleep 0.5

if [[ -d "/Applications/Murmur.app" ]]; then
    rm -rf "/Applications/Murmur.app"
fi
mv "dist/Murmur.app" "/Applications/Murmur.app"

# Launch -----------------------------------------------------------------------
echo ""
echo "🚀 Launching Murmur…"
open "/Applications/Murmur.app"

cat <<'EOF'

  ✅ Murmur installed!

  Look for the 〰️ icon in your menu bar.

  First-time setup:
    1. Grant Microphone access when prompted.
    2. Open System Settings → Privacy & Security, enable Murmur for:
         • Input Monitoring
         • Accessibility
    3. Quit Murmur from the menu bar, then relaunch it (macOS only
       applies these permissions on the next launch).
    4. Click the menu bar icon → Settings → paste your OpenAI key
       (only needed for Fn + Control AI rewrite).

  Usage:
    • Hold Fn to dictate (raw transcription, fully local).
    • Hold Fn + Control to dictate + rewrite via GPT.

EOF
