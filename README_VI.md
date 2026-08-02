# Tiny 11 Auto Builder & LTSC Toolkit (Tiếng Việt)

[**English**](README.md) | [**Tiếng Việt**](README_VI.md)

Bộ công cụ PowerShell tự động hóa tối ưu, giúp đóng gói lại bộ cài Windows 11 và Windows 11 LTSC tinh gọn, sạch sẽ, không ứng dụng rác (bloatware) và tối ưu hóa hiệu năng vượt trội. Hỗ trợ tất cả các file ISO Windows 11 chính thức ở mọi ngôn ngữ và kiến trúc hệ thống (`x64`, `arm64`).

---

## 🌟 Tổng quan

**Tiny 11 Auto Builder** tự động hóa quy trình tạo file ISO Windows 11 siêu nhẹ bằng cách sử dụng công cụ chính thức DISM từ Microsoft, nén khôi phục nâng cao (`/compact`), và file trả lời tự động tinh chỉnh OOBE. Dự án hoàn toàn không chứa phần mềm thứ ba không rõ nguồn gốc—chỉ sử dụng duy nhất `oscdimg.exe` (từ bộ Microsoft Windows ADK chính thức) để tạo file ISO khởi động (bootable ISO).

### Các chế độ đóng gói (Build Modes)

| Script | Mục đích sử dụng | Khả năng cập nhật (Serviceable) | Phù hợp cho |
| :--- | :--- | :---: | :--- |
| **`tiny11maker.ps1`** | Windows 11 tinh gọn tiêu chuẩn, loại bỏ bloatware | ✅ Có | Sử dụng làm việc hàng ngày, chơi game, văn phòng |
| **`ltsc-builder.ps1`** | Windows 11 Enterprise LTSC / IoT Enterprise LTSC | ✅ Có | Ổn định tối đa, máy cấu hình thấp, làm việc lâu dài |
| **`tiny11Coremaker.ps1`** | Phiên bản siêu tối giản, đã xóa kho component WinSxS | ❌ Không | Phòng lab thử nghiệm, máy ảo VM tạm thời |
| **`nano11maker.ps1`** | Phiên bản cắt giảm cực đoan, đã xóa sạch driver thừa | ❌ Không | Máy kiosk, máy RAM cực thấp, đua điểm Benchmark |

---

## ✨ Tính năng nổi bật

- 🎯 **Tương thích toàn diện**: Hỗ trợ mọi ISO Windows 11 & Windows 11 LTSC (từ 21H2 đến 25H2+), mọi ngôn ngữ và kiến trúc (`x64`, `arm64`).
- ⚡ **Tích hợp Driver IRST (Intel VMD)**: Tự động nạp driver Intel Rapid Storage Technology vào cả **`install.wim`** (Hệ điều hành) và **`boot.wim`** (Trình cài đặt WinPE), sửa triệt để lỗi "Không tìm thấy ổ cứng NVMe/SSD" trên chip Intel Gen 11–14.
- 🛒 **Microsoft Store cho bản LTSC**: Giữ lại MS Store mặc định và tự động kích hoạt/lập lịch cài đặt Microsoft Store (`wsreset.exe -i`) và khởi chạy các dịch vụ bản quyền trên bản LTSC.
- 🎮 **Cấu hình Preset một cú nhấp**: Các hồ sơ JSON cấu hình sẵn (`gaming`, `minimal-vm`, `privacy-plus`, `default`) giúp tối ưu nhanh theo mục đích sử dụng.
- 🔒 **Tăng cường Quyền riêng tư & Giảm độ trễ**: Chặn telemetry từ bên thứ 3 (Nvidia, VSCode, Adobe), tối ưu kích thước hàng đợi chuột (Mouse Latency), giới hạn mức dùng CPU của Defender scan xuống 25%.
- 🚀 **Bypass OOBE & Phần cứng tự động**: Bypass yêu cầu tài khoản Microsoft trên Windows 11 25H2+ (qua URI `ms-cxh:localonly`), bypass TPM 2.0, SecureBoot, RAM và CPU.
- 🌐 **Tích hợp trình duyệt Thorium**: Tùy chọn cài đặt nhanh trình duyệt Thorium siêu nhẹ, tối ưu AVX2 để thay thế Edge.
- ☁️ **Tự động đóng gói trên đám mây**: Hỗ trợ GitHub Actions Workflows (`build-optimized.yml` và `build-ltsc.yml`) để tạo ISO trực tiếp trên cloud mà không cần máy tính cấu hình mạnh.

