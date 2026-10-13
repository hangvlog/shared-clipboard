# Windows appearance (1.1.3)

The native Windows client uses the system desktop-acrylic backdrop on Windows 11 22H2 or later, with system-rounded frame corners. The title bar, resizing, maximize/restore and caption buttons remain native. Windows 10, disabled transparency, high contrast or unavailable composition use an opaque background without requiring additional dependencies.

The canvas is rendered into a premultiplied-alpha DIB: only the outer background is translucent. History and preview cards remain opaque, with rounded selection rows, softer borders and a restrained indigo accent. Standard GDI controls use opaque buffered paint to avoid transparent or washed-out text over the extended DWM frame. System setting/theme changes refresh the palette and backdrop. High contrast uses system window/highlight text colors.

Native UI fixture verification covers history text/image rendering, copy/readback, stale preview rejection, error state, tray close/reopen and logout clearing. An interactive synthetic-data fixture verifies the actual compositor effect and native maximize/restore; private-window-station rendering alone cannot demonstrate acrylic. No clipboard contents from a real account are exported for screenshots.

Build: on the authorized Windows device, run `cargo test --locked`, `cargo build --release --locked` in `desktop/`, then NSIS against `desktop/scripts/installer.nsi`. Version 1.1.3 is a Windows-only release; macOS and Android retain their existing 1.1.2 artifacts.
