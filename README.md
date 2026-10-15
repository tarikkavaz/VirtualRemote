# VirtualRemote

VirtualRemote is a menu bar app for macOS that controls the media playing on another Mac on your network, like an Apple Remote for your Mac.

Say a video is playing on a Mac mini under the TV, and you are working on a laptop in the same room. VirtualRemote lets you pause it, skip forward 20 seconds, change the volume or jump to the next track without leaving your work.

## What it does

- Play, pause, previous, next and stop.
- Skip back and forward by two lengths. The defaults are 10 and 20 seconds, and you can change them.
- Volume slider, mute, and volume shortcuts.
- Shows what is playing: title, artist, the app with its icon, a progress bar and the cover art or thumbnail.
- Click or drag the progress bar to jump to any point. A time bubble shows where you will land.
- Global keyboard shortcuts that work in any app.
- Finds the other Mac automatically on your local network and remembers it. Each Mac in the list shows an icon for its kind (Mac mini, MacBook, iMac and so on).

It controls whatever macOS lists as "Now Playing" on the other Mac. We tested Plex, YouTube in Arc, Spotify, Safari, Chrome, Firefox, VLC, Apple Music and Apple TV. Other players that report to Now Playing should work, but we have not tried them.

## Requirements

- macOS 14 or newer on both Macs.
- Both Macs on the same local network, running the same version of VirtualRemote. Versions before 0.2.0 do not work with 0.2.0 or newer.
- Apple Silicon or Intel. The release is a universal build. It has only been tested on Apple Silicon Macs running macOS 27.

## Install

1. Download `VirtualRemote-<version>.zip` and unzip it.
2. Drag `VirtualRemote.app` into your `Applications` folder.
3. Open it. A small remote icon appears in the menu bar.

The release is signed and notarized by Apple, so macOS opens it without a warning. Do this on both Macs.

Or install with Homebrew:

```sh
brew install --cask tarikkavaz/tap/virtualremote
```

Update later with `brew upgrade --cask virtualremote`.

## Set up

One Mac plays the media (the receiver) and the other controls it (the controller). A Mac can also be both.

1. On the Mac that plays the media, open the menu bar icon, click the gear, and go to Modes. Choose Receiver, or Both.
2. Copy the pairing key shown there. It looks like `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`.
3. On the controlling Mac, open the menu bar icon and choose the other Mac from the list.
4. Enter the pairing key. You only do this once. After that the two Macs reconnect by themselves.

The first time, macOS asks for two permissions:

- **Local Network:** allow it, or the Macs cannot find each other. If the popover says there was no answer after 10 seconds, it has a button that opens this setting.
- **Keychain:** the app stores pairing keys there. Choose Always Allow so it does not ask again.

## Keyboard shortcuts

These work from any app. Change them in Settings > Shortcuts.

| Action                  | Default shortcut                                   |
| ----------------------- | -------------------------------------------------- |
| Play or pause           | Control + Option + Command + Space                 |
| Back or forward (short) | Control + Option + Command + Left or Right         |
| Back or forward (long)  | Shift + Control + Option + Command + Left or Right |
| Volume up or down       | Control + Option + Command + Up or Down            |
| Stop                    | Control + Option + Command + S                     |
| Previous or next        | Control + Option + Command + Comma or Period       |

## Settings

Open the gear in the popover.

- **General:** launch at login, connect to the last receiver automatically, the volume step for shortcuts, the two skip lengths, and an About section.
- **Modes:** choose Controller, Receiver or Both. This is also where the receiver shows its pairing key and status, and where you enter or forget a key for the Mac you control.
- **Shortcuts:** record your own keyboard shortcuts.

## Privacy and security

- Everything stays on your local network. There is no account, no cloud service and no tracking.
- The connection is encrypted (TLS 1.2 with a pre-shared key). The key is a random 120-bit value made on the receiver. Only controllers that know it can connect.
- Keys are stored in your Keychain. "New key" in the receiver settings makes a new one, which unpairs every controller.
- The app is not sandboxed. It needs to run helper tools to read and control media.

