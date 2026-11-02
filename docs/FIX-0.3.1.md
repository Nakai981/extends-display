# 0.3.1 — sửa capture trong callback Swift và chẩn đoán build

Lỗi compiler do người dùng cung cấp:

```text
error: call to method 'armSlideshow' in closure requires explicit use of 'self' to make capture semantics explicit
```

Nguyên nhân nằm ở callback `requestImage → DispatchQueue.main.async` trong PhotosController. Closure lồng dùng thành viên của controller mà chưa ghi `self.` tường minh. Đã sửa thành `self.armSlideshow()` và ghi rõ capture/access cho các callback PhotoKit khác.

Đồng thời sửa các chỗ cùng kiểu trong Browser Find, wallpaper import/load, Files previews/Trash/Notes, file index và menu callbacks. Capture yếu ở closure lồng dùng alias tường minh `[weak self = self]`; stale-result/generation checks được giữ nguyên.

DesktopSharing không còn worker giữ `self` mạnh rồi capture yếu lại. Tác vụ JPEG chỉ giữ image và completion có weak owner; cập nhật trạng thái quay về main queue. Service được đánh dấu `@MainActor` để khớp nơi sử dụng UIKit.

## Build lại trên Mac

Chép mã nguồn mới vào thư mục Mac đang build, ít nhất `Sources/`, `scripts/` và `project.yml`. Script sinh lại Xcode project qua XcodeGen, không cần sửa project bằng tay:

```bash
cd /Users/thuthao/Downloads/extends-display
bash scripts/build-mac.sh
```

Mỗi target lưu log riêng vào `build/logs/`. Khi thất bại, script giữ đúng exit code và in các block `error:` thay vì chỉ phần `BUILD FAILED`. Có thể chạy lại phần trích lỗi cho một log cũ:

```bash
python3 scripts/build_diagnostics.py build/logs/TEN-LOG.log
```

## Kiểm tra đã chạy

- 7 Python tests pass: phân biệt warning/error, giữ context, loại trùng và mô phỏng exit status/log của build wrapper cho iOS fail, Mac fail và success.
- Parser 29 tệp Swift, YAML, target paths, JavaScript behavior tests và syntax preview pass.
- Các test build wrapper dùng **mock Xcode tools**; không phải native build thành công. Máy hiện tại vẫn không có Apple SDK/Xcode, nên compiler và XCTest cần xác nhận trên Mac.
