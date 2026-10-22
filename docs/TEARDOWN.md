# Teardown: how a scrolling window manager works on macOS

Carousel started as an attempt to rebuild [ChainYourMac](https://chainyourmac.com) (a paid
scrolling window manager) as a free, open-source app. These notes cover what that product does
according to its public site, and which macOS APIs you need to build each piece.

## The idea

A normal tiling WM (yabai, AeroSpace, Amethyst) divides the screen. Open a fifth window and the
other four shrink. A **scrolling** WM (PaperWM and niri on Linux) puts every window on one
horizontal strip that extends past the edges of the screen. Each window is a column with its own
width, and opening a new one inserts a column without resizing the others. The screen becomes a
viewport you slide along the strip with the keyboard or the trackpad.

```
            ┌──────── screen (viewport) ────────┐
 ┌─────┐ ┌──┼───────┐ ┌───────────┐ ┌──────────┼──┐ ┌──────┐
 │  A  │ │  │  B    │ │     C     │ │    D     │  │ │  E   │
 └─────┘ └──┼───────┘ └───────────┘ └──────────┼──┘ └──────┘
            └───────────────────────────────────┘
   parked      partly        fully visible        parked
   at edge     visible                           at edge
```

## Feature list (from the public site) and how to build each one

| Feature | What it does | How it's done on macOS |
|---|---|---|
| Strip layout | Every window is a column; new windows open next to the focused one | Accessibility API: `AXUIElementSetAttributeValue(window, kAXPosition/kAXSize)`. The layout is pure math over a list of columns ([`Strip.swift`](../Sources/CarouselCore/Strip.swift)). |
| Off-screen windows | Columns outside the viewport | macOS won't let a window go fully off screen, so it's **parked** with 1px visible at the edge (the AeroSpace trick). When another display sits on that side, the window also drops below the screen so it doesn't show up there. |
| Focus left/right, move, jump 1–9 | Keyboard navigation | Carbon `RegisterEventHotKey`. It needs no permission and swallows the keystroke. Focus is `kAXRaiseAction` + `kAXFrontmostAttribute` + `NSRunningApplication.activate`. |
| Cycle width / full width / centre | Preset widths 25/33/50/66/75%, toggle 100%, centre the column | Column width is a fraction of the viewport. Centre = set viewport offset so the column's midpoint is at the screen's midpoint. |
| Stacks & pop out | Several windows share one column, split vertically | Column holds `[window]` plus height weights. |
| Tabbed columns | Stack shown as tabs, each window full height | Not built yet. Needs a tab-bar overlay window and hiding the non-active tabs (park them). |
| Pinned columns | Window stays at the left or right edge while the strip scrolls | Not built yet. Exclude the column from the offset and shrink the viewport. |
| Strip indicator | Frosted HUD with each column's app icon; click to jump, drag to reorder | `NSPanel` + `NSVisualEffectView(.hudWindow)` at `.statusBar` level, nonactivating so clicking it doesn't steal focus. |
| Trackpad swipe | 3/4-finger swipe moves the strip and settles on the nearest column | A true 3/4-finger swipe needs the private `MultitouchSupport.framework`. Carousel uses a `CGEventTap` on scroll events while ⌃⌥ is held, which also works with mice. It snaps 180 ms after the last event. |
| Focus border / dim inactive | Outline around the focused window, darken others | Click-through borderless `NSPanel`s at `.floating` level placed over window frames. Tiled windows never overlap, so this is enough. |
| Centre modes | never / when overflowing / always | `Strip.scrollToFocused(mode:)` |
| Multi-monitor & Spaces | Each display has its own strip, per Space | Strips are keyed by `(displayID, spaceID)`. The space ID comes from the private `CGSManagedDisplayGetCurrentSpace`. AX only lists windows on the current Space, so a window missing from AX is only dropped if `CGWindowListCopyWindowInfo(.optionAll)` says it's gone. |
| Smart floating | Dialogs, Quick Look, fixed-size windows (Calculator) float | Only tile `AXStandardWindow` subroles whose position and size are settable and whose zoom button is enabled. |
| Native fullscreen | Left alone | Skip windows with `AXFullScreen == true`. |
| No focus stealing | Background windows don't scroll the strip | New windows are inserted without moving focus. Only a real focus change (AX `FocusedWindowChanged`) scrolls. |
| Drag to resize | Manual resize sticks | `kAXWindowResizedNotification`: when we didn't cause it, the new width becomes the column's fraction. Manual moves snap back once the drag stops. |
| Session restore | Order and widths survive restarts | Not built yet. Persist strips keyed by app bundle ID plus window title. Window IDs change on every launch. |
| Per-app rules | Always float X, fixed slot for Y | Not built yet. |
| Focus follows mouse | Optional | Not built yet. Needs a mouse-moved event tap and a hover delay. |
| Automation | `chainyourmac://` URL scheme, CLI, Raycast | Not built yet. A URL scheme plus a CLI that talks to the app through a Unix socket or distributed notifications. |
| Engine | Rust process + SwiftUI shell, vsync-locked springs | Carousel is Swift only: one process, a 120 Hz timer, and ease-out. AX writes go across processes and cost about 1 ms each, so size is set once and only position is animated. `AXEnhancedUserInterface` is switched off during moves, otherwise Chrome/Electron animate AX moves themselves. |
| Permissions | Accessibility only, no SIP changes | Same here. |

## Things that make this hard

- **AX is slow and synchronous.** Every get/set is an IPC round trip into the target app. A
  hung app hangs you, so set `AXUIElementSetMessagingTimeout`.
- **Apps fight back.** Minimum window sizes, apps that animate their own frame changes, and
  apps that never post window-created notifications. Carousel reconciles every 3 s as a safety net.
- **Spaces have no public API.** Every WM that cares about Spaces uses private CGS/SkyLight calls.
- **Signing.** TCC ties the Accessibility grant to the code signature. An unsigned or ad-hoc
  build loses permission on every rebuild.

## Prior art worth reading

- [PaperWM](https://github.com/paperwm/PaperWM) (GNOME) and [PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon) (Hammerspoon, macOS)
- [niri](https://github.com/YaLTeR/niri), a scrolling Wayland compositor
- [AeroSpace](https://github.com/nikitabobko/AeroSpace), for the window-hiding trick and AX handling
- [Rectangle](https://github.com/rxhanson/Rectangle), for the AX frame-setting quirks
