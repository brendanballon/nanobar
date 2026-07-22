# NanoBar

A lightweight AeroSpace workspace bar for macOS — pure Swift/SwiftUI, no Electron, no shell scripts on the hot path.

**Requires macOS 15 (Sequoia) or later**

![NanoBar screenshot](docs/screenshot.webp)

---

## Features

- **AeroSpace integration** — workspace indicator with app icons and socket-based live updates
- **Liquid Glass pills** — native macOS 26 glass effect with hover/focus states; vibrancy blur fallback on macOS 15
- **Multi-monitor** — one bar per screen, automatically managed
- **Fullscreen aware** — bar hides when a fullscreen window covers the screen
- **Native performance** — ~2% CPU at idle

---

## Installation

### Homebrew (recommended)

```bash
brew install xeydev/tap/nanobar
brew services start nanobar
```

### From source

```bash
git clone https://github.com/xeydev/nanobar
cd nanobar
bash build-release.sh
```

Produces a `dist/` directory with `bin/nanobar` and `libexec/NanoBar`. Add `dist/bin` to your `PATH` or copy the contents to your preferred prefix.

For development, `./build-dev.sh` builds a debug binary and (re)starts NanoBar; log at `/tmp/nanobar-debug.log`.

Logs (service): `/tmp/nanobar.log` and `/tmp/nanobar.err`.

---

## Configuration

Config lives at `~/.config/nanobar/config.toml` and is created automatically on first launch. The file is watched — edits apply live, no restart needed.

```toml
[widgets]
left   = ["workspaces"]
center = []
right  = []
```

That's all you need to get started. Everything else is optional.

### Workspaces widget

```toml
[workspaces]
mode = "clampAndExpand"   # labelsOnly | activeIcons | clampAndExpand
```

- `labelsOnly` — workspace names only
- `activeIcons` — app icons shown on the focused workspace
- `clampAndExpand` — icons on the focused workspace, others expand on hover

### App settings

```toml
[app]
theme = "system"   # system | light | dark
```

### Bar appearance

```toml
[bar]
background   = "none"    # none | blur | color:#RRGGBBAA
minHeight    = 30
cornerRadius = 0
shadow       = false
position     = "top"     # top | left | right
margin       = 0         # gap between screen edge and bar
padding      = 8         # gap between bar edge and pill widgets
border       = false
```

`margin` and `padding` accept a scalar (all sides) or a per-side table:

```toml
margin  = { all = 6, top = 4 }
padding = { all = 8, left = 16 }
```

### Pill appearance

```toml
[pill]
style        = "liquidGlass"   # liquidGlass | blur | solid | none
height       = 30
cornerRadius = 15
border       = true            # false | true | { width = 0.75, color = "#FFFFFF47" }

[pill.liquidGlass]
# Glass effect per interaction state: "regular" | "clear" | "identity"
defaultEffect = "clear"
hoverEffect   = "regular"
toggledEffect = "regular"

[pill.liquidGlass.blur]
# Pre-macOS 26 fallback — ignored on macOS 26+ (glass handles itself).
material = "regular"   # regular | thin | ultraThin
specular = true
shadow   = true

[pill.blur]
# Standalone blur style (vibrancy, works on all macOS 15+ versions).
material = "regular"   # regular | thin | ultraThin
specular = true
shadow   = false

[pill.solid]
# Opaque pill. solidColor is an #RRGGBBAA hex string.
# solidColor = "#1C1C1ECC"
# solidShadow = false
```

---

## AeroSpace Integration

The workspaces widget listens on a Unix socket for instant updates. Add this to `~/.aerospace.toml`:

```toml
exec-on-workspace-change = ['/bin/bash', '-c',
  'printf "%s" "$AEROSPACE_FOCUSED_WORKSPACE" | nc -U /tmp/nanobar-notify.sock']
```

Without it, workspace state is only fetched at startup — the socket hook is what makes focus changes appear instantly.

---

## Uninstalling

```bash
launchctl unload ~/Library/LaunchAgents/com.user.nanobar.plist
rm ~/Library/LaunchAgents/com.user.nanobar.plist
sudo rm /usr/local/bin/nanobar
rm -rf ~/.config/nanobar   # optional — removes your config
```