---

## 🎛️ Các hồ sơ tối ưu hóa (Presets)

Các file Preset được lưu trữ trong thư mục `presets/` dưới dạng JSON.

| Preset | Mô tả chi tiết | Điểm nổi bật |
| :--- | :--- | :--- |
| **`default`** | Hồ sơ cân bằng cho nhu cầu hàng ngày | Giữ lại Store, xóa bloatware tiêu chuẩn, tối ưu riêng tư |
| **`gaming`** | Tối đa hiệu năng chơi game & giảm độ trễ | Tối ưu độ trễ chuột, giới hạn CPU Defender, bật Ultimate Performance |
| **`minimal-vm`** | Siêu tinh gọn cho máy ảo & phòng lab | Cắt giảm Defender & Store để tối ưu dung lượng RAM và ổ cứng |
| **`privacy-plus`** | Bảo mật riêng tư & chặn theo dõi tối đa | Chặn toàn bộ telemetry bên thứ 3, xóa quảng cáo & ứng dụng tài trợ |

> **Quy tắc ưu tiên tham số**: Khi bạn truyền tham số trực tiếp từ dòng lệnh (ví dụ: `-RemoveDefender yes`), lựa chọn của bạn **luôn được ưu tiên hàng đầu** và không bị đè bởi giá trị mặc định của file preset.

---

## 🛠️ Yêu cầu hệ thống

- **Hệ điều hành**: Windows 10/11 hoặc Windows Server 2022/2025 (Chạy với quyền Administrator)
- **PowerShell**: PowerShell 5.1 hoặc PowerShell 7+
- **File ISO mẫu**: File ISO Windows 11 hoặc Windows 11 LTSC chính thức từ Microsoft
- **Dung lượng trống**: Tối thiểu 15–20 GB dung lượng trống trên ổ đĩa scratch

---

## 🚀 Hướng dẫn nhanh (Chạy Local PowerShell)

1. Tải về file ISO Windows 11 hoặc Windows 11 LTSC chính thức từ Microsoft.
2. Click kép vào file ISO để Mount vào Windows File Explorer (ghi nhớ ký tự ổ đĩa, ví dụ: `E:`).
3. Mở PowerShell với quyền **Administrator**.
4. Cấp quyền chạy script cho phiên làm việc hiện tại:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process
   ```
5. Chạy lệnh đóng gói mong muốn:

```powershell
# Đóng gói Windows 11 chuẩn với Preset Gaming
.\tiny11maker.ps1 -ISO E -SCRATCH D -Preset gaming

# Đóng gói Windows 11 LTSC kèm MS Store & Preset Gaming
.\ltsc-builder.ps1 -DriveLetter E -Edition "IoT Enterprise LTSC" -IsoName "ltsc-gaming.iso" -Preset gaming

