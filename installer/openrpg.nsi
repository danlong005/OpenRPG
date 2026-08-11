!include "MUI2.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif

Name "openrpg ${VERSION}"
OutFile "openrpg-${VERSION}-windows-x64.exe"
InstallDir "$PROGRAMFILES64\openrpg"
InstallDirRegKey HKLM "Software\openrpg" "InstallDir"
RequestExecutionLevel admin
Unicode true

!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "OpenRPG Compiler (rpgc)" SecMain
    SectionIn RO
    SetOutPath "$INSTDIR"
    File "rpgc.exe"

    SetOutPath "$INSTDIR\runtime"
    File "rpg_runtime.h"
    File "rpg_sql_runtime.h"
    File "rpg_xml_runtime.h"
    File "rpg_json_runtime.h"
    File "rpg_csv_runtime.h"

    ; Bundled C++ compiler (llvm-mingw, trimmed) — rpgc/dspfc transpile to
    ; C++ and shell out to a real compiler to build the final .exe. Part of
    ; the required section, not a Components-page choice: a user
    ; unselecting this would silently break every compile with no
    ; indication why, since rpgc has no way to tell them "you skipped the
    ; compiler" at that point.
    SetOutPath "$INSTDIR\mingw"
    File /r "mingw\*.*"

    ; Add install dir to system PATH. Also add mingw\bin: -static doesn't
    ; fully static-link this toolchain's libc++/libunwind (confirmed on
    ; real hardware — compiled programs still hit "error while loading
    ; shared libraries: libunwind.dll"), so programs rpgc compiles need
    ; that directory reachable via the standard DLL search order.
    nsExec::ExecToStack "powershell -NonInteractive -Command $\"[Environment]::SetEnvironmentVariable('PATH', [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';$INSTDIR;$INSTDIR\mingw\bin', 'Machine')$\""

    WriteUninstaller "$INSTDIR\uninstall.exe"

    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\openrpg" "DisplayName" "openrpg"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\openrpg" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\openrpg" "DisplayVersion" "${VERSION}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\openrpg" "Publisher" "Daniel Long"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\openrpg" "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\openrpg" "NoRepair" 1
SectionEnd

Section "OpenDSPF Display File Compiler (dspfc)" SecDspf
    SetOutPath "$INSTDIR"
    File "dspfc.exe"
    SetOutPath "$INSTDIR\runtime"
    File "rpg_dspf_runtime.h"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} "The RPG IV free-format compiler (rpgc), including the bundled C++ compiler it needs to build programs. Required."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDspf} "The display file compiler (dspfc) for interactive screen programs. Produces .dspfd descriptors consumed by rpg_dspf_runtime.h."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
    Delete "$INSTDIR\rpgc.exe"
    Delete "$INSTDIR\runtime\rpg_runtime.h"
    Delete "$INSTDIR\runtime\rpg_sql_runtime.h"
    Delete "$INSTDIR\runtime\rpg_xml_runtime.h"
    Delete "$INSTDIR\runtime\rpg_json_runtime.h"
    Delete "$INSTDIR\runtime\rpg_csv_runtime.h"
    Delete "$INSTDIR\dspfc.exe"
    Delete "$INSTDIR\runtime\rpg_dspf_runtime.h"
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR\runtime"
    RMDir /r "$INSTDIR\mingw"
    RMDir "$INSTDIR"

    ; Remove install dir (and mingw\bin) from system PATH
    nsExec::ExecToStack "powershell -NonInteractive -Command $\"$$p = [Environment]::GetEnvironmentVariable('PATH', 'Machine'); $$p = ($$p -split ';' | Where-Object { $$_ -ne '$INSTDIR' -and $$_ -ne '$INSTDIR\mingw\bin' }) -join ';'; [Environment]::SetEnvironmentVariable('PATH', $$p, 'Machine')$\""

    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\openrpg"
    DeleteRegKey HKLM "Software\openrpg"
SectionEnd
