# 🏎️ f1-claude-pet

**A Formula 1 car that lives on your macOS Dock and races when Claude Code works.**

[![Tests](https://github.com/Monty-Criel/f1-claude-pet/actions/workflows/tests.yml/badge.svg)](https://github.com/Monty-Criel/f1-claude-pet/actions/workflows/tests.yml)
![Coverage](docs/coverage.svg)

> **Beta — v0.9.0.** It runs all day on the author's machine, but expect rough
> edges, and expect things to move between versions.

Ask Claude Code a question and the car launches off the line in a cloud of tyre
smoke. While it works, the car laps the Dock — hot stints, cool-down laps, sparks
over the kerbs. When Claude needs your input it pits and flashes its rain light.
When the job lands: donut, smoke, and Claude's actual answer on the pit board.

Click the car and a **pit wall** opens — the live Claude Code conversation, with a
box to reply, plus a tab showing your plan usage.

**It costs you nothing to run.** The pet is a native Swift app driven by shell
hooks. No model calls, no network, no tokens — the only exception is when *you*
type a reply in the pit wall, which is exactly like typing it into Claude Code.

---

## Install

Needs **macOS 15+**, Xcode command line tools, and Claude Code.

```bash
git clone https://github.com/Monty-Criel/f1-claude-pet.git ~/Documents/GitHub/f1-claude-pet
cd ~/Documents/GitHub/f1-claude-pet
./scripts/setup-signing.sh   # one-time: stable identity so macOS keeps its permissions
./scripts/pet rebuild        # build, bundle and launch
```

A car should appear on your Dock, and a 🏁 icon in your menu bar.

> On a MacBook with a notch, the menu bar icon can land behind it —
> ⌘-drag it left to pull it out.

### Two permissions, both optional but worth it

| Grant | What it buys | Where |
|---|---|---|
| **Accessibility** | The car measures your Dock exactly and parks flush against it. Without it, it falls back to an estimate that's usually a few pixels off. | System Settings → Privacy & Security → Accessibility → tick **F1ClaudePet** |
| **Keychain** | The Usage tab reads your Claude Code OAuth token to fetch plan limits (a billing query — no tokens spent). macOS prompts on first use; choose **Always Allow**. | Prompt appears on first click |

Check what it actually has:

```bash
cat ~/.f1-claude-pet/status
```

`accessibility: true` and `measured: true` means you're set.

### Wire it to Claude Code

The car needs hooks in `~/.claude/settings.json` to know what Claude is doing:

```json
{
  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "~/Documents/GitHub/f1-claude-pet/scripts/hook SessionStart",     "timeout": 5 }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/Documents/GitHub/f1-claude-pet/scripts/hook UserPromptSubmit", "timeout": 5 }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "~/Documents/GitHub/f1-claude-pet/scripts/hook PostToolUse",      "timeout": 5 }] }],
    "PostToolUseFailure": [{ "hooks": [{ "type": "command", "command": "~/Documents/GitHub/f1-claude-pet/scripts/hook PostToolUseFailure", "timeout": 5 }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "~/Documents/GitHub/f1-claude-pet/scripts/hook Notification",     "timeout": 5 }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "~/Documents/GitHub/f1-claude-pet/scripts/hook Stop",             "timeout": 5 }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "~/Documents/GitHub/f1-claude-pet/scripts/hook SessionEnd",       "timeout": 5 }] }]
  }
}
```

Each hook is a ~5 ms shell script that writes one word to a file. It prints
nothing and always exits 0, so it can never interfere with your work.

### Start it with your terminal

```bash
echo 'pgrep -qf F1ClaudePet || open ~/Documents/GitHub/f1-claude-pet/F1ClaudePet.app' >> ~/.zshrc
echo 'alias pet="~/Documents/GitHub/f1-claude-pet/scripts/pet"' >> ~/.zshrc
```

---

## What the car is telling you

| On screen | Meaning |
|---|---|
| 🏁 Burnout, then a flat-out lap | You just sent a prompt |
| Lapping the Dock, hot and cool stints | Claude is working |
| Quick burst + smoke, tool name on the board | A tool just ran |
| Parked in the pits, rain light flashing | **Claude needs your input** |
| Donut, smoke, Claude's answer on the board | Job done |
| Stopped, tyre blown, engine on fire | Something failed |
| Parked quietly, session name showing | Idle |

## Things you can do

- **Click the car** → the pit wall opens: live conversation, a reply box, your two
  most recent sessions as tabs, and a **Usage** tab.
- **Right-click the car** → moves it to the other end of the Dock (same as
  the Pit box menu). The second car swaps with it.
- **Usage tab** → plan limits (5-hour, weekly) as bars, a Mon–Sun prompt
  histogram with estimates for days still to come, and activity stats.
- **Pin button** → the panel rides above the car, or unpin to drag it anywhere.
- **Menu bar 🏁** → switch car, change tyre compound, pause, trigger any
  animation, turn on a second car, restart, quit.

## The garage

**Formula 1** — Red Bull RB22, Ferrari SF-26, Mercedes W17, McLaren MCL40,
Aston Martin AMR26, Williams FW48, Alpine A526, Audi R26, Racing Bulls RB03,
Haas VF-26, Cadillac.

**GT3** — Porsche 911 GT3 RS, McLaren 720S, BMW M4, Mercedes-AMG GT3 (incl.
Verstappen livery and AMG ONE), Aston Martin Vantage.

Every car is drawn as vector paths rasterised to hard pixels, so they stay
crisp at any size. F1 cars wear real Pirelli compounds — pick soft, medium,
hard, intermediate or wet from the menu bar, and the sidewall ring changes.

**Second car (beta)** — bind a second session to its own car in the menu bar.
It parks at the other end of the Dock with its own pit wall.

## Command line

```bash
pet start            # launch (no rebuild — keeps your permissions)
pet rebuild          # recompile, re-bundle, relaunch
pet stop             # kill it
pet probe            # print the Dock geometry it resolved
pet sprite out.png   # export a magnified PNG of the current car
pet test             # run the test suite
pet coverage         # run tests under coverage and refresh docs/coverage.svg
pet victory          # trigger any state by hand:
                     # idle launch racing boost waiting victory crash
```

Add a specific car or finer pixels to a sprite export:

```bash
.build/debug/F1ClaudePet --export-sprite out.png --car sf26 --detail 3 --zoom 4
```

## Tests

```bash
pet test
```

The suite lives inside the app module and runs via `F1ClaudePet --self-test`,
rather than as an XCTest bundle. XCTest ships with Xcode, and this project
builds with the Command Line Tools alone — an XCTest target would mean nobody
could run the tests on a machine that can perfectly well build the app.

It covers the logic that can be wrong quietly: transcript parsing, agent and
background-work status, usage arithmetic, formatting, and the car registry.
Drawing and window code is deliberately left alone — asserting on pixels is
busywork when you can see the car on your Dock.

```bash
pet coverage
```

Runs the same suite under instrumentation and rewrites `docs/coverage.svg`.
CI fails if coverage drops below the threshold, or if the badge is stale.

## Under the hood

The window sits at Dock level + 1, click-through except over the car itself, and
follows your Dock across displays — including full-screen apps and Split View.
Dock geometry comes from the Accessibility API when granted, with two fallbacks.

Hooks write one word to `~/.f1-claude-pet/state`; the app polls that file and
animates. Session titles, conversation text and context usage are read from
Claude Code's own transcripts in `~/.claude/projects/`, tail-read so a 59 MB
file costs nothing.

```
Sources/F1ClaudePet/
  AppDelegate.swift      window lifecycle, Dock following, second car
  TrackView.swift        driving physics, states, smoke, radio bubble
  ChatPanel.swift        the pit wall: conversation, replies, usage
  DockGeometry.swift     where the Dock actually is
  Cars/                  one file per car; add yours here
  Render/                pixel rasteriser, smoke, app icon
  State/                 hook channel, transcript reader, usage service
```

**Adding a car** is one file conforming to `Car` — a palette, some paths, wheel
positions, a rake value — plus a line in `CarRegistry.all`. No renderer changes.

## Known beta rough edges

- Rebuilding re-signs the app, which can drop the Accessibility grant. Re-tick it.
- The weekly histogram counts prompts from `~/.claude/history.jsonl`, which
  Claude Code prunes — early-week numbers can undercount.
- The Usage tab's parser is written against an undocumented endpoint. If it says
  "no limit data", the field names moved.
- The second car doesn't animate its own session yet; it shows its conversation.

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Formula 1, any team, Pirelli, or Anthropic. Liveries are
pixel-art impressions, drawn by hand from reference photos.
