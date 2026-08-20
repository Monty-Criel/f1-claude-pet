#!/usr/bin/env bash
# Remove every trace of the pet from this machine.
#
#   scripts/uninstall.sh            interactive: shows the plan, asks once
#   scripts/uninstall.sh --yes      no questions
#   scripts/uninstall.sh --dry-run  print what would be removed, touch nothing
#
# Cleans: the running app, Claude Code hooks, shell autostart lines (zsh,
# bash, fish, profile), the `pet` symlink, ~/.f1-claude-pet, saved settings
# (defaults), the Accessibility grant, the signing certificate, and build
# output. The cloned repo itself is left for you to delete — this script
# lives inside it.
set -uo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [ "${SOURCE:0:1}" = "/" ] || SOURCE="$DIR/$SOURCE"
done
ROOT="$(cd -P "$(dirname "$SOURCE")/.." && pwd)"

DRY=0; YES=0
for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY=1 ;;
      --yes)     YES=1 ;;
      *) echo "usage: uninstall.sh [--yes] [--dry-run]"; exit 2 ;;
    esac
done

run() {  # run "description" cmd args...
    local desc="$1"; shift
    if [ "$DRY" = 1 ]; then
        echo "would: $desc"
    else
        echo "  - $desc"
        "$@" 2>/dev/null || true
    fi
}

echo "This removes the F1 Claude Pet from:"
echo "  app        the running pet and F1ClaudePet.app"
echo "  hooks      the 7 pet entries in ~/.claude/settings.json (rest untouched)"
echo "  shell      autostart + alias lines in zsh/bash/fish rc files"
echo "  path       the pet symlink in ~/.local/bin and /usr/local/bin"
echo "  state      ~/.f1-claude-pet"
echo "  settings   saved preferences (defaults domains, old name included)"
echo "  privacy    the Accessibility grant (tccutil)"
echo "  keychain   the 'F1DockPet Dev' self-signed certificate"
echo ""
if [ "$DRY" = 0 ] && [ "$YES" = 0 ]; then
    printf "Proceed? [y/N] "
    read -r reply
    case "$reply" in y|Y|yes|YES) ;; *) echo "aborted, nothing touched"; exit 0 ;; esac
fi

# ------------------------------------------------------------------- app
run "stop the running pet"        pkill -f F1ClaudePet
run "remove $ROOT/F1ClaudePet.app" rm -rf "$ROOT/F1ClaudePet.app"
run "remove build output"          rm -rf "$ROOT/.build"

# ----------------------------------------------------------------- hooks
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -qE "f1-claude-pet|F1DockPet" "$SETTINGS"; then
    if [ "$DRY" = 1 ]; then
        echo "would: strip pet hooks from $SETTINGS (backup kept as .pet-uninstall.bak)"
    else
        echo "  - strip pet hooks from $SETTINGS"
        cp "$SETTINGS" "$SETTINGS.pet-uninstall.bak"
        python3 - "$SETTINGS" <<'PY' || echo "    (edit failed — restore from .pet-uninstall.bak)"
import json, sys

path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)

def ours(entry):
    return all("f1-claude-pet" in h.get("command", "") or "F1DockPet" in h.get("command", "")
               for h in entry.get("hooks", [])) and entry.get("hooks")

hooks = settings.get("hooks", {})
for event in list(hooks):
    kept = [e for e in hooks[event] if not ours(e)]
    # Mixed matcher groups: drop only our commands, keep the group.
    for e in kept:
        e["hooks"] = [h for h in e.get("hooks", [])
                      if "f1-claude-pet" not in h.get("command", "")
                      and "F1DockPet" not in h.get("command", "")]
    kept = [e for e in kept if e.get("hooks")]
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]
if not hooks and "hooks" in settings:
    del settings["hooks"]

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PY
    fi
else
    echo "  - hooks: none found"
fi

# ----------------------------------------------------------------- shell
# Remove every line that mentions the pet, in every rc file it may have
# landed in — the user's shell today is not necessarily the one at install.
for RC in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
          "$HOME/.config/fish/config.fish"; do
    [ -f "$RC" ] || continue
    if grep -qE "f1-claude-pet|F1ClaudePet|f1dockpet|F1DockPet" "$RC"; then
        if [ "$DRY" = 1 ]; then
            echo "would: clean $(grep -cE "f1-claude-pet|F1ClaudePet|f1dockpet|F1DockPet" "$RC") line(s) from $RC"
        else
            echo "  - clean pet lines from $RC"
            cp "$RC" "$RC.pet-uninstall.bak"
            grep -vE "f1-claude-pet|F1ClaudePet|f1dockpet|F1DockPet" "$RC.pet-uninstall.bak" > "$RC"
        fi
    fi
done

# ------------------------------------------------------------------ path
for LINK in "$HOME/.local/bin/pet" "/usr/local/bin/pet" "$HOME/bin/pet"; do
    if [ -L "$LINK" ] && readlink "$LINK" | grep -qE "f1-claude-pet|F1DockPet"; then
        run "remove symlink $LINK" rm -f "$LINK"
    fi
done

# ----------------------------------------------------------------- state
[ -d "$HOME/.f1-claude-pet" ] && run "remove ~/.f1-claude-pet" rm -rf "$HOME/.f1-claude-pet"

# -------------------------------------------------------------- settings
for DOMAIN in com.nibel.f1claudepet com.nibel.f1dockpet F1ClaudePet F1DockPet; do
    if defaults read "$DOMAIN" >/dev/null 2>&1; then
        run "delete saved settings ($DOMAIN)" defaults delete "$DOMAIN"
    fi
done

# --------------------------------------------------------------- privacy
run "reset Accessibility grant" tccutil reset Accessibility com.nibel.f1claudepet
run "reset old-name Accessibility grant" tccutil reset Accessibility com.nibel.f1dockpet

# -------------------------------------------------------------- keychain
if security find-identity -v -p codesigning 2>/dev/null | grep -q "F1DockPet Dev"; then
    if [ "$DRY" = 1 ]; then
        echo "would: delete 'F1DockPet Dev' certificate + key from the login keychain"
    else
        echo "  - delete 'F1DockPet Dev' certificate from the login keychain"
        # Trust settings first (may ask for your password), then cert + key.
        PEM=$(mktemp)
        security find-certificate -c "F1DockPet Dev" -p > "$PEM" 2>/dev/null \
            && security remove-trusted-cert "$PEM" 2>/dev/null
        rm -f "$PEM"
        security delete-identity -c "F1DockPet Dev" 2>/dev/null \
            || security delete-certificate -c "F1DockPet Dev" 2>/dev/null
    fi
fi

# ------------------------------------------------------------------ temp
run "remove temp exhaust" sh -c 'rm -f /tmp/pet-*.wav /tmp/f1-claude-pet.gif /tmp/rb22.png'

echo ""
if [ "$DRY" = 1 ]; then
    echo "dry run — nothing was touched."
else
    echo "done. Backups of edited files sit next to them as *.pet-uninstall.bak."
    echo "The notification permission entry disappears from System Settings on"
    echo "its own once macOS notices the app is gone."
fi
echo "Last step, when you're ready:"
echo "  rm -rf \"$ROOT\""
