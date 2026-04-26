# Agent Notes

This project is a Windows utility for registering portable/green software so it behaves more like normally installed software.

## Product Goal

The user has many portable Windows apps and games. After reinstalling Windows or moving systems, they want a quick way to make those apps appear in the Start menu and, where possible, in Windows "Installed apps".

The preferred workflow is non-technical:

1. Open a small window.
2. Drag one or more `.exe` files into it.
3. Choose a readable app name from suggestions, or type one manually.
4. The app appears in the Start menu.
5. The management window shows registered apps and can remove them.

The user wants this to feel close to native installation, but they understand that records stored in AppData disappear if the Windows profile is wiped.

## Important User Preferences

- The UI should be simple and drag-and-drop oriented.
- The user does not want to maintain a JSON manifest manually for the normal workflow.
- Naming matters. Portable executable names are often messy, such as `ps2019.exe`, `GTA-VC.exe`, `gamemd.exe`, or `ra2md.exe`.
- The naming dialog should offer multiple suggestions, similar to music tagging apps that suggest possible song names/lyrics.
- The user wants to be able to manually choose or edit the final name before registration.
- A management list is required. It should show apps already registered by this tool and allow removing selected entries.
- Removing an entry should delete this tool's Start menu shortcut, registry registration, and AppData record, but must not delete the actual portable app files.

## Current Main Files

- `PortableAppRegister-GUI.ps1`: Main WinForms GUI.
- `PortableAppRegister.bat`: Double-click launcher for the GUI.
- `Register-PortableApps.ps1`: Older manifest-based CLI flow.
- `apps.example.json`: Example manifest for the CLI flow.
- `README.md`: User-facing usage notes.

## Current Persistence Model

The GUI writes records to:

```text
%APPDATA%\PortableAppRegister\apps.json
```

It also writes:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\<id>
HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\<exe name>
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Portable Apps
```

The management list should merge sources:

- AppData database records.
- Registry entries marked with `PortableAppRegisterId`.
- `.lnk` files found in the `Portable Apps` Start menu folder.

This merge behavior was added because some partial failures created shortcuts without list records.

## Known Pain Points

The list display has been troublesome. The user reported cases where the status said `Registered apps: 2` but the visible list looked empty. Defensive behavior added so far:

- fallback display name from shortcut path, target path, exe name, or id;
- fallback target text from target path, shortcut path, or exe name;
- status now includes visible row count;
- list refresh catches per-item failures and writes logs;
- newly registered items are reinserted after refresh so refresh does not wipe them from the visible list.

If this still fails, inspect `Refresh-AppList`, `Upsert-AppListItem`, and WinForms docking/order. Consider replacing `ListView` with a simpler `DataGridView`, which may be more reliable for mixed data.

## Error Logs

Detailed GUI errors are written to:

```text
%APPDATA%\PortableAppRegister\errors.log
```

Ask the user to open this file if GUI behavior is unclear.

## Naming Suggestions

Current naming sources:

- built-in alias rules;
- `.exe` version info: `ProductName`, `FileDescription`, `InternalName`, `OriginalFilename`;
- parent folder name;
- file name;
- optional DuckDuckGo HTML search results.

Known alias examples:

- `ps2019` -> `Adobe Photoshop 2019`
- `pr2020` -> `Adobe Premiere Pro 2020`
- `GTA-VC` -> `Grand Theft Auto: Vice City`
- `GTA-SA` -> `Grand Theft Auto: San Andreas`
- `gamemd` / `ra2md` -> `Command & Conquer: Yuri's Revenge`
- `ra2` -> `Command & Conquer: Red Alert 2`

The alias list is intentionally local and pragmatic. A good future improvement is a user-editable alias file:

```text
%APPDATA%\PortableAppRegister\aliases.json
```

## Git / Upload Context

The user asked about uploading this directory to GitHub using SourceTree.

This environment had trouble running `git init` because Git lock/object writes failed inside the sandbox. Failed attempts left ignored directories:

```text
.git/
.codex-git/
repo-data/
```

`.gitignore` ignores these. The user was advised to delete those directories from File Explorer before using SourceTree.

Recommended SourceTree flow:

1. Create an empty GitHub repo in the browser.
2. Delete any bad local `.git`, `.codex-git`, and `repo-data` folders.
3. In SourceTree, use `Create` or `Add Working Copy`, not `Clone`.
4. Choose `D:\Documents\repos-other\app-register`.
5. Commit files.
6. Add GitHub remote as `origin`.
7. Push `main`.

The screenshot the user showed was SourceTree's `Clone` screen. That screen is for downloading an existing remote repo, not uploading this existing local directory.

## Development Constraints

- Keep the GUI Windows-native and easy to launch by double-clicking `PortableAppRegister.bat`.
- Avoid requiring admin permission. Use HKCU and current user's Start menu.
- Keep `.ps1` executable strings ASCII where possible because Windows PowerShell 5 can misread UTF-8 without BOM. README and docs can be Chinese.
- The UI currently uses English text to avoid encoding problems in Windows PowerShell.
- Avoid deleting portable app files. Only remove shortcuts and records created by this tool.
- When adding new registry writes, make partial failure recoverable and visible in the management list.

## Likely Next Improvements

- Replace `ListView` with `DataGridView` if the list still appears empty.
- Add `Repair selected` / `Restore all` to recreate missing shortcuts from AppData records.
- Add user-editable alias database in AppData.
- Add import/export for AppData records.
- Package as a proper `.exe` later, but keep the script launcher working.
