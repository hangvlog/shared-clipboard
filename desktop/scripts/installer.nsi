Unicode true
Name "Shared Clipboard"
OutFile "SharedClipboard-1.1.0-windows-x64-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\SharedClipboard"
RequestExecutionLevel user
!include "MUI2.nsh"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
Section
 SetOutPath "$INSTDIR"
 File "..\target\release\shared-clipboard.exe"
 WriteUninstaller "$INSTDIR\Uninstall.exe"
 CreateShortcut "$SMPROGRAMS\Shared Clipboard.lnk" "$INSTDIR\shared-clipboard.exe"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SharedClipboard" "DisplayName" "Shared Clipboard"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SharedClipboard" "DisplayVersion" "1.1.0"
 WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SharedClipboard" "UninstallString" '$"$INSTDIR\Uninstall.exe$"'
SectionEnd
Section "Uninstall"
 Delete "$INSTDIR\shared-clipboard.exe"
 Delete "$INSTDIR\Uninstall.exe"
 Delete "$SMPROGRAMS\Shared Clipboard.lnk"
 RMDir "$INSTDIR"
 DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\SharedClipboard"
SectionEnd
