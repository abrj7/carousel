# Carousel

A free, open-source **scrolling window manager for macOS**, in the style of PaperWM and niri.

Your windows sit side by side on one horizontal strip that runs past the edges of the screen.
Opening a window adds a column next to the one you're on. Nothing else gets squashed. Move along
the strip with ⌃⌥ + arrow keys, or hold ⌃⌥ and scroll.

- Each window is a column with its own width (25 / 33 / 50 / 66 / 75 / 100%)
- Stack windows in one column, pop them back out
- A frosted strip indicator shows where you are; click a tile to jump or drag to reorder
- Optional focus border and dimming of inactive windows
- One strip per display per Space
- Dialogs, fixed-size windows and native fullscreen are left floating
- Only needs Accessibility permission. No SIP changes.

> Status: early (v0.1). It works day to day but has rough edges. See [Roadmap](#roadmap).

## Install

Requires macOS 13+ and Xcode (or the Swift toolchain).

```bash
git clone https://github.com/abrj7/carousel.git
cd carousel
make install     # builds Carousel.app, copies it to /Applications and opens it
```

On first launch macOS asks for **Accessibility** access. Turn on Carousel in System Settings →
Privacy & Security → Accessibility, and it starts tiling within a second.

> **Rebuilding?** Without a signing certificate the app gets an ad-hoc signature, and macOS
> treats each build as a new app. After a rebuild, remove Carousel from the Accessibility list
> and add it again. Set `CODESIGN_IDENTITY="Apple Development: you@…"` to avoid this.

Quitting Carousel (menu bar → Quit, or `pkill Carousel`) pulls every off-screen window back
onto the screen.

## Shortcuts

| Keys | Action |
|---|---|
| ⌃⌥ ← / → (or H / L) | Focus left / right |
| ⌃⌥ ↑ / ↓ (or K / J) | Focus up / down inside a stack |
| ⌃⌥⌘ ← / → | First / last window |
| ⌃⌥ 1 … 9 | Jump to window N |
| ⌃⌥⇧ ← / → (or H / L) | Move column left / right |
| ⌃⌥⇧ ↑ / ↓ (or K / J) | Move window up / down inside a stack |
| ⌃⌥ R | Cycle width |
| ⌃⌥ F | Toggle full width |
| ⌃⌥ C | Centre the focused column |
| ⌃⌥ = / - | Wider / narrower |
| ⌃⌥⇧ = / - | Taller / shorter (stacks) |
| ⌃⌥ 0 | Equalize heights in a stack |
| ⌃⌥ [ / ] | Stack the focused window into the left / right column |
| ⌃⌥⇧ [ / ] | Pop the window out of its stack to the left / right |
| ⌃⌥ T | Float / unfloat the focused window |
| ⌃⌥ N | Send window to the next display |
| ⌃⌥ Q | Pause / resume tiling |
| ⌃⌥ + scroll | Scroll the strip (settles on the nearest column) |

Holding ⌃⌥ keeps the strip indicator visible so you can click it.

## Settings

From the menu bar icon: gaps (0–24 pt), centre mode (never / when the strip overflows /
always), focus border, dim inactive windows, strip indicator, animations, launch at login.

## How it works

```
Sources/
  CarouselCore/        pure layout model, no AppKit, fully unit tested
    Strip.swift        columns, stacks, widths, scrolling, snapping, parking
  Carousel/            the app
    AX.swift           Accessibility wrappers (+ private _AXUIElementGetWindow, CGS spaces)
    AppObserver.swift  per-app AXObserver: window created/destroyed/moved/focused
    WindowManager.swift  owns strips per (display, Space), reacts to events, runs commands
    Animator.swift     120 Hz ease-out, position-only per frame, size once
    Hotkeys.swift      Carbon global hotkeys + default keymap
    ScrollTap.swift    CGEventTap for ⌃⌥ + scroll
    Overlays.swift     focus border, dimming, strip indicator HUD
    StatusMenu.swift   menu bar UI
```

The strip is a list of columns. Each column has a width (a fraction of the screen) and one or
more windows. The viewport has an `offset` into the strip. Every action (focus, move, resize,
scroll) changes that model. Then `frames(in:gap:)` works out where every window should be, and
the animator moves the real windows there through the Accessibility API. A window that ends up
fully off screen is "parked" with one pixel showing at the edge, because macOS won't let a
window leave the screen entirely.

[`docs/TEARDOWN.md`](docs/TEARDOWN.md) explains the design in more detail: every feature of a
commercial scrolling WM and the macOS API behind it.

```bash
make test   # layout model tests
make run    # build the .app and launch it
```

## Roadmap

- [ ] Tabbed columns (⌃⌥⇧T)
- [ ] Pinned columns at the left/right edge
- [ ] Session restore (order, widths and stacks across restarts)
- [ ] Per-app rules (always float, fixed slot)
- [ ] Real 3/4-finger swipe via MultitouchSupport
- [ ] Rebindable shortcuts + settings window
- [ ] Focus follows mouse / mouse follows focus
- [ ] URL scheme + CLI for scripting (Raycast, Alfred)
- [ ] Drag a window onto another column to reorder

## Credits

Inspired by [PaperWM](https://github.com/paperwm/PaperWM), [niri](https://github.com/YaLTeR/niri)
and ChainYourMac. The window-parking trick comes from [AeroSpace](https://github.com/nikitabobko/AeroSpace).

MIT licensed.
