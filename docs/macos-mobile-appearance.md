# macOS and mobile interface (1.1.4)

macOS now opens a regular main window on launch and Dock reopen, with a native behind-window visual effect, rounded content panels and an adaptive light/dark palette. The left panel shows recent history; the right panel shows selectable full text and image content. Copy, refresh, sync, account and legacy unlock remain available. Closing hides the window while the menu-bar sync agent continues; closing and logout release preview/history data. Record IDs guard against stale async previews.

Flutter mobile uses a shared indigo palette, rounded translucent surfaces and restrained background colors across login, history and detail. The header/login surface uses a clipped backdrop blur; history rows avoid per-row blur costs. High contrast uses opaque surfaces. Card actions have separate touch targets and long device names truncate; phone/tablet widths and large text are verified. This shared source also styles iOS, but an iOS simulator build does not constitute a signed device release.

Release 1.1.4 updates macOS and Android only. The existing Windows 1.1.3 artifact remains unchanged. New records remain plaintext over authenticated HTTPS; this visual change does not modify or delete server history.

macOS distribution uses `SharedClipboard-1.1.4-macos-universal.dmg`. Open the disk image and drag `Shared Clipboard.app` to the included `Applications` shortcut, then launch it from Applications and eject the image. The packaging script builds both architectures, verifies the app signature, creates a compressed read-only HFS+ image and verifies the image checksum. The `.app` in `desktop/out` is an intermediate, not the downloadable installer. The preview package remains ad-hoc signed and is not notarized.
