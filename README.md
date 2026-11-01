# ExtendDesk

Ứng dụng Swift iOS lấy cảm hứng từ desktop mode của XeOS/DeX. Dành cho iPhone 15 và iPad mini 6 kết nối màn hình ngoài. Tên, mã nguồn và UI riêng; không sử dụng mã nguồn/tài nguyên độc quyền của XeOS.

**Trạng thái: bản alpha 0.3, chưa được build bằng Apple SDK hoặc chạy trên thiết bị thật.** Máy phát triển hiện tại là Windows, không có Xcode. Kiểm tra cú pháp không chứng minh app biên dịch hay hoạt động. Xem `docs/STATUS.md` để biết phần đã viết, giới hạn và phần chưa làm. Thay đổi mới ở `docs/UPGRADE-0.3.md`; bản xem thiết kế trên Windows ở `preview/desktop.html`.

## Build trên Mac

1. Cài Xcode đầy đủ và mở một lần để cài platform iOS. Chọn Xcode trong Settings → Locations → Command Line Tools.
2. Chép toàn bộ thư mục này sang Mac hoặc đồng bộ bằng Git.
3. Cài [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
4. Trong Terminal ở thư mục dự án:

```bash
bash scripts/build-mac.sh
```

Lệnh tạo `ExtendDesk.xcodeproj`, build iOS Simulator và app Mac đồng hành. Sau đó mở `ExtendDesk.xcodeproj`, chọn target ExtendDesk → Signing & Capabilities → Team của bạn. Đổi bundle identifier nếu cần. Chọn iPhone/iPad đã cắm vào Mac, bật Developer Mode trên thiết bị, rồi Run. Build script không ký app cho thiết bị.

Chạy unit tests trên simulator đã cài:

```bash
xcrun simctl list devices available
bash scripts/test-mac.sh 'platform=iOS Simulator,name=iPhone 16'
```

Có workflow GitHub Actions ở `.github/workflows/apple-build.yml`. Workflow chưa được chạy; cần đặt dự án này ở gốc một repository để GitHub nhận workflow.

## Dùng app

- Chưa cắm màn hình: chọn **Preview** để dùng desktop trực tiếp trên điện thoại/tablet. Chọn **Trackpad** để quay lại.
- Cắm cáp USB-C hỗ trợ video hoặc hub USB-C → HDMI. Màn hình ngoài được scene riêng quản lý; thiết bị hiện bảng điều khiển.
- **Apps**, **Go**, **Windows** mở panel ngay trên desktop. Có lưới ứng dụng, tìm công cụ/site/tệp trong Documents và overview cửa sổ. Gửi từ khóa từ điện thoại, dùng ↑/↓ chọn, Enter mở, Esc đóng. Menu bar có File/Edit/View/Window/Help và Control Center. Dock có icon màu, ứng dụng đang chạy, website ghim, tùy chỉnh kích thước và auto-hide.
- Trackpad: một ngón di chuyển; chạm click; hai ngón cuộn; hai ngón chạm menu ngữ cảnh; giữ rồi kéo trên thanh tiêu đề hoặc góc dưới phải để di chuyển/đổi kích thước cửa sổ.
- Nút đỏ đóng, vàng thu nhỏ, xanh phóng to. Các cửa sổ thu nhỏ xuất hiện trên Dock. Hai nút chia màn hình trên thiết bị đưa cửa sổ đang chọn sang trái/phải.
- Gõ vào trường trên thiết bị và chọn **Send** để gửi đến panel, phần tử web đang chọn, Find hoặc Notes. Bàn phím không tự đóng sau mỗi Send. Có Enter/Backspace. Chuột nhận qua GameController. ⌃Tab đổi tab browser (không có browser thì đổi cửa sổ), ⌘` đổi cửa sổ, ⌘↑ overview, ⌃Space search, ⌘, Settings, ⌃⌘D Show Desktop. Printable hardware keys vẫn cần focus trường nhập trên thiết bị; chưa full raw-key forwarding.
- Trình duyệt có nhiều tab, bookmark strip, popover Downloads với byte/percent và hủy tải. Tối đa 24 tab metadata và 3 WKWebView đang giữ mỗi cửa sổ; khi bị ẩn/background/memory warning còn tab đang chọn. Tab nền bị giải phóng sẽ tải lại URL khi mở lại. Không có giới hạn tổng WKWebView cho mọi cửa sổ; cần đo RAM trên thiết bị.
- Browser có Find (⌘F), zoom theo tab 50–200% (⌘+/⌘−/⌘0), next/previous match. Menu Window có tile nửa/bốn góc/center/fill/restore. Show Desktop không minimize và không gửi text vào cửa sổ đang ẩn.
- Settings có System/Light/Dark, accent, bốn hình nền vector và nhập ảnh từ Files. Desktop hiển thị Downloads và các tệp/thư mục trong `Documents/Desktop`, mở bằng double-click; File → New Desktop Folder tạo thư mục mới.
- Photos chỉ yêu cầu quyền khi chọn Access. Có lưới ảnh, preview và slideshow 3/5/10 giây, tối đa 1000 ảnh gần nhất; không sửa thư viện. Khi ẩn/background, slideshow dừng và không tự phát lại.
- **Web on device** chuyển chính WKWebView đang dùng sang điện thoại để thao tác trực tiếp; **Done** trả lại. Dùng cho đăng nhập, chọn tệp, iframe hoặc hành vi yêu cầu tương tác thật. Không tạo bản sao phiên web.
- Files có sidebar Places, grid/list, sort theo tên/ngày/kích thước, trạng thái loading/error và refresh theo sự kiện. Import sao chép tệp vào app; Mount mở thư mục/iCloud/ổ ngoài do người dùng chọn. Quyền Mount chỉ giữ trong phiên. Menu ngữ cảnh có Copy/Cut/Rename/Share/Delete; nút clipboard dán vào thư mục hiện tại. Tệp trong sandbox đưa vào Trash và có Restore; tệp trên ổ được mount dùng xóa vĩnh viễn có xác nhận. ZIP và đa chọn chưa có.
- PDF, ảnh, văn bản và media có viewer trong cửa sổ Files. PDF có thêm ghi chú và lưu bản sao. Định dạng khác dùng Quick Look trên thiết bị. Mỗi cửa sổ Notes mặc định có tệp riêng trong `Documents/Notes`, có Open/Rename và editor trên thiết bị.

## Chia sẻ qua LAN

Trên thiết bị chọn **Share LAN → Start**, cấp quyền mạng cục bộ, rồi mở địa chỉ được cung cấp trên trình duyệt cùng mạng. Giữ app ở foreground. Stop hoặc background vô hiệu hóa server và token. Mỗi lần Start tạo token mới. JPEG capture được giới hạn 1280×720, dùng chung cache tối đa 4 lần/giây giữa các viewer và encode ngoài main thread. Đây là viewer thử nghiệm, không phải streaming chất lượng production; ảnh WebKit/video có thể không thu được đầy đủ.

Kết nối Mac: mở `MacCompanion/ExtendDeskLink.xcodeproj` sau khi build, chạy ExtendDesk Link trên Mac (macOS 14+), cấp Screen Recording và Accessibility. Start sharing, thay `MAC-LAN-IP` trong URL bằng IP Wi-Fi của Mac, rồi mở URL trong trình duyệt. Để tương tác trực tiếp trên iPhone có thể mở bằng Safari hoặc Web on device. Bản đầu chỉ chia sẻ màn hình chính, click/scroll/nhập văn bản; không truyền âm thanh hay từng cửa sổ riêng.

**LAN transport hiện là HTTP không mã hóa.** Chỉ chủ động bật trên mạng riêng tin cậy. Ai có session URL có thể xem và điều khiển phiên. Không port-forward, không dùng trên Wi-Fi công cộng. Đây là giới hạn cụ thể của bản triển khai, chưa phù hợp phát hành rộng.

## Phát triển trên Windows

```powershell
python -m pip install -r scripts/requirements-dev.txt
python scripts/verify.py
```

Kiểm tra Swift bằng tree-sitter, YAML và cú pháp JavaScript; không thay cho Swift compiler. UIKit/WebKit/ScreenCaptureKit cần Mac để type-check/build. Tài liệu kiểm tra thiết bị: `docs/DEVICE-TESTS.md`.

## Tài liệu kỹ thuật tham chiếu

- [UIKit external display scenes](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display)
- [WKDownload](https://developer.apple.com/documentation/webkit/wkdownload)
- [GCMouseInput](https://developer.apple.com/documentation/gamecontroller/gcmouseinput)
- [XeOS feature reference](https://externaldisplayiphone.com/)
