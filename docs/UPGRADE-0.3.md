# ExtendDesk 0.3 — desktop lấy cảm hứng từ Mac

Đợt nâng cấp chủ động này tập trung vào một môi trường làm việc nhất quán: menu có tác dụng, bố trí cửa sổ, cá nhân hóa và công cụ ảnh/web. Không sử dụng icon/hình nền độc quyền của Apple. Mã đã được kiểm tra tĩnh trên Windows; chưa có Xcode build, XCTest hoặc kiểm chứng thiết bị.

## Giao diện và thao tác

- Menu bar material có tên ứng dụng đang focus, File/Edit/View/Window/Help, tìm kiếm, Control Center và ngày giờ. Ở cửa sổ nhỏ, một số menu nằm trong menu ExtendDesk để tránh tràn chiều ngang.
- Menu ngữ cảnh riêng cho desktop, icon tệp, Dock và header cửa sổ. Menu và launcher hỗ trợ pointer, Enter/Esc và chọn bằng mũi tên. Native right-click trong nội dung vẫn do WebKit/UICollectionView xử lý; remote trackpad đi qua routing rõ ràng.
- Desktop có thư mục Downloads và nội dung thực của `Documents/Desktop`, tải metadata nền. Icon mở bằng double-click; menu có Open/Reveal/Rename. File → New Desktop Folder tạo thư mục thật, không phải shortcut giả.
- Dock material có kích thước tùy chọn và auto-hide. Khi auto-hide, pointer ở mép dưới làm Dock hiện; hit-testing ưu tiên Dock để không click xuyên vào cửa sổ bên dưới.
- Cửa sổ tile nửa trái/phải, bốn góc, center/fill và Restore Size. Geometry trước tile được lưu; nút chia đôi trên điện thoại dùng cùng một luồng.
- Show Desktop ẩn tạm cửa sổ, không sửa trạng thái minimized. Mở/focus ứng dụng đưa chúng trở lại. Gửi text bị chặn khi nội dung đang ẩn.

## Cá nhân hóa

- System/Light/Dark và sáu accent color.
- Bốn cảnh quan vector nguyên bản và hình nền nhập từ Files. ImageIO giới hạn cạnh dài 2560 px; ảnh được lưu riêng trong Application Support, có cache và request generation guard.
- Settings dạng sidebar: Appearance, Desktop & Dock, Input, Browser & Storage, About. Có Dock size/auto-hide, Reduce Motion, pointer speed, quản lý website ghim, xóa website data có xác nhận và reset appearance.
- Control Center chỉ chỉnh các tùy chọn app có thể thực hiện. Không dựng các nút giả để điều khiển Wi-Fi, độ sáng hệ thống hoặc các app iOS khác.

## Công cụ mới/cải thiện

- Photos: xin quyền khi người dùng bấm Access, hỗ trợ limited/denied; lấy tối đa 1000 ảnh gần nhất, thumbnail 256 px, prefetch giới hạn, preview tối đa 2048 px, progress khi tải ảnh iCloud.
- Slideshow có 3/5/10 giây, next/previous/play/pause và chế độ ảnh phủ phần nội dung cửa sổ. Minimize/Show Desktop/background sẽ dừng; khôi phục không tự phát lại.
- Browser có Find in Page, next/previous match và zoom theo tab 50–200%, lưu qua lần mở app. Số lượng kết quả trong main-document text được ghi rõ phạm vi; native WebKit find là chỉ báo có/không có kết quả.
- File menu, View menu và keyboard dùng chung `BrowserCommand`, tránh mỗi luồng xử lý một kiểu. Đóng tab cuối bằng ⌘W đóng cửa sổ browser.

## Phím tắt

| Phím | Tác dụng |
|---|---|
| ⌘N / ⌘T | Browser window / tab mới |
| ⌘W / ⇧⌘W | Đóng tab hoặc công cụ / đóng cửa sổ |
| ⌘F / ⌘R | Find / reload trang |
| ⌘[ / ⌘] | Back / Forward |
| ⌘+ / ⌘− / ⌘0 | Zoom in / out / actual size |
| ⌃Tab / ⇧⌃Tab | Tab kế / trước; không có browser thì đổi cửa sổ |
| ⌘` / ⌘↑ | Cửa sổ kế / overview |
| ⌘M / ⌘, | Minimize / Settings |
| ⌃Space / ⌘L | Search |
| ⌃⌘D | Show Desktop |
| ↑ ↓ / Enter / Esc | Chọn / mở / đóng panel |

Printable text và IME vẫn đi qua trường nhập trên thiết bị hoặc Web on device. Đây chưa phải full hardware-key forwarding vào mọi website; cần kiểm tra responder chain và từng bàn phím trên thiết bị.

## Cần kiểm chứng và còn thiếu

- Xcode type-check, visual QA cho cả light/dark, hot-plug, pointer/keyboard, PhotoKit permissions/iCloud, hiệu năng và memory pressure.
- Photos hiện chỉ ảnh: chưa albums, video, editing hoặc share. Không ghi/sửa thư viện người dùng.
- Desktop folder không dùng file alias/security bookmark cho mọi vị trí bên ngoài sandbox; nội dung mở từ Files được mount vẫn tuân theo giới hạn phiên.
- Chưa PDF highlight/sign, ZIP, đa chọn, SSH, recording, TLS/pairing hoặc streaming audio/video. Các hạn chế WebKit/trusted activation vẫn tồn tại.
- Bản HTML trong `preview/` là bản xem thiết kế và tương tác trên Windows, không phải ảnh chụp hay bản build iOS.

## Kết quả kiểm tra thực hiện trong lượt này

- Parser qua 29 tệp Swift, 3 YAML, target paths; Node behavior tests cho viewer/browser và syntax check script preview đều pass.
- Preview HTML chạy bằng headless Chrome: 18 assertion tương tác pass, đã xem ảnh ở 1280×800 và 800×600. `preview/desktop-preview.png` là ảnh của preview này.
- XCTest đã bổ sung cho tiling, migration restoreFrame/tab zoom, chọn tab, appearance và slideshow model; chưa được thực thi.
- Không có kết quả native compiler, ảnh native UI hoặc benchmark iOS. Cần Mac để hoàn tất các kiểm tra đó.
