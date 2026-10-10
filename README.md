# QuickPlay

QuickPlay is a small macOS video viewer. It opens a video in a clean window with the
system playback controls, the same control bar that Quick Look shows.

## Build

Run the build script. It compiles the app into `~/Applications/QuickPlay.app` and
registers the app with Launch Services.

```sh
./build.sh
```

The script needs the Xcode command line tools (`swiftc`, `iconutil`).

## Keys

| Key | Action |
|---|---|
| Space | Play or pause |
| ← / → | Jump back or forward 5 s |
| , / . | Previous or next frame |
| F, Ctrl-Cmd-F, double-click | Full screen |
| Esc | Leave full screen, then close |
| ⌘C | Copy the current frame |

## Other formats

To play MKV, WebM and other formats, install
[QuickLook Video](https://github.com/Marginal/QuickLookVideo). Then turn on its two
Media Extensions in System Settings → General → Login Items & Extensions.
