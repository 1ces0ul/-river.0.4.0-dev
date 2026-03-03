# Rijan Window Manager – A Complete Beginner's Guide & Customization Tutorial

> **What is Rijan?** Rijan is a tiling window manager written in Janet, designed to run on top of the River Wayland compositor. It offers a clean, scriptable, and runtime‑modifiable approach to window management. This guide covers both the basics and the advanced modifications made in this fork.

> **🇨🇳 中文版：[Rijan 魔改详解](https://1ces0ul.github.io/linux-guides/rijan-fork-guide.html)**

## Table of Contents

- [Introduction: What is Rijan?](#introduction-what-is-rijan)
- [Overview of Modified Rijan Features](#overview-of-modified-rijan-features)
- [Source Code Walkthrough](#source-code-walkthrough)
- [Getting Started](#getting-started)
- [Daily Usage & Keybindings](#daily-usage--keybindings)
- [Advanced: REPL Live Debugging](#advanced-repl-live-debugging)
- [Deep Dive: Modification Details](#deep-dive-modification-details)
- [Troubleshooting](#troubleshooting)
- [Links](#links)

---

## Introduction: What is Rijan?

**River** is a Wayland compositor – it handles low‑level display, input, and protocol tasks. **Rijan** is the window manager that sits on top of River, deciding how windows are arranged, focused, and managed.

The separation of compositor and window manager is a powerful design choice in the Wayland world. While most Wayland compositors (like Sway or Hyprland) have built‑in window management, River + Rijan let you rewrite the entire window‑management logic in a scripting language (Janet) without touching C or Zig. This makes Rijan highly programmable and hot‑reloadable.

### Why This Fork?

The original Rijan (by Isaac Freund) is an elegant, minimal window manager (~650 lines of Janet code). It works perfectly for a basic tiling setup, but for daily use it lacked several practical features. This fork adds three layout engines, robust child‑window handling, keyboard‑driven floating operations, better focus management, and many other improvements – all while staying true to the original clean architecture.

---

## Overview of Modified Rijan Features

| Area | Original Rijan | This Fork |
|------|----------------|-----------|
| **Layouts** | Single master‑stack (left) | 3 layouts: master‑stack (4 directions), scroller, grid; per‑output switching |
| **Size Constraints** | None | Respects window min/max hints; centers and clips overflow |
| **Child/Popup Windows** | Simple parent‑based floating | Handles XWayland client‑leader, logical‑parent matching, smart centering |
| **Focus System** | Monolithic `seat/manage` | Split into 6 focused sub‑functions; focus‑return‑to‑parent after child closes |
| **Sticky Windows** | Not supported | Toggle sticky (visible on all tags) |
| **Floating Operations** | Mouse only | Keyboard move/resize/snap with edge collision |
| **Window Swapping** | None | Swap focused window with next/prev tiled window |
| **Multi‑Monitor** | One‑way `focus‑output` | Bidirectional focus/send‑to‑output |
| **Nmaster** | Fixed at 1 | Configurable and dynamically adjustable |
| **Error Tolerance** | None | `protect` wraps core loops; single‑window errors won’t break the whole WM |
| **Background Management** | Single‑pixel‑buffer | Removed (use external tools like `swww` for animated wallpapers) |
| **Code Size** | ~650 lines | ~1100 lines |

---

## Source Code Walkthrough

This fork is based on the original Rijan source from **Feb 5, 2026**. Two main source files are provided:

- **`rijan.janet.patched` (latest)** – The main window‑manager file. It contains the upgraded window‑drawing logic and adds the `grid` and `scroller` layouts.
- **`rijan.janet.ref` (reference)** – An earlier version that optimizes XWayland window‑drawing logic. Kept for reference.

Both files have the background‑color code removed, making it easy to use tools like `swww` for animated wallpapers.

**`init.janet`** is the configuration file that works with the latest `rijan.janet.patched`. It launches your status bar (`waybar`), notification daemon (`dunst`), input method (`fcitx5`), wallpaper (`swww`), and sets up all keybindings.

---

## Getting Started

### 1. Install Janet and Spork

```bash
# Install Janet (check your distribution’s package manager)
# For Arch Linux:
sudo pacman -S janet

# Install the Spork library (needed for the REPL server)
jpm install spork
```

### 2. Get the Source and Install

```bash
git clone https://github.com/1ces0ul/config-river.0.4.0-dev.git
cd config-river.0.4.0-dev/rijanpkg
makepkg -fsi
```

This builds and installs the Rijan package. The PKGBUILD handles placing files in the correct locations.

### 3. Configure `init.janet`

The `init.janet` file is responsible for starting your desktop environment. Open it and adjust the paths to match your system:

- **`waybar-conf`**, **`waybar-css`** – Point to your Waybar config and style files.
- **`wallpaper`** – Path to your wallpaper (supports GIF for animated backgrounds via `swww`).
- **`dunst-conf`** – Path to your Dunst configuration.

The file also contains the keybinding definitions. You can modify them here.

### 4. Launch River + Rijan

From a TTY (or a display‑manager session that supports Wayland), run:

```bash
export XDG_CURRENT_DESKTOP=river
exec river
```

River will automatically load Rijan from `~/.config/rijan/` (or wherever you placed the files).

**Tip:** If you see a black screen after starting, check the **Troubleshooting** section below.

---

## Daily Usage & Keybindings

The default modifier key is **`Mod4`** (usually the Windows key).

| Keybinding | Action |
|------------|--------|
| `Mod4 + t` | Open terminal (`kitty`) |
| `Mod4 + b` | Open browser (`chromium`) |
| `Mod4 + r` | Launch application launcher (`rofi`) |
| `Mod4 + q` | Close focused window |
| `Mod4 + space` | Zoom (swap focused window with master) |
| `Mod4 + p` / `Mod4 + n` | Focus previous / next window |
| `Mod4 + j` / `Mod4 + k` | Focus next / previous output (monitor) |
| `Mod4 + f` | Toggle fullscreen |
| `Mod4 + Alt + f` | Toggle floating |
| `Mod4 + Shift + r` | Retile (reset all user‑floated windows) |
| `Mod4 + 0` | Show all tags (workspaces) |
| `Mod4 + 1` … `Mod4 + 9` | Switch to tag 1‑9 |
| `Mod4 + Alt + 1` … `Mod4 + Alt + 9` | Move window to tag 1‑9 |
| `Mod4 + Alt + Shift + 1` … `9` | Toggle tag 1‑9 on focused output |

**Layout switching** (per output):

- `Mod4 + Alt + t` → tile (master‑stack)
- `Mod4 + Alt + s` → scroller
- `Mod4 + Alt + g` → grid
- `Mod4 + Alt + Tab` → switch to previous layout

**Master‑stack direction** (when in tile layout):

- `Mod4 + Alt + h` → left
- `Mod4 + Alt + l` → right
- `Mod4 + Alt + k` → top
- `Mod4 + Alt + j` → bottom

**Floating‑window keyboard controls**:

- Move: `Mod4 + Ctrl + Shift + h/j/k/l`
- Resize: `Mod4 + Alt + Shift + h/j/k/l`
- Snap to edge: `Mod4 + Alt + Ctrl + h/j/k/l`

**Mouse bindings**:

- `Mod4 + left‑click` → drag window
- `Mod4 + right‑click` → resize window

---

## Advanced: REPL Live Debugging

One of Rijan’s killer features is the built‑in REPL (Read‑Eval‑Print Loop). It lets you connect to the running window manager, inspect its state, and even modify behavior on the fly.

### Connect to the REPL

Make sure Rijan is running, then in a terminal:

```bash
janet -e "(import spork/netrepl) (netrepl/client :unix \"$XDG_RUNTIME_DIR/rijan-$WAYLAND_DISPLAY\")"
```

You’ll get a Janet prompt. Try evaluating some expressions:

```janet
# Print the current window list
(print (wm :windows))

# Print the layout of each output
(each output (wm :outputs) (print (output :layout)))

# Reload the configuration (after editing init.janet)
(load "init.janet")
```

### Exiting the REPL

- **`Ctrl+D`** – exits the REPL client, leaves Rijan running.
- **`(quit)`** – exits the entire Rijan process (and returns you to River).

---

## Deep Dive: Modification Details

*(This section is a condensed version of the full Chinese tutorial. For a complete walkthrough, see the [Chinese version](#chinese-version) below.)*

### Layout Engines

- **Master‑Stack** – The classic dwm‑style layout. Master area can be placed left, right, top, or bottom. Number of master windows (`nmaster`) and master ratio are adjustable.
- **Scroller** – Inspired by PaperWM/niri. The focused window stays centered; neighboring windows extend to the sides. Windows that would go off‑screen are hidden.
- **Grid** – Automatically arranges windows in a grid, centering the last row.

### Window Decoration (Border Fix)

**Problem:** All windows were appearing without any server-side rendered (SSD) borders.
**Cause:** The `decoration_hint` values (e.g., `0, 1, 2, 3`) received from the `river_layout_manager_v1` protocol are automatically converted into Janet `keywords` (e.g., `:only-supports-csd`, `:prefers-csd`, `:prefers-ssd`, `:no-preference`) by the Wayland binding layer. However, Rijan’s `window/manage` and `window/render` functions were incorrectly comparing these `keyword` hints against `integers`. Since a keyword can never equal an integer, the border-drawing logic failed, preventing any borders from being drawn.
**Fix:** The code was updated to compare `decoration-hint` values against their corresponding Janet `keywords` instead of `integers`. For example, `(= hint 0)` was changed to `(= hint :only-supports-csd)`. The default fallback hint was also changed from `3` to `:no-preference`.

**Decoration Hint Values (`river_layout_manager_v1`):**

| Value | Meaning | Rijan Keyword | Typical Windows |
|:------|:--------|:--------------|:----------------|
| `0` | `only_supports_csd` | `:only-supports-csd` | Telegram, Chrome, X11 apps without MOTIF |
| `1` | `prefers_csd` | `:prefers-csd` | WeChat (MOTIF `no_border`) |
| `2` | `prefers_ssd` | `:prefers-ssd` | GTK4 apps, X11 apps requesting decoration |
| `3` | `no_preference` | `:no-preference` | XDG toplevel only |

**Border Drawing Decision:**

| Window Type | Border? | Decoration Mode |
|:------------|:--------|:----------------|
| Child/Transient (`managed-as-child`) | ✗ No | None |
| Independent toplevel + focused (hint 2/3) | ✓ Yes (focused color) | `use-ssd` |
| Independent toplevel + unfocused (hint 2/3) | ✓ Yes (normal color) | `use-ssd` |
| CSD window (hint 0/1) | ✗ No | `use-csd` |
| Fullscreen | ✓ Yes* | `use-ssd` |

\*Protocol hides borders when fullscreen.

### Child‑Window Handling

XWayland popups (e.g., file dialogs, login windows) are tricky because of `WM_TRANSIENT_FOR` and client‑leader semantics. This fork adds:

- **`parent‑event‑received` flag** – distinguishes “no parent event” from “parent is nil (client‑leader)”.
- **Logical‑parent matching** – when a real parent isn’t available, match by `app‑id` to guess the owner window.
- **Smart centering** – child windows are centered over their parent’s content area (not the whole output).
- **Focus‑return‑to‑parent** – when a child closes, focus goes back to its parent (if still alive).

### Size Constraints (`clamp‑to‑hints`)

Some applications (terminals, image viewers) have fixed or bounded size hints. The layout now respects `min‑width`, `max‑width`, `min‑height`, `max‑height`. Windows are centered in their allocated layout box, and any overflow is clipped.

### Error Tolerance

The core `wm/manage` and `wm/render` loops are wrapped with Janet’s `protect`. If a single window’s event handler throws an error (common with half‑initialized XWayland windows), the error is logged but the manage cycle continues. Your keybindings stay alive.

### Background Removal

The original Rijan used `single‑pixel‑buffer` to draw a solid background. That code has been removed, so you can use external wallpaper tools (`swww`, `swaybg`, etc.) without interference.

---

## Troubleshooting

### Black Screen / River Doesn’t Start

- Check that Wayland is available: `echo $WAYLAND_DISPLAY`
- Verify `XDG_RUNTIME_DIR` is set and writable.
- Look at logs: `journalctl --user -b -e | grep -i "river\|rijan\|drm"`
- If you suspect a DRM issue, try switching to a different VT (`Ctrl+Alt+F2`) and check kernel logs: `dmesg | tail -20`

### Keybindings Don’t Work

- Ensure Rijan loaded correctly. Check `journalctl --user -b -e | grep rijan`.
- Verify your `init.janet` is in the right place (`~/.config/rijan/`).
- Make sure the `Mod4` key is recognized (try `xev` or `wev` to see key events).

### Applications Fail to Launch from `init.janet`

- The `init.janet` script runs as a background shell. Check its output: `journalctl --user -b -e | grep -A2 -B2 "swww\|waybar\|dunst"`
- Ensure the programs are installed and in your `$PATH`.
- The script uses `pgrep -x … || … &` to avoid duplicates, but if a process dies immediately, you might need to debug its own logs.

### REPL Connection Fails

- Confirm Rijan is running (`ps aux | grep rijan`).
- The socket path is `$XDG_RUNTIME_DIR/rijan-$WAYLAND_DISPLAY`. Make both variables are set in the shell where you run the REPL client.

---

## Links

- [River compositor](https://codeberg.org/river/river)
- [Original Rijan](https://codeberg.org/ifreund/rijan)
- [This fork](https://github.com/1ces0ul/config-river.0.4.0-dev)
- [Janet language](https://janet-lang.org/)

*Happy tiling!*