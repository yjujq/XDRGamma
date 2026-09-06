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

Clicking the icon opens the settings panel, and clicking it again closes it.
There is no menu behind the icon at all — the panel holds every control one
would have offered, and a second copy is only another surface to keep in sync.
Opening the app again while it is already running also brings the panel up.

## The settings panel

Everything else lives in one hand-drawn panel: teal ground, a thin rule with
the title cut into its top edge, monospace throughout. The controls are
typography rather than widgets — checkboxes are `[x]`, the intensity slider is a
run of cells between brackets, and buttons carry a hard offset shadow that the
face slides onto when pressed.

None of it uses a stock control, because an `NSButton` or `NSSlider` drags its
own material and corner radius into the picture and breaks the look on sight.
`RetroKit.swift` holds the pieces; `SettingsWindow.swift` assembles them.

The diagnostics line at the foot, `Headroom current / potential · gamma ×factor`,
updates once a second while the panel is open and shows whether the panel has
actually entered HDR mode.

Three details that are easy to get wrong with custom views: each one overrides
`mouseDown` even where it does nothing, because a view that ignores it never
receives the matching `mouseUp`; each returns true from `acceptsFirstMouse`, so
a click lands on the control rather than being swallowed as an activating click;
and the window is an `NSWindow` subclass that returns true from `canBecomeKey`,
which a borderless window otherwise refuses, along with closing on Escape.

It behaves like a menu rather than a window: it hangs under the status item,
has no close button, and clicking anywhere else dismisses it.

Clicking the icon again closes it, which is fussier than it sounds. The click
makes the panel resign key *before* it reaches the icon's action, so the panel
has already closed by then and simply calling "show" would reopen it — the icon
would look like it did nothing. The action therefore asks whether the panel was
dismissed within the last fraction of a second, not merely whether it is
visible, and treats that as the closing half of a toggle.

## Layout

| File | Role |
|---|---|
| `EDRTrigger.swift` | 1×1 window plus the Metal layer that holds HDR mode |
| `GammaTable.swift` | Table capture, scaling, drift detection |
| `GammaController.swift` | State machine: HDR ramp-up, factor, fade, hold |
| `StatusItem.swift` | Menu bar icon: boost state, opens the panel |
| `RetroKit.swift` | The terminal look: panel, buttons, `[x]` checks, cell bar |
| `SettingsWindow.swift` | Every setting, assembled from RetroKit |
| `AppDelegate.swift` | Gamma restore safety nets |
| `ThermalMonitor.swift` | Thermal throttling watch |
| `LoginItem.swift` | Launch at login via `SMAppService` |
| `Settings.swift` | `UserDefaults` storage |
| `Utils.swift` | Panel constants, model detection |

## Cost

The whole app runs at about **0.24% CPU**, and nearly all of that is the EDR
trigger — the gamma table is written only when the factor actually changes, and
the integrity poll is cheap.

Getting there was mostly one measurement. The trigger used to run its `MTKView`
at 5 fps and cost 1.75% on its own, which is essentially everything the process
spent. Dropping to 1 fps only brought that to 1.15%: the frames were never the
expense. `MTKView`'s display link ticks at the display's refresh rate whatever
`preferredFramesPerSecond` says — the property only decides which ticks draw —
so a low frame rate still pays for a 120 Hz thread.

Pausing the view and presenting from a timer instead removes the display link
altogether, and the trigger needs far fewer frames than it looks: measured on
Mac15,7, **one frame every ten seconds** held the granted headroom with no dip.
The timer runs at one second, for margin, in `.common` run loop modes so an open
menu cannot stall it.

None of this matters next to the panel. At 1000 nits the backlight dwarfs a
couple of percent of one core — if the goal is battery, the lever is whether the
boost is engaged at all, which is what **Only at Full Brightness** is for. The
CPU work matters for a different reason: a background agent should not be waking
the processor around the clock for a boost that is not switched on.

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

## HDR content, and why it has to be handled by hand

The gamma technique claims the display's entire EDR headroom for SDR content,
which is the same headroom HDR video needs for its highlights — so the two
cannot coexist, and the boost clips HDR. Turn the boost off before a film.

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

## Not done yet

- Global hotkeys and F1/F2 interception
- Pausing on battery and at low charge
- Incompatible-app monitoring

## References

- [niklasr22/BrightIntosh](https://github.com/niklasr22/BrightIntosh) — source of
  the panel constants and the overall state machine
- [waydabber/BetterDisplay wiki](https://github.com/waydabber/BetterDisplay/wiki/XDR-and-HDR-brightness-upscaling)
- [Explore HDR rendering with EDR (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10161/)
