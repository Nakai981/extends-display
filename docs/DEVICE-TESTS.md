# Kiểm tra trên Mac và thiết bị

Chưa chạy các bước này. Ghi lại Xcode/iOS/iPadOS/macOS, thiết bị, adapter, độ phân giải, expected/actual và log lỗi.

- [ ] `bash scripts/build-mac.sh`: cả hai target build thành công.
- [ ] `bash scripts/test-mac.sh '<destination>'`: toàn bộ XCTest pass.
- [ ] Mở app không cắm màn hình; Preview mở desktop, các công cụ hoạt động bằng touch.
- [ ] Cắm/rút/cắm lại màn hình khi app đang mở; chỉ một desktop hoạt động, không nhân đôi phiên web.
- [ ] Khởi chạy khi đã cắm màn hình; background/foreground; khóa/mở thiết bị; màn hình ngoài không giữ nội dung nhạy cảm khi app không hoạt động.
- [ ] Hai cửa sổ web: click link, back, search tiếng Việt, scroll nested div, nhập text, submit, iframe.
- [ ] Web on device: giữ đúng URL/cookie/DOM hiện tại, thao tác upload/login và Done trả WKWebView về đúng cửa sổ.
- [ ] Dialog JS alert/confirm/prompt; popup/new window; link tải tệp và response download.
- [ ] Chuột Bluetooth/USB: con trỏ đúng hướng, click, phải, scroll, drag tiêu đề, resize; không click thừa sau kéo.
- [ ] Trackpad: click, hai ngón scroll/context, long press drag/resize, cancel gesture.
- [ ] Bàn phím: shortcuts và nhập tiếng Việt/IME trên thiết bị; trường password không bị log.
- [ ] Minimize, restore, close, maximize, snap; cửa sổ không mất khỏi màn hình sau đổi độ phân giải.
- [ ] Import tệp, Mount iCloud/SSD, tên Unicode, rename trùng tên, không ghi được, xóa hủy/xác nhận.
- [ ] PDF nhiều trang, ảnh lớn, video/audio local, text lỗi encoding, Office Quick Look, share sheet trên iPad.
- [ ] Notes autosave, đóng/mở app; bookmarks và geometry được phục hồi.
- [ ] Launcher/search/overview hiện trên màn hình ngoài, pointer chọn được; Send nhập từ khóa, Enter mở kết quả, Esc đóng; tìm tệp mở đúng thư mục/preview.
- [ ] Dock restore ứng dụng hiện có, ghim website, running dots và cuộn khi nhiều mục.
- [ ] Mở tab thứ tư, đổi lại tab cũ; selected DOM/back history còn khi hot-plug; tab nền bị evict tải lại URL; background/memory warning trim còn selected.
- [ ] Download center có byte/percent, hủy tải, lịch sử, Open Downloads; đóng tab không làm mất bản ghi tải xuống.
- [ ] Files grid/list/sort/sidebar, thư mục lớn không chặn pointer; chuyển nhanh thư mục không áp dụng kết quả cũ; Trash/restore không ghi đè tệp trùng tên.
- [ ] Notes gõ nhanh rồi đóng/background/Open/Rename giữ nội dung mới nhất; Files tự refresh theo sự kiện.
- [ ] Nhiều viewer cùng lúc dùng cache capture; background/Start/Stop nhanh không để server báo running sai; mở system window thứ hai không lấy content của cửa sổ chính.
- [ ] Light/Dark/System và accent cập nhật menu/header/Dock/panel/browser/downloads; reset appearance không quay lại preset legacy; custom wallpaper chỉ lưu bản downsample.
- [ ] Dock auto-hide hiện khi pointer sát mép dưới, click không xuyên vào cửa sổ full desktop; resize/rotation khi Dock ẩn không đổi vị trí reveal.
- [ ] File/View/Window menu bằng chuột và phím; native right-click trong web/Files không bị xử lý hai lần; remote right-click vẫn đến nội dung.
- [ ] Tile trái/phải/bốn góc/center/fill/restore, Show Desktop/restore không làm đổi minimized hoặc gửi text đến trang ẩn.
- [ ] Desktop double-click/Open/Reveal/Rename và New Folder tạo đúng nội dung Documents/Desktop; nhiều icon không chồng ra ngoài bounds.
- [ ] Browser Find next/previous/close và zoom 50–200% giữ theo tab qua relaunch; Find count ghi đúng phạm vi, iframe không làm count giả chính xác.
- [ ] ⌘W đóng tab/cuối cùng đóng window, ⇧⌘W đóng window; ⌃Tab đổi tab, ⌘` đổi window; mũi tên/Enter/Esc chọn panel từ thiết bị.
- [ ] Photos chưa cấp quyền không tự bật prompt; Access xin quyền, denied/limited/empty đúng giao diện; limited picker chỉ mở khi bấm; iCloud failure/cancel không treo spinner.
- [ ] Photos slideshow 3/5/10 giây, pause khi ẩn/background, không tự phát lại; callback đến muộn không tải ảnh hoặc chạy timer khi app inactive.
- [ ] LAN: cấp/từ chối permission, sai token trả 401, unknown path 404, malformed/oversized request bị chặn, Stop ngắt client, Start đổi token.
- [ ] Viewer web: click/scroll/text đúng tọa độ khi browser resize; ảnh WebKit và video có hiển thị hay không.
- [ ] Mac Link: permission denied/granted, screenshot màn hình chính, click/scroll/Unicode text, Stop ngắt truy cập.
- [ ] Mở nhiều website nặng, kiểm tra RAM, nhiệt, giật, cảnh báo memory; không khẳng định số cửa sổ không giới hạn.

Điều kiện tối thiểu cho bản alpha: build và tests pass; external desktop + browser + native fallback hoạt động trên cả hai thiết bị; không mất dữ liệu khi thao tác tệp; mọi hạn chế được ghi đúng trong hướng dẫn.
