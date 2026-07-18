# LiveWall

A free macOS menu bar app that turns any video into your desktop wallpaper —
looping, muted, sitting behind your icons on every Space and every display.

No paywall, no watermark, no subscription, no license key, no account.
Everything in it is available to everyone, always.

## What it does

- **Lives in the menu bar.** No Dock icon, no clutter. Click the icon, get a
  small settings panel.
- **Renders at the actual desktop level.** Each display gets its own
  borderless, click-through window sitting right where the wallpaper picture
  normally goes — above it, but still behind your desktop icons. It follows
  you across every Space and stays invisible to Mission Control and Cmd+Tab.
- **Handles any video, any size.** `.mov`, `.mp4`, `.m4v` — a tiny 480p clip
  and a multi-gigabyte 8K file both just work, since AVFoundation streams and
  hardware-decodes them straight off disk instead of loading them into memory.
- **Loops seamlessly** with `AVQueuePlayer` + `AVPlayerLooper` — no visible
  seam or stutter at the loop point.
- **Every display is independent.** Different video, scaling mode
  (Fill / Fit / Stretch), and mute/volume per screen. Drag a video onto a
  display's card, or use the Choose… button.
- **Copes with displays coming and going.** Plug in a monitor, unplug it,
  plug it back in — its wallpaper comes back, remembered by the display's own
  hardware ID rather than its position.
- **Doesn't waste power.** Playback pauses automatically when a display is
  fully covered by something (a fullscreen app, say), when the Mac sleeps,
  and optionally whenever you're running on battery. Muted by default too.
- **Remembers everything** — assignments survive quitting the app, restarting
  the Mac, all of it.
- **Launch at Login**, using Apple's current `SMAppService` API rather than
  the deprecated one everyone copy-pastes from Stack Overflow.
- **Optional screen saver mode.** Flip a toggle and LiveWall installs a real
  screen saver module that plays your video. macOS files all third-party
  screen savers under "Other" in System Settings — that's Apple's own
  placement, not something an app can change.
- **Optional native wallpaper + lock screen tile (experimental).** A second
  toggle registers your video with macOS's own wallpaper system, so it gets
  a real, top-level "LiveWall" section in System Settings → Wallpaper and →
  Screen Saver, right next to Apple's own aerials — and picking it there also
  puts it on the lock screen. This leans on an undocumented, reverse
  engineered part of macOS, so treat it as a bonus rather than something to
  depend on. See the comments in `AerialInstaller.swift` for the full story.

## Building it

You need Xcode 16+ with a macOS 26+ SDK. No third-party dependencies, no
Swift Package Manager, no CocoaPods — just open the project and build.

```sh
open LiveWall.xcodeproj
# or from the command line:
xcodebuild -project LiveWall.xcodeproj -scheme LiveWall -configuration Release build
```

## A note on distribution

Drawing a window at the desktop level isn't something the full macOS App
Sandbox allows, so LiveWall is built **non-sandboxed** and can't go on the
Mac App Store. If you hand a built copy to someone instead of having them
build it themselves, Gatekeeper will block it on first launch — they'll need
to right-click → Open once, or you'll need to sign and notarize it with a
Developer ID certificate.

It doesn't need Screen Recording or any other special permission. Drawing
the wallpaper window is just a normal window at an unusual level — no TCC
entitlements involved.

## Things that need a human to verify

Some behavior only really shows itself with a person in front of the screen:

- [ ] Drop a `.mov` on a display card → it becomes a looping, muted wallpaper
      behind your icons
- [ ] The wallpaper survives Space switches and Mission Control
- [ ] A fullscreen app on a display pauses that display's playback; leaving
      fullscreen resumes it
- [ ] Unplug and replug an external display → its assignment comes back
- [ ] Quit and relaunch (and restart the Mac entirely) → wallpapers are
      still there
- [ ] "Pause when on battery" actually pauses on unplug, resumes on AC
- [ ] Launch at Login toggle actually registers/unregisters the login item
- [ ] Screen saver toggle: enable it, then pick "LiveWall" yourself under
      System Settings → Screen Saver → Other, and confirm it plays after
      idle. Apple's third-party screen saver host has had rough edges on
      recent macOS versions — if it shows a fallback message instead of your
      video, re-toggle it in LiveWall after (re)assigning a video

## How it's organized

```
LiveWall/
├── App/            App entry point — accessory app lifecycle, no Dock icon
├── Core/           The actual engine: windows, players, persistence, power
├── UI/             Menu bar item + the SwiftUI settings panel
└── Resources/      App icon, accent color
LiveWallSaver/       The bundled screen saver module (separate build target)
```

## Contributing

Pull requests welcome. It's a small, dependency-free codebase, so it should
be easy to poke around in Xcode and figure out where things live. If you're
touching the desktop-window-level code or the wallpaper/aerial tricks, it's
worth reading the comments in those files first — there's real reverse
engineering behind some of this and the reasoning matters.

## License

MIT — see [LICENSE](LICENSE). Free for anyone to use, modify, and ship,
including commercially.
