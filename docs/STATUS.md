# Phạm vi và trạng thái

Không đánh dấu một tính năng là đã kiểm chứng chỉ vì có mã nguồn. Tất cả tính năng dưới đây hiện mới ở mức **đã triển khai mã, cần build và kiểm tra trên Mac/thiết bị**.

| Nhóm | Đã triển khai | Giới hạn/chưa có |
|---|---|---|
| Màn hình | Scene ngoài riêng, thiết bị làm điều khiển, preview nội bộ khi chưa kết nối | Chưa thử hot-plug, AirPlay, rotation hay các tỉ lệ màn hình. Scene accessory của iOS 27 chưa tích hợp; bản này hướng đến scene lifecycle iOS 16–26. |
| Desktop | Menu bar/context menus, vật liệu blur, Dock auto-hide/size, icon tệp Desktop, Show Desktop, tile nửa/bốn góc/center/restore, launcher/search/overview | Chưa có Spaces, kéo tệp giữa cửa sổ; thumbnail WebKit có thể thiếu nội dung. File icon giới hạn Documents/Desktop và Downloads |
| Appearance | System/Light/Dark, accent, bốn wallpaper vector và ảnh riêng, Settings sidebar, Control Center, Reduce Motion | Chưa visual QA trên thiết bị; chỉ một số animation Dock, không giả lập cài đặt hệ thống ngoài phạm vi app |
| Browser | Tab/cửa sổ, bookmark strip, downloads progress/cancel/history, Find, zoom theo tab, JS dialogs và popup configuration | Chưa ad blocker, nhập bookmark/mật khẩu, tab groups; chưa kiểm thử OAuth. Find count chỉ main-document text có giới hạn. Tối đa 3 warm WKWebView mỗi cửa sổ |
| Input | Trackpad, kéo/resize cửa sổ, scroll, gửi text, raw mouse và vài phím tắt | DOM click/text chỉ best effort; không phải trusted events, không điều khiển cross-origin iframe. Bàn phím chưa có đầy đủ raw key/modifier forwarding. Không cam kết cloud gaming/DRM/camera/mic tương thích. |
| Web fallback | Chuyển chính WKWebView sang thiết bị để tương tác native rồi trả lại | Trong lúc chuyển, nội dung web không nằm trên màn hình ngoài |
| Files | Sidebar/grid/list/sort, async I/O và refresh theo sự kiện, copy/cut/paste, rename, share, Trash/restore cho sandbox | Chưa ZIP/unzip, đa chọn, empty Trash, bookmark bảo mật lưu qua lần khởi động; ổ ngoài vẫn xóa vĩnh viễn có xác nhận |
| Tài liệu/media | PDFView có ghi chú và lưu bản sao, ảnh, text, AVPlayer; Quick Look cho định dạng khác | Chưa highlight/ký PDF; Office preview trên thiết bị, chưa chỉnh sửa Office; media remote controls chưa đầy đủ |
| Photos | Authorized/limited/denied, tối đa 1000 ảnh, thumbnail/preview giới hạn, iCloud progress, slideshow và full-window image | Chưa albums/video/editing/share; không sửa thư viện. Chưa kiểm chứng PhotoKit trên thiết bị |
| Notes | Tệp riêng mỗi cửa sổ, autosave debounce và I/O nền, flush trước Open/Rename, editor trên thiết bị | Nếu chủ động mở cùng một tệp ở hai cửa sổ, bản ghi cuối có thể ghi đè; chưa có conflict resolution |
| Calculator/Settings | Tính cơ bản; Settings appearance/Dock/input/browser storage/about, xóa website data có xác nhận | Calculator tính theo thứ tự bấm, không theo ưu tiên biểu thức; xóa browser data ảnh hưởng mọi cửa sổ |
| Lưu phiên | Geometry, tab metadata/selection, bookmarks; controller pool giữ selected web DOM qua scene transfer | Không lưu DOM/back history qua khởi động app hoặc tab nền bị evict; mount chỉ trong phiên |
| LAN viewer | Token mỗi phiên, giới hạn request/kết nối, JPEG cache 4fps/1280×720 và encode nền, click/scroll/text, stop khi background | Chưa TLS, audio, WebRTC, video hardware encoding, drag trong client, hardening cho production. UIKit snapshot có thể không thu đủ WebKit/video/protected content. |
| Mac Link | App macOS 14+, ScreenCaptureKit ảnh màn hình chính, click/scroll/text qua Accessibility | Chưa chọn màn hình/cửa sổ, drag, audio, TLS, pairing, notarization, auto discovery |

## Các mốc còn phải hoàn tất để phát hành

1. Chạy build iOS + macOS, sửa lỗi compiler/API nếu có; chạy XCTest và lưu kết quả.
2. Kiểm tra toàn bộ danh sách DEVICE-TESTS trên cả iPhone 15 và iPad mini 6.
3. Kiểm chứng kiến trúc tương tác ngoài, hiệu năng WebKit và giới hạn bộ nhớ trên thiết bị; điều chỉnh nếu cần.
4. Hoàn thiện các tính năng thiếu trong bảng theo độ ưu tiên. Không gọi bản này là clone đầy đủ XeOS.
5. Thay LAN preview bằng transport có mã hóa, pairing và pipeline capture/streaming ổn định trước phát hành rộng.
6. Bổ sung icon/branding, localization, accessibility, privacy policy, App Store privacy declarations đúng hành vi thực tế, TestFlight và kiểm tra crash/thermal/memory.
7. Ký và phát hành bằng tài khoản Apple Developer của chủ dự án. Chưa có build archive, TestFlight hay App Store submission nào được thực hiện.
