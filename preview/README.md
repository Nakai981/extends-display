# Desktop design preview

Open `desktop.html` in Chrome, Edge, Firefox, or Safari. It is a self-contained, offline **design preview**, not an iOS build or a test of UIKit/WebKit/external-display behavior. The visible badge identifies that distinction throughout.

No external assets, fonts, libraries, network requests, or backend are used. The wallpaper is original inline vector art; Photos uses CSS-generated landscape samples. Files are in-memory samples and never touch your actual filesystem. Notes and settings last for this page session.

Try these interactions:

- Open/focus apps from the Dock; right-click a Dock app for a new window.
- Drag title bars, resize from the lower-right corner, and use the red/yellow/green window controls.
- Use menu-bar menus, right-click window title bars, tile windows, or reveal the desktop.
- Open the launcher, search apps/sample files, or view all windows.
- Change light/dark appearance, accent, wallpaper, Dock size, auto-hide and reduced motion in Settings.
- Switch Files between grid/list, change Places, create a sample folder, rename/copy/trash/restore sample items.
- Add/switch browser tabs, enter local sample text in the address field, or find text in the sample article.
- Edit a note, use Calculator, or play/pause the generated Photos slideshow.

Keyboard shortcuts use Ctrl on Windows/Linux or Command on macOS: Space for search, N for a browser window, T for a tab, M to minimize, W to close, F to find, comma for Settings. Escape dismisses overlays. Browsers may reserve some shortcuts when opened as a normal tab.

The preview approximates the native v0.3 direction. It does not reproduce native permissions, photo libraries, actual downloads, browser engines, screen sharing, device input routing, or iOS performance. Validate those using Xcode and the device checklist.

`desktop-preview.png` is a headless-Chrome screenshot of this design preview at 1280×800. It is not an iOS screenshot. The preview was also visually checked at 800×600, and 18 browser interaction assertions passed during this implementation session.
