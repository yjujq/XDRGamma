# XDRGamma

A macOS menu bar app that lifts the SDR brightness limit of the built-in
Liquid Retina XDR panel using the gamma technique. Public APIs only.

## How it works

Two parts:

1. **EDR trigger.** A 1×1 pixel window at the top edge of the screen backed by
   a `CAMetalLayer` with `wantsExtendedDynamicRangeContent = true`, an
   `rgba16Float` format, an extended-linear color space and a clear color of
   1.6. A value above 1.0 tells the system there is HDR content on screen, and
   the mini-LED panel responds by raising its backlight ceiling. The window
   itself brightens nothing.

2. **Gamma table.** Once headroom has actually grown, the transfer table
   captured beforehand is multiplied by a factor and pushed back with
   `CGSetDisplayTransferByTable`. Values above 1.0 reach into that headroom —
   which is what gives SDR content its extra brightness.

The factor is derived from current headroom: the higher it is, the lower the
system brightness slider sits and the less boost is needed. At the top of the
slider the full `bonusGamma` is handed over.

## Gamma technique: trade-offs

| | |
|---|---|
| Invisible to screenshots and screen recording | Apple Silicon only |
| No full-screen overlay | HDR video clips at the SDR maximum |
| Cheap on CPU | The system resets the table; needs an integrity poll |

The alternative is a multiply overlay
(`CALayer.compositingFilter = "multiply"`): it works on Intel too and does not
clip HDR, but it shows up in screenshots.

## Build and run

```bash
./make-app.sh          # builds XDRGamma.app alongside
open XDRGamma.app
```

Or without the bundle:

```bash
swift build -c release
.build/release/XDRGamma
```

A sun icon appears in the menu bar. The boost is **off** by default.

The menu holds the toggle, an intensity slider and a diagnostics line,
`Headroom current / potential · gamma ×factor`, which shows whether the panel
has actually entered HDR mode.

## Layout

| File | Role |
|---|---|
| `EDRTrigger.swift` | 1×1 window plus the Metal layer that holds HDR mode |
| `GammaTable.swift` | Table capture, scaling, drift detection |
| `GammaController.swift` | State machine: HDR ramp-up, factor, fade, hold |
| `StatusMenu.swift` | Menu bar UI |
| `AppDelegate.swift` | Gamma restore safety nets |
| `ThermalMonitor.swift` | Thermal throttling watch |
| `LoginItem.swift` | Launch at login via `SMAppService` |
| `Settings.swift` | `UserDefaults` storage |
| `Utils.swift` | Panel constants, model detection |

## Gamma safety

A modified gamma table **outlives the process**. If the app dies without
restoring it, the screen stays blown out until reboot. Hence three nets:
`applicationWillTerminate`, handlers for `SIGINT`/`SIGTERM`/`SIGHUP`, and
`atexit` — all calling `CGDisplayRestoreColorSyncSettings()`.

To reset by hand if something goes wrong:

```bash
swift -e 'import CoreGraphics; CGDisplayRestoreColorSyncSettings()'
```

## Pausing on overheat

A raised backlight ceiling heats the panel. Once the system reports
throttling there is no point adding heat: macOS will cut brightness anyway,
and it will do so abruptly and without coming back.

`ThermalMonitor` listens to `ProcessInfo.thermalStateDidChangeNotification`.
The threshold is `.serious` and `.critical`; `.fair` is ignored as ordinary
heat under load.

User intent (`isUserEnabled`) is kept separate from what is actually running
(`isActive`). While throttling, the boost is dropped along with the EDR
trigger — otherwise the panel would stay in HDR mode and keep heating — and it
returns on its own once things cool down. The menu bar shows this: the icon
becomes a thermometer and diagnostics read `Paused: hot`.

Turn it off with **Pause When Overheating**.

## Launch at login

**Launch at Login** uses `SMAppService.mainApp`. It requires running from the
`.app` bundle: a bare binary from `.build/release` reports `.notFound` and the
menu item stays disabled.

The boost state is stored in `UserDefaults` and restored on launch, so after
logging in the app comes back exactly as it was.

If registration fails, move `XDRGamma.app` into `/Applications`: macOS is
warier about login items living in arbitrary folders, especially ad-hoc
signed ones. If launch at login was turned off by hand the status becomes
`.requiresApproval`, and the app offers to open the relevant System Settings
pane.

## Hiding the menu bar icon

**Hide Menu Bar Icon** removes the icon via `NSStatusItem.isVisible`. The
boost keeps running and the setting persists across launches.

Since the icon is the only control surface, hiding it without a way back is
not an option. The way back is `applicationShouldHandleReopen`: launching the
already-running app again (double-click `XDRGamma.app`, or Spotlight) restores
the icon and clears the setting. A dialog explains this before hiding.

The Dock icon is hidden separately and always, via `LSUIElement` in
`Info.plist` and `setActivationPolicy(.accessory)`.

## Not done yet

- Global hotkeys and F1/F2 interception
- Pausing on battery and at low charge
- Incompatible-app monitoring

## References

- [niklasr22/BrightIntosh](https://github.com/niklasr22/BrightIntosh) — source of
  the panel constants and the overall state machine
- [waydabber/BetterDisplay wiki](https://github.com/waydabber/BetterDisplay/wiki/XDR-and-HDR-brightness-upscaling)
- [Explore HDR rendering with EDR (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10161/)
