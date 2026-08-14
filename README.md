# SimSlim Menu

A small macOS menu bar app for the local iOS Simulator fleet.

It shows each simulator's runtime state and simslim optimization state. You can copy a simulator UUID or shut down a running simulator. It does not create, rename, erase, or delete devices.

## Requirements

- macOS 14 or later
- Xcode command-line tools
- [`simslim`](https://github.com/mobai-app/simslim) installed in `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`

## Run

```sh
swift run
```

The iPhone icon appears in the menu bar. The app does not appear in the Dock.

## Build the app

```sh
make app
open "dist/SimSlim Menu.app"
```

The signed local app bundle is created at `dist/SimSlim Menu.app`. You can move it to `/Applications` if you want.
