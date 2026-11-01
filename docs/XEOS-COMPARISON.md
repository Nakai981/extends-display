# Đối chiếu XeOS — 02/11/2026

Đây là mốc đối chiếu **trước đợt nâng cấp 0.2**. Một số khoảng cách trong bảng đã được triển khai sau đó; xem [thay đổi 0.2](UPGRADE-0.2.md), [thay đổi 0.3](UPGRADE-0.3.md) và [trạng thái hiện tại](STATUS.md).

## Cách đánh giá

Đã xem website, changelog App Store và các ảnh/animation giới thiệu. Phía ExtendDesk được kiểm tra bằng mã nguồn hiện tại, không phải ảnh chụp app đang chạy. Chưa build Xcode hay thử XeOS trực tiếp nên không kết luận về độ mượt, độ trễ, độ ổn định hoặc tỉ lệ giống nhau.

### Giao diện quan sát được

| Khu vực | XeOS trong ảnh giới thiệu | ExtendDesk trong mã hiện tại | Việc cần làm |
|---|---|---|---|
| Desktop | Hình nền ảnh, shortcut tệp bên trái | Ba gradient, chưa có shortcut desktop | Chọn ảnh nền, shortcut tệp/thư mục/site, bố cục lưu được |
| Dock | Icon màu, nhiều công cụ | SF Symbols trắng, năm công cụ cố định và cửa sổ thu nhỏ | Icon riêng đồng nhất, trạng thái đang chạy, ghim site, tooltip và menu ngữ cảnh |
| Cửa sổ | Thanh tiêu đề gọn, nội dung chiếm phần lớn diện tích | Header 38 pt, nền tối, border theo focus | Thiết kế token chung, bóng đổ, hit area lớn hơn phần nút nhìn thấy, animation, quản lý focus |
| Launcher | Lưới ứng dụng có ô tìm kiếm trên desktop | Action sheet trên thiết bị | Panel lưới ngay trên desktop, hỗ trợ pointer và keyboard |
| Search | Panel kết quả có phân nhóm | Alert URL/search, mở Google | Tìm công cụ, website và tệp trong phạm vi được cấp quyền; điều hướng kết quả bằng phím |
| Overview | Các cửa sổ thu nhỏ trên nền desktop mờ | Grid thumbnail trong modal trên thiết bị | Overview trên màn hình ngoài, chọn/đóng/restore trực tiếp |
| Browser | Có hàng tab và thanh bookmark | Mỗi window một WKWebView, không có tab strip/bookmark bar | Tab model, favicon, trạng thái tải, tab shortcuts, bookmark manager |
| Files | Sidebar vị trí, lưới tệp, toolbar | Table tệp, preview bên cạnh, nút Mount | Sidebar, grid/list, breadcrumb, selection, menu thao tác thống nhất |
| Downloads | Popover riêng | Dòng trạng thái tải xong/lỗi | Download center, tiến trình, trạng thái, mở thư mục và quản lý lịch sử |
| Settings | Chưa kiểm tra đủ ảnh để đánh giá bố cục | Ba nhóm tùy chọn | Chia nhóm Display/Input/Browser/Storage/Sharing/Privacy/About, có trạng thái và trợ giúp |

Nguồn hình ảnh:

