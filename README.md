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

## Where the boost appears

By default the display is left completely stock until the brightness slider
reaches the top, and only then does the extra range appear — so the boost
*extends* the slider rather than rescaling it. Measured on Mac15,7:

| Slider | SDR white as a fraction of rated | Gamma |
|---|---|---|
| 95% | 0.865 | ×1.0000 — stock |
| 97% | 0.916 | ×1.0000 — stock |
| **99%** | 0.971 | **×1.6667 — boost** |
| 100% | 1.000 | ×1.6667 — boost |

Slider position is read from headroom rather than from any brightness API:
headroom is peak ÷ current SDR white and `referenceEdr` is peak ÷ rated SDR
white, so dividing one by the other gives current white as a fraction of the
panel's rating, exactly 1.0 at the top.

It engages at 0.97 and lets go below 0.90 — coming back down the boost holds
through 98% and 97% and releases at 96%. That gap is deliberate: with a single
threshold, a rounding wobble would flip the boost on and off. Crossing it fades
over 240 ms rather than jumping, which would read as a flash.

Turn **Only at Full Brightness** off in the menu for the older behaviour, where
the boost blends in gradually across the whole slider: the factor follows
current headroom, so the lower the slider sits the less boost is applied, and
the full `bonusGamma` arrives only at the top.

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
| `Hotkey.swift` | System-wide shortcut for toggling the boost |
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

## The shortcut, and why it exists

**⌃⌥⌘B** toggles the boost from anywhere. Turn it off before an HDR film, back
on afterwards, without going to the menu bar.

This is deliberately a manual switch rather than automatic detection. The gamma
technique claims the display's entire EDR headroom for SDR content, which is the
same headroom HDR video needs for its highlights — so the two cannot coexist,
and the boost clips HDR.

Handing the headroom back automatically is not possible. macOS reports one
headroom value for the whole display, not per app; there is no arbitration
between apps and no signal that anything else wants the range. SkyLight has
promising-looking constants (`SLSBrightnessNotificationRequestEDR`,
`SLSBrightnessRequestEDRHeadroom`) but nothing is delivered on the Darwin,
distributed or local notification centres — the traffic stays inside SkyLight.
Worse, the EDR trigger switches the whole screen into EDR mode, so other apps'
HDR content is already being presented extended while our gamma table crushes
it, and the headroom reading looks identical either way.

BetterDisplay, which supports every method there is, also leaves this manual.

The combination is fixed. If another app already owns it, **Shortcut ⌃⌥⌘B** in
the menu stays unchecked and says so.

## Not done yet

- F1/F2 brightness key interception
- Pausing on battery and at low charge
- Incompatible-app monitoring

## References

- [niklasr22/BrightIntosh](https://github.com/niklasr22/BrightIntosh) — source of
  the panel constants and the overall state machine
- [waydabber/BetterDisplay wiki](https://github.com/waydabber/BetterDisplay/wiki/XDR-and-HDR-brightness-upscaling)
- [Explore HDR rendering with EDR (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10161/)
