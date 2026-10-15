# Changelog

All notable changes to VirtualRemote are listed here, newest first. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add an entry
for every release before running `scripts/release.sh`.

## [Unreleased]

### Changed

- With nothing playing, play, pause, next, previous and stop are refused with
  "Nothing is playing." Before, pressing play made macOS launch Apple Music. A
  paused or idle player still counts as a session, so play still resumes it.

### Fixed

- Skipping on a live stream (for example YouTube live) jumped far behind the live
  edge, because a live stream reports an elapsed time but no length. Skip and seek
  are now refused for any player without a known length, and the skip buttons are
  greyed out for it.
- A failed command showed raw text such as `noActivePlayer` or
  `processFailed(executable: ...)`. It now shows a plain sentence, for example
  "Nothing is playing." or "This is a live stream or has no known length, so it
  cannot skip or seek."
- An error message stayed on screen until the next reconnect. It now disappears after
  5 seconds, and a newer message replaces it.
- Stopping the receiver right after starting it (for example by switching the mode)
  could leave a stale error such as "The media adapter is missing" on the stopped
  receiver. A start that was cancelled no longer writes to the status.

## [0.2.1] - 2026-10-15

### Fixed

- A receiver whose output has no software volume (HDMI or DisplayPort displays)
  never sent any state, so controllers showed "Nothing playing" forever. The state
  now arrives, and the controller hides the volume row for such a receiver.

### Changed

- The receiver reads volume and mute from CoreAudio instead of starting two
  `osascript` processes every second. With a controller connected, the helper
  processes now cost about 7 times less CPU. Setting the volume still uses
  `osascript`.

### Added

- The MIT license (`LICENSE`).
- The app bundle now carries `LICENSE` and `ThirdPartyLicenses.txt` (KeyboardShortcuts
  and the Octicons GitHub mark, both MIT), next to the adapter's BSD-3 license.

## [0.2.0] - 2026-10-15

Not compatible with 0.1.x. Both Macs must run 0.2.0 or newer.

### Added

- The popover shows the player's app icon and name, read on the receiver, so it
  also works for apps that are not installed on the controller.
- Click or drag the progress bar to jump to a position. A time bubble follows the
  cursor.
- Each receiver in the list shows an icon for its kind of Mac (Mac mini, MacBook,
  iMac, Mac Studio, Mac Pro), sent through the Bonjour record.
- Clear connection screens instead of one long message: searching, connecting,
  receiver not visible, not answering, pairing key does not match, local network
  access blocked, and connection lost. Each has one button where it helps, and the
  status dot is amber while the app is busy.
- About section in Settings with the app logo, the version, a link to the author
  and a GitHub icon that opens the source.
- The pointing-hand cursor on buttons, links, toggles, pickers, steppers and the
  progress and volume bars.

### Changed

- The numbers in the skip icons are larger and readable.
- The Settings tab "Keyboard Shortcuts" is now called "Shortcuts" so it fits the
  toolbar.

## [0.1.1] - 2026-10-15

### Fixed

- A receiver that goes silent (a sleeping Mac or a dropped Wi-Fi) is now noticed in
  about 15 seconds, so the controller shows "Disconnected" and reconnects. It used
  to take about 10 minutes.

### Added

- Install and update with Homebrew: `brew install --cask tarikkavaz/tap/virtualremote`.

## [0.1.0] - 2026-10-15

First release, a signed and notarized universal app.

### Added

- Control the media playing on another Mac on the local network, like an Apple
  Remote: play, pause, previous, next and stop (stop only for players known to
  support it).
- Skip back and forward by two lengths, 10 and 20 seconds by default.
- Volume slider and mute.
- Now playing display with title, artist, app, progress and cover art.
- Global keyboard shortcuts that work in any app.
- One menu bar app with three modes: Controller, Receiver, or Both. The receiver
  can launch at login.
- Automatic discovery of receivers with Bonjour, and an encrypted connection
  (TLS 1.2 with a pre-shared key). The 120-bit pairing key is shown on the receiver,
  entered once on the controller, and stored in the Keychain.
- Works with whatever macOS reports as Now Playing: tested with Plex, YouTube in
  Arc, and Spotify.
- Settings window with General, Modes and Shortcuts tabs.
- Help when macOS blocks Local Network access or asks for Keychain access.
- App icon and menu bar icon.
