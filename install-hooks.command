#!/bin/bash
# Megadesk — Hook installer for Claude Code
# Double-click this file to install.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SRC="$SCRIPT_DIR/megadesk-hook.py"
HOOK_DEST="$HOME/.claude/megadesk-hook.py"

echo "Installing Megadesk hooks for Claude Code..."
echo ""

# 1. Copy hook script
mkdir -p "$HOME/.claude"
if [ ! -f "$HOOK_SRC" ]; then
    echo "✗ megadesk-hook.py not found next to this script."
    echo "  Make sure both files are in the same folder."
    read -p "Press Enter to close..."
    exit 1
fi

cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo "✓ Hook script installed to ~/.claude/megadesk-hook.py"

# 2. Patch ~/.claude/settings.json
python3 << 'PYEOF'
import json, os
from pathlib import Path

settings_path = Path.home() / ".claude" / "settings.json"

if settings_path.exists():
    try:
        settings = json.loads(settings_path.read_text())
    except Exception:
        settings = {}
else:
    settings = {}

hook_cmd = {
    "type": "command",
    "command": "python3 ~/.claude/megadesk-hook.py",
    "timeout": 3
}

events = {
    "PreToolUse":       [{"matcher": ".*", "hooks": [hook_cmd]}],
    "PostToolUse":      [{"matcher": ".*", "hooks": [hook_cmd]}],
    "Stop":             [{"hooks": [hook_cmd]}],
    "UserPromptSubmit": [{"hooks": [hook_cmd]}],
    "SessionStart":     [{"hooks": [hook_cmd]}],
}

hooks = settings.setdefault("hooks", {})
added = []

for event, config in events.items():
    existing = hooks.get(event, [])
    already = any(hook_cmd["command"] in str(e) for e in existing)
    if not already:
        hooks[event] = existing + config
        added.append(event)

tmp = str(settings_path) + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
os.rename(tmp, str(settings_path))

if added:
    print(f"✓ Hooks registered in ~/.claude/settings.json")
else:
    print("✓ Hooks were already configured — nothing to do")
PYEOF

echo ""
echo "Done! Open a new Claude Code session to start seeing sessions in Megadesk."
echo ""
read -p "Press Enter to close..."
