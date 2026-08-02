# Tiny 11 Auto Builder & LTSC Toolkit

[**English**](README.md) | [**Tiếng Việt**](README_VI.md)

A powerful, automated PowerShell toolkit designed to build streamlined, bloat-free, and performance-optimized Windows 11 and Windows 11 LTSC ISO images. Works with any official Windows 11 ISO across all languages and system architectures (`x64`, `arm64`).

---

## 🌟 Overview

**Tiny 11 Auto Builder** automates the creation of lightweight Windows 11 images using official Microsoft DISM utilities, recovery compression (`/compact`), and dynamic unattended answer files. No untrusted third-party binaries are used—only `oscdimg.exe` (from the official Microsoft Windows ADK) is utilized for bootable ISO generation.

### Supported Build Modes

| Script | Purpose | Serviceable | Best For |
| :--- | :--- | :---: | :--- |
| **`tiny11maker.ps1`** | Streamlined Windows 11 with consumer bloat removed | ✅ Yes | Daily desktop use, gaming, productivity |
| **`ltsc-builder.ps1`** | Windows 11 Enterprise LTSC / IoT Enterprise LTSC | ✅ Yes | Maximum stability, long-term support, enterprise |
| **`tiny11Coremaker.ps1`** | Ultra-minimal build with WinSxS component store removed | ❌ No | Lightweight testing labs, throwaway VMs |
| **`nano11maker.ps1`** | Extra-aggressive footprint reduction with driver removal | ❌ No | Kiosks, low-RAM devices, extreme benchmarking |

---

## ✨ Key Features

- 🎯 **Universal Compatibility**: Works with any Windows 11 or Windows 11 LTSC ISO (21H2 through 25H2+), any language, and architectures (`x64`, `arm64`).
- ⚡ **Intel RST (VMD) Driver Integration**: Automatically injects Intel Rapid Storage Technology drivers into both **`install.wim`** (Main OS) and **`boot.wim`** (Windows Setup WinPE), resolving "No drives found" NVMe/SSD issues on 11th–14th Gen Intel platforms.
- 🛒 **Microsoft Store for LTSC**: Preserves MS Store by default and automatically stages Microsoft Store installation (`wsreset.exe -i`) and service activation on LTSC editions.
- 🎮 **Optimization Presets**: Pre-configured JSON profiles (`gaming`, `minimal-vm`, `privacy-plus`, `default`) for one-click performance tuning.
- 🔒 **Enhanced Privacy & Latency Tweaks**: Blocks third-party telemetry (Nvidia, VSCode, Adobe), tunes mouse input queue latency, and limits Defender CPU usage.
- 🚀 **Dynamic OOBE & Hardware Bypass**: Bypasses Microsoft Account requirements on Windows 11 25H2+ (via `ms-cxh:localonly`), TPM 2.0, SecureBoot, RAM, and CPU requirements.
- 🌐 **Thorium Browser Integration**: Optional one-click injection of the lightweight, AVX2-optimized Thorium browser.
- ☁️ **GitHub Actions CI/CD**: Cloud-based ISO creation workflows (`build-optimized.yml` and `build-ltsc.yml`).

---

## 🎛️ Optimization Presets

Presets are JSON configuration profiles stored in the `presets/` directory.

| Preset | Description | Highlights |
| :--- | :--- | :--- |
| **`default`** | Balanced daily driver profile | Retains Store, removes consumer bloat, applies telemetry tweaks |
| **`gaming`** | Max performance & low input latency | Tunes mouse queue latency, limits Defender CPU usage, enables Ultimate Performance |
| **`minimal-vm`** | Ultra-lean footprint for virtual machines | Trims Defender & Store for minimum RAM and disk usage |
| **`privacy-plus`** | Strict telemetry & privacy hardening | Blocks third-party telemetry, disables ads, sponsored apps & tracking |

