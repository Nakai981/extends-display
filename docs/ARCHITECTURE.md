# Kiến trúc

```text
DeviceSceneDelegate → DeviceController
                     ├─ trackpad / text / shortcuts / LAN controls
                     └─ local DesktopController (preview khi không có màn hình ngoài)

ExternalSceneDelegate → DesktopController
                        ├─ menu / Dock / pointer / window manager
                        └─ DesktopWindow → Browser / Files / Photos / Notes / Calculator / SystemSettings

Workspace → records + focus + bookmarks + preferences → UserDefaults
Documents → Downloads / Notes / imported files

DesktopSharing → LocalHTTPServer → token-authenticated JPEG viewer + input
Mac ExtendDesk Link → LocalHTTPServer → ScreenCaptureKit + CGEvent
```

`Workspace` là model dùng chung, gom notification theo main-loop và debounce persistence 400 ms. Scene ngoài được ưu tiên để nhận điều khiển. Controller pool giữ một content controller theo window ID, được detach/reparent khi chuyển scene với ownership guard. Selected WKWebView đang giữ không bị dựng lại từ URL khi chuyển scene. Controller chỉ giải phóng khi đóng cửa sổ; các tab nền có thể bị evict riêng. Chỉ một device scene điều khiển pool; system window thứ hai không tạo controller mới.

Mỗi desktop window là một container UIKit. Trạng thái model lưu geometry chưa maximize; maximize dùng bounds canvas hiện tại. Thứ tự records là z-order. Dock/wallpaper/layout dùng signature hoặc geometry diff. Launcher, search và overview là panel desktop có pointer/text/scroll routing riêng. Index tên tệp chạy nền, một job tại một thời điểm, giới hạn 3000 mục. GameController nhận raw mouse chỉ khi desktop ngoài tồn tại, tránh trùng xử lý native trên preview nội bộ.

DesktopMenuView xử lý menu bar/context bằng actions dùng chung với DeviceController. BrowserCommand là luồng thống nhất cho tab/find/zoom/navigation. WindowPlacement sinh geometry và WindowRecord.restoreFrame lưu kích thước trước tile; desktopRevealed là trạng thái tạm không ghi vào phiên. Visible Dock được hit-test trước cửa sổ khi auto-hide cho phép canvas mở rộng xuống dưới.

DesktopPreferences giữ appearance/accent/Dock/wallpaper, notification được gom. WallpaperView vẽ landscape vector gốc, dùng ảnh cache khi được nhập qua picker; ImageIO decode và ghi ảnh chạy ở queue riêng. UI theo trait, CGColor được resolve khi đổi appearance. DesktopIconsView dùng metadata loader và Documents/Desktop, không dùng global filesystem alias.

PhotosController quản lý PhotoKit quyền đọc do người dùng yêu cầu, fetch metadata nền tối đa 1000 ảnh, thumbnail/preview giới hạn và hủy request theo reuse/visibility/generation. Slideshow chỉ chạy khi app active, selected preview đã về và tool còn hiển thị; không có thao tác ghi asset.

External scene thuộc loại noninteractive nên không dựa vào việc phát UITouch giả. Toolbar và tool UI nhận lệnh qua action; browser dùng DOM events và native value setter, chịu giới hạn WebKit, cross-origin và trusted activation. Chế độ Web on device chuyển cùng một WKWebView vào modal native để xử lý các trường hợp này.

File access giới hạn trong sandbox và những URL được document picker cấp quyền. Mount giữ security scope trong vòng đời FilesController. Không lưu security-scoped bookmark. DirectoryLoader chạy serial background, generation guard bỏ kết quả cũ; filesystem watcher và notification kích hoạt refresh debounce. Cut/copy giữ URL trong một FilesController, paste không ghi đè đích. FileTrashStore giới hạn trong sandbox, có manifest và rollback khi ghi manifest thất bại. Notes ghi qua BufferedTextWriter. Chú thích PDF chỉ được lưu khi chọn Save copy.

HTTP server dùng Network.framework, mỗi connection một request, giới hạn buffer 64 KiB, body 32 KiB, tối đa 12 connection, timeout 10 giây. DesktopSharing gom capture in-flight, cache JPEG 250 ms dùng chung và encode trên queue riêng; ảnh scale 1 giới hạn 1280×720. Start/stop dùng generation guard, background tự stop. Không ánh xạ URL vào filesystem. Mọi endpoint cần token mỗi phiên, input POST cần custom header, không cấp CORS. Chưa mã hóa transport.

Mac companion là target độc lập, không sandbox trong bản phát triển vì cần CGEvent. Screen Recording và Accessibility được người dùng cấp trong macOS. Chưa ký Developer ID, hardened runtime hoặc notarize. Client dùng cùng LAN viewer; chưa có remote input drag, full keyboard protocol, audio hay chọn từng cửa sổ.

Kiểm tra Windows chỉ dùng parser/Node và config checks. `CoreTests.swift`, build script và CI phải chạy bằng Xcode để type-check Apple APIs. Thiết bị thật quyết định khả năng đáp ứng về pointer, keyboard, media, hot-plug và hiệu năng.
