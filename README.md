# LiveWall

Puts a video on your desktop as wallpaper. That's it — no subscription, no
account, no watermark, no "pro" version hiding behind a paywall. Download it
and it works.

### [Download the latest release →](https://github.com/layton-brewer/LiveWall/releases/latest)

## What it does

Drop a video on a display in the app and it becomes your wallpaper — looping,
muted, sitting right behind your desktop icons on every Space. Works with
.mov, .mp4, and .m4v files of pretty much any size, since the video streams
and decodes straight off disk instead of getting loaded into memory. An 8K
file plays exactly the same as a small one.

Lives in the menu bar, no Dock icon. Every display gets its own video, its
own scaling mode (fill, fit, or stretch), and its own volume. Unplug a
monitor and plug it back in later and its wallpaper comes back on its own.
Everything's saved, so quitting the app or restarting the Mac doesn't lose
anything.

It also knows when to stop working — playback pauses when a fullscreen app
covers a display, when the Mac sleeps, and optionally whenever you're
running on battery. There's a Launch at Login toggle too, built on Apple's
current API instead of the deprecated one half the tutorials online still
tell you to use.

Two more things, both optional:

- A real screen saver mode, if you'd rather the video kick in after being
  idle. macOS files all third-party screen savers under "Other" in System
  Settings — that's Apple's doing, not something an app can change.
- A toggle that registers your video with macOS's own wallpaper system,
  which gets it a real "LiveWall" section in System Settings instead of
  being buried under Other, and even puts it on your lock screen. This
  leans on undocumented behavior found by poking around macOS's own
  wallpaper files, so treat it as a nice bonus rather than something
  guaranteed to keep working forever. The comments in `AerialInstaller.swift`
  have the full story if you're curious.

## Getting it

Easiest way is the [DMG from the latest release](https://github.com/layton-brewer/LiveWall/releases/latest)
— drag LiveWall into Applications and you're done.

It isn't signed with a paid Apple Developer certificate, so Gatekeeper will
block it the first time you try to open it. Right-click the app and choose
Open instead of double-clicking — you only have to do that once.

## Building it yourself

Needs Xcode 16+ with a macOS 26+ SDK. No dependencies to install and nothing
to fetch, just open the project and build.

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
permission — no Screen Recording, no TCC prompts. It's just a regular
window sitting at an unusual window level.

## Things that need a human to check

Some of this only really shows itself with someone actually watching:

- Drop a video on a display → it becomes a looping wallpaper behind the icons
- Survives switching Spaces and opening Mission Control
- A fullscreen app pauses that display's playback; leaving fullscreen resumes it
- Unplug and replug a monitor → its video comes back
- Quit and reopen the app, or restart the Mac entirely → wallpapers are still there
- "Pause on battery" actually pauses on unplug and resumes on AC
- Launch at Login toggle actually adds and removes the login item
- Screen saver toggle: turn it on, pick LiveWall under System Settings →
  Screen Saver → Other, and check it plays after going idle. If it shows a
  fallback message instead of your video, re-toggle it after (re)assigning
  one — Apple's third-party screen saver host has had bugs on recent macOS
  versions

## Code layout

```
LiveWall/
├── App/            entry point, sets up the no-Dock-icon app lifecycle
├── Core/           the actual engine — windows, players, persistence, power handling
├── UI/             menu bar item + the settings panel
└── Resources/      icon, accent color
LiveWallSaver/       the screen saver module, built as its own target
```

## Contributing

PRs welcome. It's a small codebase with zero dependencies, so it's easy to
poke around in Xcode. If you're touching the desktop-window-level code or
the wallpaper/screen-saver tricks, read the comments in those files first —
there's real reverse engineering behind some of it and the reasoning
matters more than usual.

## License

MIT. See [LICENSE](LICENSE) — use it, fork it, sell it, whatever.