# Tùy chỉnh Debloat (Giữ lại Defender, Xóa Edge & AI)
.\tiny11maker.ps1 -ISO E -SCRATCH D -RemoveDefender no -RemoveEdge yes -RemoveAI yes
```

---

## 📋 Bảng tra cứu tham số chi tiết

### `ltsc-builder.ps1`

| Tham số | Kiểu dữ liệu | Mặc định | Mô tả |
| :--- | :---: | :---: | :--- |
| `-DriveLetter` | `string` | *(Bắt buộc)* | Ký tự ổ đĩa ISO LTSC đã mount (ví dụ: `E`) |
| `-Edition` | `string` | *(Bắt buộc)* | Phiên bản LTSC cần build (`IoT Enterprise LTSC`, `Enterprise LTSC`, `IoT Enterprise Subscription LTSC`) |
| `-IsoName` | `string` | *(Bắt buộc)* | Tên file ISO đầu ra (ví dụ: `ltsc.iso`) |
| `-Preset` | `string` | `''` | Cấu hình Preset (`gaming`, `minimal-vm`, `privacy-plus`, `default`) |
| `-RemoveDefender` | `string` | `'no'` | Xóa Windows Defender (`yes` / `no`) |
| `-RemoveEdge` | `string` | `'yes'` | Xóa trình duyệt Microsoft Edge (`yes` / `no`) |
| `-RemoveAI` | `string` | `'no'` | Xóa AI / Copilot (`yes` / `no`) |
| `-RemoveStore` | `string` | `'no'` | Xóa Microsoft Store (`yes` / `no`) |
| `-AddStore` | `string` | `'yes'` | Cài đặt & kích hoạt MS Store cho bản LTSC (`yes` / `no`) |
| `-AddThorium` | `string` | `'yes'` | Tích hợp trình duyệt Thorium (`yes` / `no`) |
| `-IrstDriverPath` | `string` | `''` | Đường dẫn thư mục driver Intel RST `.inf` tùy chỉnh |

### `tiny11maker.ps1`

| Tham số | Kiểu dữ liệu | Mặc định | Mô tả |
| :--- | :---: | :---: | :--- |
| `-ISO` | `string` | Hỏi khi chạy | Ký tự ổ đĩa ISO Windows 11 đã mount (ví dụ: `E`) |
| `-SCRATCH` | `string` | Thư mục script | Ổ đĩa tạm có dung lượng trống (ví dụ: `D`) |
| `-Preset` | `string` | `''` | Cấu hình Preset (`gaming`, `minimal-vm`, `privacy-plus`, `default`) |
| `-RemoveDefender` | `string` | `'no'` | Xóa Windows Defender (`yes` / `no`) |
| `-RemoveEdge` | `string` | `'yes'` | Xóa trình duyệt Microsoft Edge (`yes` / `no`) |
| `-RemoveAI` | `string` | `'yes'` | Xóa AI / Copilot (`yes` / `no`) |
| `-RemoveStore` | `string` | `'no'` | Xóa Microsoft Store (`yes` / `no`) |
| `-VersionSelector` | `string` | `'Auto'` | Chọn phiên bản Windows (`Auto`, `Pro`, `Home`, `ProWorkstations`) |
| `-AddThorium` | `string` | `'no'` | Tích hợp trình duyệt Thorium (`yes` / `no`) |
| `-IrstDriverPath` | `string` | `''` | Đường dẫn thư mục driver Intel RST `.inf` tùy chỉnh |
| `-NonInteractive` | `switch` | `$false` | Chế độ chạy tự động không hỏi câu hỏi (cho CI/CD) |

---

## ☁️ Đóng gói ISO trên Đám mây (GitHub Actions)

Bạn có thể tự tạo file ISO bootable trực tiếp trên máy chủ đám mây của GitHub hoàn toàn miễn phí.

1. **Fork** repository này về tài khoản GitHub của bạn.
2. Chuyển sang tab **Actions** trong repository vừa fork.
3. Chọn Workflow phù hợp:
   - **`Build Tiny11 ISO (Optimized)`** cho các bản Windows 11 thường (`maker`, `core`, `nano`).
   - **`Build LTSC ISO`** cho các bản Windows 11 LTSC.
4. Bấm **Run workflow**, chọn phiên bản, preset và các tùy chọn debloat mong muốn.
5. Sau khi quá trình hoàn tất, tải file ISO đầu ra tại mục **Artifacts** của Workflow Run.

---

## 🧩 Bảng so sánh các thành phần cắt giảm

| Thành phần | `tiny11maker` | `ltsc-builder` | `tiny11Coremaker` | `nano11maker` |
| :--- | :---: | :---: | :---: | :---: |
| **Ứng dụng Bloatware** (Weather, Solitaire, Xbox, News) | ❌ Xóa bỏ | ❌ Xóa bỏ | ❌ Xóa bỏ | ❌ Xóa bỏ |
| **OneDrive** | ❌ Xóa bỏ | ❌ Xóa bỏ | ❌ Xóa bỏ | ❌ Xóa bỏ |
| **Copilot / AI** | ❌ Tùy chọn | ❌ Giữ lại | ❌ Xóa bỏ | ❌ Xóa bỏ |
| **Microsoft Edge** | ❌ Tùy chọn | ❌ Tùy chọn | ❌ Tùy chọn | ❌ Tùy chọn |
| **Microsoft Store** | ✅ Giữ lại | ✅ Giữ & Tự thêm | ❌ Tùy chọn | ❌ Tùy chọn |
| **Windows Defender** | ✅ Giữ lại | ✅ Giữ lại | ❌ Xóa bỏ | ❌ Tùy chọn |
| **Kho WinSxS Component Store** | ✅ Giữ lại | ✅ Giữ lại | ❌ Xóa bỏ | ❌ Xóa bỏ |
| **Windows Update** | ✅ Hoạt động | ✅ Hoạt động | ❌ Tắt bỏ | ❌ Tắt bỏ |
| **Driver hệ thống** (Printer, Bluetooth, Scanner) | ✅ Giữ lại | ✅ Giữ lại | ✅ Giữ lại | ❌ Xóa loại bỏ |

---

## ❓ Câu hỏi thường gặp (FAQ)

<details>
<summary><b>1. Tại sao trình cài đặt Windows báo "No drives found" trên laptop chip Intel Gen 11–14?</b></summary>
Các máy tính dùng chip Intel thế hệ 11–14 bật công nghệ Intel VMD. Bộ công cụ này tự động nạp sẵn driver IRST (Intel Rapid Storage Technology) vào cả `boot.wim` (WinPE Setup) và `install.wim` (Hệ điều hành chính), giúp nhận diện ổ cứng NVMe SSD ngay lập tức mà không cần copy driver thủ công vào USB.
</details>

<details>
<summary><b>2. Microsoft Store được cài đặt vào Windows 11 LTSC như thế nào?</b></summary>
Các bản ISO LTSC gốc của Microsoft không có sẵn Store. Khi build bằng `ltsc-builder.ps1`, script sẽ tự động bật các dịch vụ bản quyền nền (`ClipSVC`, `AppXSvc`, `InstallService`, `LicenseManager`) và lập lịch chạy lệnh `wsreset.exe -i` ở lần khởi động đầu tiên để Windows tự động kích hoạt và tải Microsoft Store chính chủ về máy.
</details>

<details>
<summary><b>3. Tại sao chọn Gaming preset mà Windows Defender vẫn chưa bị xóa?</b></summary>
Hồ sơ `gaming` preset được thiết kế để giữ lại Windows Defender nhưng giới hạn mức ngốn CPU xuống `25%` và tối ưu độ trễ chuột. Nếu bạn muốn xóa hẳn Defender khi chọn Gaming preset, hãy truyền thêm tham số `-RemoveDefender yes` khi chạy lệnh.
</details>

---

## 🤝 Lời cảm ơn & Ghi danh

- Ý tưởng Tiny11 gốc thuộc về tác giả **ntdev** (`@ntdevlabs`).
- Tự động hóa bộ công cụ, tích hợp MS Store LTSC, driver IRST và tối ưu hóa hệ thống phát triển cho **Tiny Auto Builder**.