> **Parameter Precedence**: Explicit command-line arguments (e.g., `-RemoveDefender yes`) **always take precedence** over preset configuration defaults.

---

## 🛠️ Prerequisites & Requirements

- **Host OS**: Windows 10/11 or Windows Server 2022/2025 (Run as Administrator)
- **PowerShell**: PowerShell 5.1 or PowerShell 7+
- **ISO File**: Official Windows 11 or Windows 11 LTSC ISO
- **Free Disk Space**: At least 15–20 GB of free space on your scratch drive

---

## 🚀 Quick Start (Local PowerShell)

1. Download an official Windows 11 or Windows 11 LTSC ISO.
2. Double-click the ISO file in Windows File Explorer to mount it (note the drive letter, e.g., `E:`).
3. Open PowerShell as **Administrator**.
4. Set execution policy for the current session:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process
   ```
5. Run the desired builder script:

```powershell
# Standard Tiny11 Build with Gaming Preset
.\tiny11maker.ps1 -ISO E -SCRATCH D -Preset gaming

# Windows 11 LTSC Build with MS Store & Gaming Preset
.\ltsc-builder.ps1 -DriveLetter E -Edition "IoT Enterprise LTSC" -IsoName "ltsc-gaming.iso" -Preset gaming

# Custom Debloat (Keep Defender, Remove Edge & AI)
.\tiny11maker.ps1 -ISO E -SCRATCH D -RemoveDefender no -RemoveEdge yes -RemoveAI yes
```

---

## 📋 Parameter Reference

### `ltsc-builder.ps1`

| Parameter | Type | Default | Description |
| :--- | :---: | :---: | :--- |
| `-DriveLetter` | `string` | *(Required)* | Drive letter of mounted Windows LTSC ISO (e.g. `E`) |
| `-Edition` | `string` | *(Required)* | Target edition (`IoT Enterprise LTSC`, `Enterprise LTSC`, `IoT Enterprise Subscription LTSC`) |
| `-IsoName` | `string` | *(Required)* | Output ISO filename (e.g. `ltsc.iso`) |
| `-Preset` | `string` | `''` | Preset configuration profile (`gaming`, `minimal-vm`, `privacy-plus`, `default`) |
| `-RemoveDefender` | `string` | `'no'` | Remove Windows Defender (`yes` / `no`) |
| `-RemoveEdge` | `string` | `'yes'` | Remove Microsoft Edge browser (`yes` / `no`) |
| `-RemoveAI` | `string` | `'no'` | Remove AI / Copilot components (`yes` / `no`) |
| `-RemoveStore` | `string` | `'no'` | Remove Microsoft Store (`yes` / `no`) |
| `-AddStore` | `string` | `'yes'` | Install & enable MS Store on LTSC edition (`yes` / `no`) |
| `-AddThorium` | `string` | `'yes'` | Add Thorium browser (`yes` / `no`) |
| `-IrstDriverPath` | `string` | `''` | Custom path to Intel RST driver `.inf` folder |

### `tiny11maker.ps1`

| Parameter | Type | Default | Description |
| :--- | :---: | :---: | :--- |
| `-ISO` | `string` | Prompted | Drive letter of mounted Windows 11 ISO (e.g. `E`) |
| `-SCRATCH` | `string` | Script Dir | Working drive letter with free disk space (e.g. `D`) |
| `-Preset` | `string` | `''` | Preset configuration profile (`gaming`, `minimal-vm`, `privacy-plus`, `default`) |
| `-RemoveDefender` | `string` | `'no'` | Remove Windows Defender (`yes` / `no`) |
| `-RemoveEdge` | `string` | `'yes'` | Remove Microsoft Edge browser (`yes` / `no`) |
| `-RemoveAI` | `string` | `'yes'` | Remove AI / Copilot components (`yes` / `no`) |
| `-RemoveStore` | `string` | `'no'` | Remove Microsoft Store (`yes` / `no`) |
| `-VersionSelector` | `string` | `'Auto'` | Edition selector (`Auto`, `Pro`, `Home`, `ProWorkstations`) |
| `-AddThorium` | `string` | `'no'` | Add Thorium browser (`yes` / `no`) |
| `-IrstDriverPath` | `string` | `''` | Custom path to Intel RST driver `.inf` folder |
| `-NonInteractive` | `switch` | `$false` | Non-interactive mode for automated scripts / CI |

---

## ☁️ GitHub Actions Cloud Building

You can generate custom bootable ISOs directly on GitHub runners without installing anything locally.

1. Fork this repository.
2. Navigate to the **Actions** tab in your repository.
3. Select a workflow:
   - **`Build Tiny11 ISO (Optimized)`** for regular Windows 11 (`maker`, `core`, `nano`).
   - **`Build LTSC ISO`** for Windows 11 Enterprise LTSC.
4. Click **Run workflow**, choose your preferred edition, preset, and debloat options.
5. Once complete, download the generated ISO from the workflow **Artifacts** section.

---

## 🧩 Component Removal Matrix

| Component | `tiny11maker` | `ltsc-builder` | `tiny11Coremaker` | `nano11maker` |
| :--- | :---: | :---: | :---: | :---: |
| **Consumer Apps** (News, Weather, Solitaire, Xbox) | ❌ Removed | ❌ Removed | ❌ Removed | ❌ Removed |
| **OneDrive** | ❌ Removed | ❌ Removed | ❌ Removed | ❌ Removed |
| **Copilot / AI Components** | ❌ Optional | ❌ Retained | ❌ Removed | ❌ Removed |
| **Microsoft Edge** | ❌ Optional | ❌ Optional | ❌ Optional | ❌ Optional |
| **Microsoft Store** | ✅ Retained | ✅ Retained & Added | ❌ Optional | ❌ Optional |
| **Windows Defender** | ✅ Retained | ✅ Retained | ❌ Removed | ❌ Optional |
| **WinSxS Component Store** | ✅ Retained | ✅ Retained | ❌ Removed | ❌ Removed |
| **Windows Update** | ✅ Functional | ✅ Functional | ❌ Disabled | ❌ Disabled |
| **Drivers** (Printer, Bluetooth, Scanner) | ✅ Retained | ✅ Retained | ✅ Retained | ❌ Stripped |

---

## ❓ Frequently Asked Questions (FAQ)

<details>
<summary><b>1. Why does Windows Setup say "No drives found" on my Intel 11th–14th Gen laptop?</b></summary>
Intel 11th–14th Gen processors use Intel VMD technology. This toolkit automatically injects IRST (Intel Rapid Storage Technology) drivers into both `boot.wim` (WinPE Setup) and `install.wim` (Main OS), ensuring NVMe SSD drives are detected out-of-the-box.
</details>

<details>
<summary><b>2. How is Microsoft Store installed on Windows 11 LTSC?</b></summary>
Official LTSC ISOs do not include Microsoft Store. When building with `ltsc-builder.ps1`, required Store background services (`ClipSVC`, `AppXSvc`, `InstallService`, `LicenseManager`) are enabled, and `wsreset.exe -i` is automatically staged on first boot to download and initialize Microsoft Store natively.
</details>

<details>
<summary><b>3. Why does Defender remain when I select the Gaming preset?</b></summary>
The `gaming` preset profile keeps Windows Defender by default while applying CPU scan limits (`25%` CPU cap) and tuning mouse queue latency. If you explicitly specify `-RemoveDefender yes`, your explicit command-line choice will override the preset and remove Defender.
</details>

---

## 🤝 Acknowledgments & Credits

- Original Tiny11 concept by **ntdev** (`@ntdevlabs`).
- Automated builder enhancements, LTSC Store integration, and IRST driver pipeline developed for **Tiny Auto Builder**.
