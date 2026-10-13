fn main() {
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let mut build = cc::Build::new();
    build.cpp(true).include("native");
    if os == "macos" {
        build
            .files([
                "native/macos.mm",
                "native/macos_network.mm",
                "native/macos_storage.mm",
            ])
            .flag("-std=c++17")
            .flag("-fobjc-arc");
        for framework in ["AppKit", "Foundation", "Security"] {
            println!("cargo:rustc-link-lib=framework={framework}");
        }
    } else if os == "windows" {
        build
            .files([
                "native/windows.cpp",
                "native/windows_ui.cpp",
                "native/windows_network.cpp",
                "native/windows_clipboard.cpp",
            ])
            .flag_if_supported("/std:c++17")
            .flag_if_supported("/utf-8")
            .define("UNICODE", None)
            .define("_UNICODE", None)
            .define("WIN32_LEAN_AND_MEAN", None);
        for lib in [
            "user32", "shell32", "winhttp", "crypt32", "ole32", "gdiplus", "gdi32", "uxtheme",
        ] {
            println!("cargo:rustc-link-lib={lib}");
        }
    } else {
        panic!("Desktop supports Windows and macOS");
    }
    build.compile("clipboard_native");
    println!("cargo:rerun-if-changed=native");
}