## Troubleshooting

- **The popover says "Connecting" for a long time.** Check that VirtualRemote is allowed under System Settings > Privacy & Security > Local Network, then quit and reopen it. Make sure the receiver Mac is awake and the app is running there.
- **The other Mac does not appear.** Both Macs must be on the same network. Some guest or "client isolation" Wi-Fi networks block this kind of discovery.
- **It asks for the key again.** The receiver's key changed, or the key was forgotten. Copy the current key from Settings > Modes on the receiver.
- **The receiver shows "Media control self-test failed".** A macOS update may have broken the helper that reads Now Playing. Update VirtualRemote, or open an issue.
- **A button does nothing.** Not every player supports every command. Stop is shown only for apps known to support it (Plex).

## How it works

The receiver app runs a small server that is announced on the network with Bonjour (`_virtualremote._tcp`). The controller connects over TLS and sends short JSON commands. The receiver turns them into Now Playing commands.

Since macOS 15.4, apps cannot call the system Now Playing service directly. VirtualRemote uses the open source [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), which runs through `/usr/bin/perl`, a system program that is allowed to. Skipping uses an absolute seek: the receiver reads the elapsed time, adds or subtracts the skip length, and seeks. Volume goes through the system volume with AppleScript. Cover art is cut down to a small JPEG and sent once per controller.

## Build from source

You need Xcode with Swift 6, plus `git` and `cmake` (for the adapter).

```sh
swift build        # build everything
swift test         # run the tests
sh scripts/make-app.sh   # build build/VirtualRemote.app, including the adapter
```

`make-app.sh` signs ad hoc by default. Set `SIGN_IDENTITY` to a certificate name to keep macOS permissions across rebuilds. An ad hoc signature changes with every build, so macOS may ask for Local Network access again.

To regenerate the icons from `Resources/Icons`, run `swift scripts/make-icons.swift`.

To try a build on this Mac and on a second Mac over ssh, run `scripts/deploy-dev.sh`. It builds and signs, checks the signature, then stops, copies, verifies and restarts the app on each Mac, and stops at the first failure. It needs `SIGN_IDENTITY` and, for the second Mac, an ssh host name in `REMOTE_HOST` (default `macmini`). Pass `local` or `remote` to deploy to only one of them. It does not notarize or publish anything.

### Release

`scripts/release.sh` builds a universal, hardened, notarized app and writes `build/VirtualRemote-<version>.zip`. It needs a Developer ID Application certificate and a notarytool credential profile. Create the profile once, in a normal Terminal window:

```sh
xcrun notarytool store-credentials VirtualRemote-notary \
    --apple-id <your Apple ID> --team-id <your team ID>
```

Then run:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" sh scripts/release.sh
```

### Project layout

- `Sources/VirtualRemoteCore`: the protocol, the command executor, the backends, and the network layer. This part is covered by tests.
- `Sources/VirtualRemote`: the menu bar app, the popover and the Settings window.
- `Sources/vrreceiver` and `Sources/vrctl`: small command line tools for testing a receiver and a controller without the app.
- `scripts`: build, icon and release scripts. `Resources`: the Info.plist and icons.

## Status

See the [changelog](CHANGELOG.md) for what changed in each version.

This is an early release (0.2.3). Launch at login, sleep and wake of the receiver, Wi-Fi drops, receiver restarts, two controllers at once, live streams, long and missing titles, and an idle receiver are tested. The things we have not been able to check are a first launch on a Mac that never ran the app and the Intel half of the universal build.

## Credits

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg and contributors, BSD 3-Clause. A copy of its license is inside the app bundle.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, MIT.
- The GitHub logo in the About section is the mark from [Octicons](https://github.com/primer/octicons) by GitHub, MIT.

## License

VirtualRemote is released under the [MIT License](LICENSE). The libraries it uses keep their own licenses, listed under Credits.
