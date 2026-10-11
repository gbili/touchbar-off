# TouchBarOff

A menu bar item that turns the MacBook Pro Touch Bar off and keeps it off.

macOS has no setting for this. It matters when the Touch Bar's panel fails: the bar
flickers or shows flashing lines, and the only real fix is a hardware repair. With the
bar dark, the fault is invisible.

## Is it a hardware fault?

While the fault is visible, take a picture of what macOS is drawing to the bar:

```sh
screencapture -b ~/Desktop/touchbar.png
```

Shift-Command-6 does the same.

- **The picture is clean:** the fault sits after macOS has drawn the image, in the
  panel, its cable or the display controller. Software cannot repair that. TouchBarOff
  hides it.
- **The picture shows the glitch:** macOS is drawing it. Restart the Mac and update
  macOS before anything else.

## Install

Needs Xcode's command-line tools (`xcode-select --install`). No `sudo`.

```sh
git clone https://github.com/gbili/touchbar-off.git
cd touchbar-off
./install.sh
```

This builds the app into `~/Applications/TouchBarOff.app` and adds a launch agent
(`~/Library/LaunchAgents/io.github.gbili.TouchBarOff.plist`) that starts it at login.

## Use

A crossed-out lightbulb appears in the menu bar.

- **Click:** Touch Bar off.
- **Right-click:** a menu with *Turn Touch Bar On* and *Quit*.
- **By itself:** whenever something lights the bar (login, wake from sleep), the app
  darkens it again within milliseconds. *Turn Touch Bar On* holds until the next click
  on the icon, wake or login.

From a terminal:

```sh
~/Applications/TouchBarOff.app/Contents/MacOS/TouchBarOff off
~/Applications/TouchBarOff.app/Contents/MacOS/TouchBarOff on
```

While the menu bar item is running and keeping the bar off, a terminal `on` is undone
at once. Use the menu.

## Uninstall

```sh
./uninstall.sh
```

Stops the app, lights the Touch Bar again and removes the app and its launch agent.

## How it works

Two private frameworks that macOS itself uses:

- **`DFRBrightness.framework`** has a class `DFRBrightnessClient` with `turnOff` and
  `turnOn`. `TouchBarServer` uses the same class for its idle dimming. A bar turned off
  this way stays off while you type: the system's idle dimming steps keep changing
  underneath without lighting the panel.
- **`DFRFoundation.framework`** exports `DFRGetStatus()`, a bit mask that read `0x1`
  with the bar lit and `0x5` with it dark, so bit `0x4` means dark. It also exports
  `DFRRegisterStatusChangeCallback(block)`, which calls the block with the new status
  on every change. The app uses it to darken the bar the moment something lights it.

## Tested on, and limits

- **One machine:** a 13-inch M1 MacBook Pro (MacBookPro17,1) on macOS 15.5. Intel Touch
  Bar models (2016 to 2020) and other macOS versions are untested. If you try one, open
  an issue with the model, the macOS version and what happened.
- **Private frameworks:** a macOS update can break this, and it can never be in the Mac
  App Store. If something it needs is missing, the app stops with an error instead of
  pretending to work; `install.sh` reports that.
- **Only after login:** the bar is lit at the login screen, and may flash briefly at
  wake before the app reacts.
- **No Touch Bar keys while dark:** brightness, volume and media controls are in Control
  Centre. On models whose Escape key is on the Touch Bar, it is untested whether a dark
  bar still registers touches; Caps Lock can be remapped to Escape under System
  Settings, Keyboard, Keyboard Shortcuts, Modifier Keys.
- **Not a medical safeguard:** if a flickering bar is a health risk for you, do not rely
  on this alone. Cover the bar or have it repaired.

## Licence

MIT. See [LICENSE](LICENSE).
