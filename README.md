# DeskMode

**Turn an iPhone 18 into a desktop.** Plug the phone into a monitor over USB‑C, pair a keyboard
and mouse, and DeskMode puts a cursor‑driven desktop on the big screen: draggable, resizable
windows, a menu bar, a Dock, a Spotlight‑style launcher and a full tabbed browser that identifies
as Safari on a Mac. The iPhone's own screen goes dark and stays unlocked while you work.

## What it does

| Area | Details |
| --- | --- |
| External display | Uses the `UIWindowSceneSessionRoleExternalDisplayNonInteractive` scene so the monitor shows the desktop (not a mirror) at native resolution. |
| Mouse | Reads Bluetooth / USB mice through `GameController` (`GCMouse`) and draws its own cursor on the monitor. Hover, click, double/triple click, right‑click, middle‑click and scroll wheel all work. |
| Keyboard | Hardware keyboard presses are captured on the phone scene and routed to the focused window. Mac‑style shortcuts throughout (⌘T, ⌘W, ⌘L, ⌘Space, ⌘\`, ⌘[ / ⌘], ⌘F, ⌘+/−…). |
| Phone screen | Brightness goes to zero and the UI turns black; the idle timer is disabled so the phone never locks. Press and hold on the screen to wake it and show controls. |
| Trackpad fallback | With no mouse attached the iPhone's touch screen is a trackpad: drag to move, tap to click, two fingers to scroll, two‑finger tap to right‑click, tap‑then‑drag to drag. A software keyboard can also be summoned. |
| Browser | Tabs, address bar with search, back/forward/reload, find in page, zoom, desktop user agent, context menus (open in new tab, copy link, …), session restore, start page with shortcuts. Synthetic DOM events give real link clicks, form input, text selection with the mouse, hover states, `<select>` menus and iframe support. |
| Windows | Title‑bar drag, 8‑direction resize, traffic lights, double‑click to zoom, edge snapping (left / right / full), tiling shortcuts, minimize to Dock, focus cycling. |
| Apps | Browser, Notes (autosaving plain‑text editor), Tasks (checklist), Settings. |

## Requirements

* Xcode 16 or newer (the project uses Xcode 16's folder‑synchronised groups).
* iOS 17 or newer; built and tested with the iPhone 18 in mind, but any USB‑C iPhone works.
* A monitor connected over USB‑C (DisplayPort Alt Mode) or through a USB‑C → HDMI adapter.
* A Bluetooth or USB keyboard and mouse. Without a mouse, the phone screen acts as a trackpad.

## Build & run

1. Open `DeskMode.xcodeproj` in Xcode.
2. Select your team under *Signing & Capabilities* (bundle id `com.micull.DeskMode`).
3. Run on an iPhone, then connect the display. The desktop appears on the monitor and the phone
   screen dims.

If you prefer to regenerate the project, `project.yml` is an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec:

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

### Trying it without hardware

* **Simulator:** choose *I/O › External Displays › 1080p* (or 4K) in the Simulator menu. The
  desktop opens on the second window. The Mac keyboard drives the desktop via *I/O › Keyboard ›
  Connect Hardware Keyboard*, and the phone window works as the trackpad.
* **Phone preview:** on the setup screen tap *Preview the desktop on this iPhone*. Touches act
  as the cursor so you can click around in landscape.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘Space (or ⌃Space) | Launcher: open apps, search the web, open a URL |
| ⌘\` / ⌘Tab | Cycle windows |
| ⌘N | New browser window |
| ⌘T / ⇧⌘T | New tab / reopen closed tab |
| ⌘W / ⇧⌘W | Close tab / close window |
| ⌘L | Address bar |
| ⌘R | Reload |
| ⌘[ / ⌘] | Back / forward |
| ⌃Tab / ⌃⇧Tab, ⌘1…9 | Switch tabs |
| ⌘F / ⌘G | Find in page / next match |
| ⌘+ / ⌘− / ⌘0 | Zoom |
| ⌘M | Minimize |
| ⌃⌥← / ⌃⌥→ / ⌃⌥↩ | Tile left / right / fill screen |
| ⌘, | Settings |
| ⌥⌘N / ⌥⌘T | New note / new task |
| Esc | Close menus, launcher, find bar |

## Architecture

```
DeskMode/
  App/        AppDelegate (scene routing), PhoneSceneDelegate, ExternalSceneDelegate, Info.plist
  Core/       InputRouter (mouse + keyboard → events), DesktopSession (shared state, dimming),
              WindowManager (z‑order, focus, tiling), Settings, Persistence, DeskApp
  Desktop/    DesktopViewController (hit‑testing + routing), window chrome, menu bar, Dock,
              launcher, cursor, pointer‑driven controls (buttons, toggles, text fields, editor)
  Browser/    BrowserWindowContent, BrowserTab (WKWebView), WebContentView (JS bridge),
              BrowserScripts (injected JavaScript), TabStripView, StartPage
  Apps/       Notes, Tasks, Settings windows
  Phone/      SwiftUI setup / status screens, TrackpadView, SoftKeyboardBridge
```

The external display is *non‑interactive* in iOS terms: it never receives touches. DeskMode
therefore keeps its own cursor position (`InputRouter`), hit‑tests the view hierarchy itself
(`DesktopViewController.target(at:)`) and delivers `PointerEvent`s to views that adopt
`PointerTarget`. Keyboard events arrive on the phone scene (`PhoneRootViewController.pressesBegan`)
and are forwarded to the focused window's `WindowContent`.

Inside web pages the same events are replayed as real DOM `PointerEvent`/`MouseEvent`/
`KeyboardEvent`s by `BrowserScripts.bridge`, which also reports the CSS cursor under the pointer
so the desktop shows an I‑beam over text and a hand over links.

## Limitations

* iOS does not allow an app to switch the display off. DeskMode sets brightness to zero and
  shows black, which is visually equivalent and keeps the session alive.
* If a Bluetooth mouse is paired but the cursor does not move, enable *Settings › Accessibility ›
  Touch › AssistiveTouch* once so iOS exposes the mouse to apps.
* DeskMode must stay in the foreground. Switching apps hands the monitor back to iOS mirroring.
* Cross‑origin iframes cannot be scripted, so content inside them is not clickable.
* Downloads, file uploads and native `<input type="date">` pickers are not supported in the browser.
