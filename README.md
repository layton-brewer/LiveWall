# LiveWall

Puts a video on your desktop as wallpaper. That's it. No subscription, no
account, no watermark, no "pro" version hiding behind a paywall. Runs on macOS 14 Sonoma and newer.

### [Download the latest release →](https://github.com/layton-brewer/LiveWall/releases/latest)

![LiveWall setting a video as the desktop wallpaper](demo.gif)

## What it does

Drop a video on a display in the app and it becomes your wallpaper: looping,
muted, sitting right behind your desktop icons on every Space. Works with
.mov, .mp4, and .m4v files of pretty much any size, since the video streams
and decodes straight off disk instead of getting loaded into memory. An 8K
file plays exactly the same as a small one.

Lives in the menu bar, no Dock icon. Every display gets its own video, its
own scaling mode (fill, fit, or stretch), and its own volume. You can also
trim the loop: pick a start and end point and it plays just that slice,
without touching the file itself. Unplug a monitor and plug it back in later
and its wallpaper comes back on its own. Everything's saved, so quitting the
app or restarting the Mac doesn't lose anything.

It also knows when to stop working. Playback pauses when a fullscreen app
covers a display, when the Mac sleeps, when someone fast-user-switches away,
and optionally on battery or in Low Power Mode. There's a Launch at Login
toggle too, built on Apple's current API instead of the deprecated one half
the tutorials online still tell you to use. And it can check GitHub for new
versions quietly, once a day, only ever speaking up when there's actually
something new.

Two more things, both optional:

- A real screen saver mode, if you'd rather the video kick in after being
  idle. macOS files all third-party screen savers under "Other" in System
  Settings. That's Apple's doing, not something an app can change.
- A toggle that registers your video with macOS's own wallpaper system and
  applies it in one shot. It gets a real "LiveWall" section in System
  Settings instead of being buried under Other, becomes the active wallpaper
  and screen saver immediately, and shows up on your lock screen. This leans
  on undocumented behavior found by poking around macOS's own wallpaper
  files, so treat it as a nice bonus rather than something guaranteed to
  keep working forever, and it needs a recent macOS, so the toggle only
  appears where it can actually work. The comments in `AerialInstaller.swift`
  have the full story if you're curious.

## Getting it

Easiest way is the [DMG from the latest release](https://github.com/layton-brewer/LiveWall/releases/latest).
Drag LiveWall into Applications and you're done.

It isn't signed with a paid Apple Developer certificate, so Gatekeeper will
block it the first time you try to open it. Right-click the app and choose
Open instead of double-clicking. You only have to do that once.

## Building it yourself

Runs on macOS 14 Sonoma or newer. Building needs Xcode with a macOS 26+ SDK
(the panel uses the new glass material where available, with a normal blur
fallback on older systems). No dependencies to install and nothing to fetch,
just open the project and build.

```sh
open LiveWall.xcodeproj
```

or from the command line:

```sh
xcodebuild -project LiveWall.xcodeproj -scheme LiveWall -configuration Release build
```

## Why it's not sandboxed

Drawing a window at the actual desktop level isn't something Apple allows
inside the App Sandbox, so this can't go on the Mac App Store. On the plus
side, it also means building it yourself doesn't ask for any special
permission: no Screen Recording, no TCC prompts. It's just a regular
window sitting at an unusual window level.


## Code layout

```
LiveWall/
├── App/            entry point, sets up the no-Dock-icon app lifecycle
├── Core/           the actual engine: windows, players, persistence, power handling
├── UI/             menu bar item + the settings panel
└── Resources/      icon, accent color
LiveWallSaver/       the screen saver module, built as its own target
```

## Contributing

PRs welcome. It's a small codebase with zero dependencies, so it's easy to
poke around in Xcode. 

## License

MIT. See [LICENSE](LICENSE). Use it, fork it, sell it, whatever.