- [Desktop và Dock](https://externaldisplayiphone.com/anim/hero-desktop.webp)
- [Cửa sổ](https://externaldisplayiphone.com/anim/windows-base.webp)
- [Files](https://externaldisplayiphone.com/anim/files-icloud.webp)
- [Launcher](https://externaldisplayiphone.com/anim/apps-drawer.webp)
- [Search](https://externaldisplayiphone.com/anim/spotlight.webp)
- [Downloads](https://externaldisplayiphone.com/anim/downloads-popover.webp)
- [Overview](https://externaldisplayiphone.com/anim/windows-overview.webp)

### Khoảng cách tính năng

Website công bố ZIP/giải nén và Trash; highlight/ký PDF; thư viện ảnh/slideshow; nhập bookmark/mật khẩu; autofill; chia sẻ từng cửa sổ Mac hoặc cả màn hình; web meetings và cloud gaming. Các thông tin này là tuyên bố của nhà phát triển, chưa được kiểm chứng thực tế. [Nguồn](https://externaldisplayiphone.com/)

ExtendDesk còn thiếu hoặc mới có một phần:

- Files: ZIP/unzip, Trash/restore, đa chọn, bookmark quyền thư mục qua lần mở app.
- PDF: mới thêm note và save copy; chưa highlight, ký tay, toolbar thuyết trình.
- Photos: chỉ mở ảnh dạng tệp; chưa duyệt thư viện hệ thống hoặc slideshow.
- Browser: chưa có import bookmark/password, autofill workflow được kiểm thử hoặc ad blocker. Không nên tự xây kho mật khẩu trước khi có yêu cầu và thiết kế bảo mật riêng.
- Meetings/gaming: có WKWebView nhưng chưa kiểm chứng camera/mic, fullscreen, controller, DRM, pointer lock hay tương thích từng dịch vụ. Không xem việc mở được URL là đã hỗ trợ dịch vụ.
- Mac Link: chỉ màn hình chính, JPEG tối đa khoảng 4 fps; thiếu chọn cửa sổ, audio, drag, clipboard và transport có mã hóa.
- Bàn phím: có vài shortcut và Send text; chưa đầy đủ keydown/up/modifiers/IME/selection/copy-paste.
- Chuyển scene: dựng lại browser từ URL, mất DOM/back history; cần giải quyết tính liên tục của phiên trước khi mở rộng số công cụ.

### Những điểm mới cần đưa vào backlog

Changelog App Store được kiểm tra lần này còn công bố: SSH Terminal và VSCode Remote Tunnels; lịch sử clipboard/lọc Smart Search; chụp và quay màn hình ngoài; web-app file handling/default apps; display scaling/frame rate/status bar; cải thiện IME và diagnostics chuột/bàn phím. Trang mô tả còn nêu ad blocker và onboarding kết nối. [Nguồn App Store](https://apps.apple.com/us/app/external-display-desktop-xeos/id6758286241)

Phía ExtendDesk chưa có các module này. Snapshot hiện tại chỉ là ảnh xem trước, không phải screenshot manager hoặc screen recorder. LAN viewer cũng không thay thế trình quay màn hình.

## Thứ tự phát triển đề xuất

**P0 — xác thực nền tảng trước:** build iOS/macOS, hot-plug trên cả hai thiết bị, nhập liệu/IME, focus, trusted-input fallback, bộ nhớ và giữ phiên khi chuyển scene. Chỉ đánh dấu hoàn tất khi có kết quả thiết bị.

**P1 — làm đúng trải nghiệm desktop:** bộ màu/kích thước/icon chung; Dock có ghim và trạng thái; launcher/search/overview trên màn hình ngoài; Files sidebar/grid; browser tabs và download center. Đây là nhóm tạo khác biệt rõ nhất về giao diện và cách sử dụng.

**P2 — hoàn thiện công việc hằng ngày:** Trash/restore, ZIP, đa chọn tệp, PDF highlight/sign/presentation, Photos/slideshow, onboarding/diagnostics, site data controls, dark/light mode, display scaling và shortcut help. Đo hiệu năng trước khi cho tùy chỉnh frame rate.

**P3 — mở rộng kết nối:** transport mã hóa/pairing, stream hiệu quả, chọn màn hình/cửa sổ Mac, audio, capture/recording. Sau đó cân nhắc SSH/SFTP bằng thư viện phù hợp và xác minh host key; clipboard history phải opt-in, có xóa lịch sử và tránh thu mật khẩu.

Không sửa giao diện hoặc thêm tính năng trong lượt đối chiếu này. Đây là báo cáo làm đầu vào cho các đợt triển khai kế tiếp.
