## Tiny 11 Auto Builder Tool
Scripts to build a streamlined, bloat‑reduced Windows 11 image using PowerShell. Works with any official Windows 11 ISO, in any language or architecture.

### Overview
Tiny 11 Auto Builder automates creating a smaller, cleaner Windows 11 ISO. It leverages DISM, recovery compression, and an optional unattended answer file to reduce size, skip the Microsoft Account requirement in OOBE, and deploy with the `/compact` flag. No third‑party binaries are required beyond `oscdimg.exe` from the Windows ADK to generate the bootable ISO.

The toolkit includes two build modes:
- `tiny11maker.ps1` — Regular, serviceable Windows 11 (recommended for everyday use)
- `tiny11coremaker.ps1` — Extra‑minimal, non‑serviceable image (for testing/VMs)

### Key Features
- Works with any Windows 11 ISO, language, and architecture (x64, arm64)
- Automated trimming of inbox apps and features
- Uses DISM recovery compression for smaller ISOs
- Optional unattended setup to bypass MSA in OOBE and auto‑apply `/compact`
- Produces a bootable ISO via `oscdimg.exe`

### Requirements
- Windows 11 host with administrative privileges
- PowerShell 5.1
- Official Windows 11 ISO (download from Microsoft or via Rufus)
- Optional: Windows ADK (for `oscdimg.exe`)

### Quick Start
1) Download an official Windows 11 ISO.
2) Mount the ISO in File Explorer.
3) Open PowerShell 5.1 as Administrator.
4) Temporarily allow script execution for this session:
```powershell
Set-ExecutionPolicy Bypass -Scope Process
```
5) Run a builder script (replace with your paths and drive letters):
```powershell
./tiny11maker.ps1 -ISO <mount_letter> -SCRATCH <work_letter>
```
6) Select the mounted ISO drive letter (letter only, no colon).
7) Choose the Windows edition (SKU) to base your image on.
8) Wait for completion. The resulting ISO (e.g., `tiny11.iso`) will be created in the script folder.

Tip: Use `Get-Help .\tiny11maker.ps1 -Detailed` for all available parameters.

### Parameters (common)
- `-ISO` — Drive letter of the mounted Windows 11 ISO (e.g., `E`)
- `-SCRATCH` — Working drive letter with sufficient free space
- Optional flags vary per script; use `Get-Help` to discover advanced options

### Build Modes
- `tiny11maker.ps1`
  - Removes consumer bloat while keeping the image serviceable
  - You can still add languages, updates, and features later

- `tiny11coremaker.ps1`
  - Removes even more components, including the component store
  - Not serviceable: you cannot add updates, features, or languages later
  - Best for fast test/dev environments and lightweight VMs

### Nano 11 (extra‑aggressive build)
`nano11maker.ps1` targets the smallest possible Windows 11 footprint for highly constrained scenarios (throwaway VMs, labs, kiosks). It removes more apps and components than the regular build and is intended for advanced users who understand the trade‑offs.

- Focuses on minimal disk/RAM footprint and reduced background activity
- Non‑serviceable in practice; expect limited feature/add‑on support
- Some experiences and system integrations may be absent by design

Quick use (same parameter pattern as other scripts):
```powershell
./nano11maker.ps1 -ISO <mount_letter> -SCRATCH <work_letter>
```
Use `Get-Help .\nano11maker.ps1 -Detailed` to discover advanced options and up‑to‑date behavior.

### What gets removed
The exact removal set depends on the mode. In general, the regular build trims common consumer apps; the core build removes everything the regular build does plus additional system components.

Regular (`tiny11maker`):
- Clipchamp, News, Weather, Xbox, GetHelp, GetStarted, Office Hub, Solitaire
- PeopleApp, PowerAutomate, ToDo, Alarms, Mail and Calendar, Feedback Hub
- Maps, Sound Recorder, Your Phone, Media Player, Quick Assist
- Internet Explorer, Tablet PC Math, Edge, OneDrive

Core (`tiny11coremaker`) additionally targets:
- Windows Component Store (WinSxS)
- Windows Defender (disabled; can be re‑enabled, but not recommended)
- Windows Update (not functional without WinSxS)
- Windows Recovery Environment (WinRE)

Important: With the core build you cannot add features later. During creation you may be prompted to enable .NET 3.5 support.

### Known Issues and Notes
- Edge stubs may still appear in Settings though the app is removed
- You may need to update `winget` before installing apps via Microsoft Store
- Outlook and Dev Home may re‑appear over time; latest scripts minimize this
- On arm64, a brief script error may appear due to missing `OneDriveSetup.exe`

### Support and Contributions
This project is open‑source. PRs and feedback are welcome. Customize the removal list to fit your needs.

If the tool helps you, consider supporting continued development:
- Patreon: `http://patreon.com/ntdev`
- PayPal: `http://paypal.me/ntdev2`
- Ko‑fi: `http://ko-fi.com/ntdev`

Thank you for using Tiny 11 Auto Builder!
