#!/usr/bin/env bash
# Wire the pet into Claude Code and the user's shell — any shell.
#
#   scripts/install.sh            hooks + shell autostart + `pet` on PATH
#
# Idempotent: safe to run twice, it only adds what is missing. The build and
# signing steps stay separate (setup-signing.sh, pet rebuild) because they can
# pop macOS dialogs; this script touches only config files.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "${SOURCE:0:1}" = "/" ] || SOURCE="$DIR/$SOURCE"
done
ROOT="$(cd -P "$(dirname "$SOURCE")/.." && pwd)"

SETTINGS="$HOME/.claude/settings.json"
MARK="f1-claude-pet"

# ---------------------------------------------------------------- hooks
# Merge the seven hook events into ~/.claude/settings.json without touching
# anything else in the file. Existing pet hooks are left alone.
mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
ROOT="$ROOT" python3 - "$SETTINGS" <<'PY'
import json, os, sys

path = sys.argv[1]
root = os.environ["ROOT"]
events = ["SessionStart", "UserPromptSubmit", "PostToolUse",
          "PostToolUseFailure", "Notification", "Stop", "SessionEnd"]

with open(path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})
added = []
for event in events:
    entries = hooks.setdefault(event, [])
    have = any("f1-claude-pet" in h.get("command", "") or "F1DockPet" in h.get("command", "")
               for e in entries for h in e.get("hooks", []))
    if not have:
        entries.append({"hooks": [{"type": "command",
                                   "command": f"{root}/scripts/hook {event}",
                                   "timeout": 5}]})
        added.append(event)

if added:
    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"hooks: added {', '.join(added)}")
else:
    print("hooks: already wired")
PY

# ------------------------------------------------------- shell autostart
# Append to the rc file of the user's actual login shell — not everyone runs
# zsh. fish gets fish syntax; anything unrecognised falls back to ~/.profile.
shell_name="$(basename "${SHELL:-/bin/zsh}")"
case "$shell_name" in
  zsh)  RC="$HOME/.zshrc" ;;
  bash) RC="$HOME/.bashrc"
        # macOS Terminal opens login shells, which read .bash_profile and skip
        # .bashrc unless chained. Make sure the chain exists.
        if [ ! -f "$HOME/.bash_profile" ] || ! grep -q '\.bashrc' "$HOME/.bash_profile" 2>/dev/null; then
            printf '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' >> "$HOME/.bash_profile"
        fi ;;
  fish) RC="$HOME/.config/fish/config.fish"; mkdir -p "$(dirname "$RC")" ;;
  *)    RC="$HOME/.profile" ;;
esac

if [ -f "$RC" ] && grep -q "$MARK" "$RC"; then
    echo "shell: $RC already set up"
else
    {
        echo ""
        echo "# f1-claude-pet: start the Dock pet once, if it isn't already running"
        if [ "$shell_name" = "fish" ]; then
            echo "pgrep -qf F1ClaudePet; or open -a \"$ROOT/F1ClaudePet.app\" 2>/dev/null"
            echo "alias pet=\"$ROOT/scripts/pet\""
        else
            echo "pgrep -qf F1ClaudePet || open -a \"$ROOT/F1ClaudePet.app\" 2>/dev/null"
            echo "alias pet=\"$ROOT/scripts/pet\""
        fi
    } >> "$RC"
    echo "shell: autostart + alias added to $RC"
fi

# ------------------------------------------------------------- pet on PATH
# The alias only exists in that one shell; a symlink works from anywhere.
mkdir -p "$HOME/.local/bin"
if [ ! -e "$HOME/.local/bin/pet" ]; then
    ln -s "$ROOT/scripts/pet" "$HOME/.local/bin/pet"
    echo "path: linked ~/.local/bin/pet"
    case ":$PATH:" in
      *":$HOME/.local/bin:"*) ;;
      *) echo "note: ~/.local/bin is not on your PATH — the \`pet\` alias still works" ;;
    esac
else
    echo "path: ~/.local/bin/pet already exists"
fi

echo ""
echo "wired up. Next:  ./scripts/setup-signing.sh && ./scripts/pet rebuild"
