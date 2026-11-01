# ExtendDesk 0.2 — giao diện, tính năng và giảm công việc lặp lại

Đã triển khai mã trên Windows. Không có kết quả đo fps/RAM/độ trễ và chưa có Xcode build hoặc thiết bị thật; không khẳng định nhanh hơn theo một tỷ lệ cụ thể.

## Trải nghiệm desktop

- Launcher dạng lưới, tìm kiếm ứng dụng/site/tệp và overview cửa sổ nằm ngay trên desktop. Routing pointer/scroll/text làm việc với panel, không phụ thuộc UITouch giả.
- Dock icon màu, trạng thái đang chạy, ghim website, khôi phục ứng dụng hiện có, tooltip và cuộn khi thiếu chỗ.
- Thanh tiêu đề gọn, nút giao thông có vùng bấm lớn hơn, border focus và shadow có shadowPath.
- Cửa sổ bị giới hạn trong canvas sau kéo/resize hoặc đổi kích thước màn hình. Panel cũng giới hạn theo bounds.
- Controls điện thoại có scroll và keyboard layout guide, giữ bàn phím sau Send; pointer pan không phải chờ long press thất bại.

## Browser và Files

- Browser có tab strip, bookmark bar và Downloads có progress/cancel/history/open folder. 24 tab metadata và 3 warm WKWebView mỗi cửa sổ, trim về selected tab khi ẩn/background/áp lực bộ nhớ. Giữ selected DOM khi chuyển scene, tab nền bị evict tải lại từ URL.
- WebKit popup trả đúng configuration được yêu cầu; không xem điều này là đã kiểm thử OAuth của từng website.
- Files có sidebar, grid/list, sort, I/O nền, cancel/stale-result guard, filesystem watcher và refresh debounce. Không còn timer quét mỗi 3 giây.
- Trash/restore trong sandbox có rollback manifest và kiểm tra đích trùng; ổ ngoài vẫn xóa vĩnh viễn sau xác nhận. Clipboard file trong phạm vi một FilesController.
- Preview ảnh downsample 2048 px; text viewer đọc tối đa 2 MiB. Notes gom thao tác gõ và ghi atomic trên utility queue; flush khi đóng/background hoặc trước đổi tệp.

## Công việc được loại bỏ hoặc giới hạn

| Luồng | Thay đổi |
|---|---|
| Click cửa sổ đang focus | Không đổi thứ tự, không phát update/lưu phiên thừa |
| Thay đổi Workspace | Notification gom theo main-loop; lưu phiên debounce 400 ms, flush khi background |
| Render desktop | Chỉ cập nhật wallpaper khi đổi; Dock theo signature; z-order khi thứ tự đổi; layout khi geometry thay đổi |
| Cắm/rút màn hình | Pool controller theo window ID, detach/reparent có kiểm tra ownership; không dựng WKWebView từ URL cho selected tab đang giữ |
| Tìm tệp | Một index job nền tại một thời điểm, tối đa 3000 mục; query mới dùng callback cuối cùng; cache 20 giây, invalidation theo sự kiện |
| Overview | Tối đa 12 thumbnail 220×110, các mục còn lại dùng biểu tượng; tối đa 60 mục trong panel |
| LAN viewer | Một capture in-flight; cache 250 ms dùng chung; ảnh tối đa 1280×720 ở scale 1; JPEG encode ngoài main |
| Vòng đời | Stop sharing khi background; guard generation khi start/stop; mouse disconnect kết thúc kéo |

## Kiểm tra

- `python scripts/verify.py`: parser Swift, YAML, target paths và Node behavior tests cho viewer/browser scripts.
- XCTest mới bao gồm tab lifecycle/persistence, download fraction, geometry, workspace restore, file copy/move guards, Trash/restore và buffered Notes writer. Chưa chạy do không có Xcode.
- Cần thực hiện `docs/DEVICE-TESTS.md`, đặc biệt hot-plug giữ DOM, 3 warm tabs, search/launcher bằng pointer, ký tự tiếng Việt, long press drag, Trash restore và viewer background/start-stop.

## Giới hạn còn lại

Chưa full raw-key/IME forwarding; chưa ZIP, multi-select, persistent mount permissions, PDF highlight/sign, Photos/slideshow, SSH, screenshot recording, TLS/pairing hoặc streaming video/audio. DOM events vẫn không phải trusted input và không xuyên cross-origin iframe. Một primary device scene điều khiển desktop; system window thứ hai chỉ hiện thông báo, không lấy controller pool.

Mức độ giống XeOS mới được đánh giá bằng cấu trúc UI và tính năng đã viết; cần render/chạy thật để kiểm tra hình thức và hành vi.
