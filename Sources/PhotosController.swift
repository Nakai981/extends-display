import UIKit
import Photos
import PhotosUI

/// Permission-gated image gallery. PhotoKit retains asset metadata; only visible
/// thumbnails and one bounded preview are requested. No originals are decoded.
final class PhotosController: ToolController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching, PHPhotoLibraryChangeObserver {
    private let imageManager = PHCachingImageManager()
    private let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let toolbar = UIStackView()
    private let toolbarScroll = UIScrollView()
    private let imageView = UIImageView()
    private let previewSurface = UIView()
    private let message = UILabel()
    private let countLabel = UILabel()
    private let permissionButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var playButton: UIButton!
    private var fullButton: UIButton!
    private var assets: PHFetchResult<PHAsset>?
    private var slideshow = PhotoSlideshow()
    private var previewRequest: PHImageRequestID = PHInvalidImageRequestID
    private var previewGeneration = UUID()
    private var libraryGeneration = UUID()
    private var pendingLibraryRefresh: DispatchWorkItem?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var registered = false
    private var desktopVisible = true
    private var appActive = UIApplication.shared.applicationState == .active
    private var presentationOnly = false
    private var previewing = false
    private var lastCollectionSize = CGSize.zero
    private var access: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    private let thumbnailSize = CGSize(width: 256, height: 256)
    private let fetchQueue = DispatchQueue(label: "extenddesk.photos.fetch", qos: .userInitiated)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        imageManager.allowsCachingHighQualityImages = false
        collection.backgroundColor = .systemBackground; collection.dataSource = self; collection.delegate = self; collection.prefetchDataSource = self
        collection.register(PhotoThumbnailCell.self, forCellWithReuseIdentifier: "photo")
        toolbar.axis = .horizontal; toolbar.spacing = 2; toolbar.alignment = .center
        toolbar.addArrangedSubview(actionButton("square.grid.2x2", title: "Library") { [weak self] in self?.showLibrary() })
        toolbar.addArrangedSubview(actionButton("chevron.left", title: nil) { [weak self] in self?.previousPhoto() })
        toolbar.addArrangedSubview(actionButton("chevron.right", title: nil) { [weak self] in self?.nextPhoto() })
        playButton = actionButton("play.fill", title: "Slideshow") { [weak self] in self?.toggleSlideshow() }
        playButton.accessibilityLabel = "Play or pause slideshow"; toolbar.addArrangedSubview(playButton)
        fullButton = actionButton("arrow.up.left.and.arrow.down.right", title: nil) { [weak self] in self?.togglePresentation() }
        fullButton.accessibilityLabel = "Toggle full-window photo"; toolbar.addArrangedSubview(fullButton)
        toolbar.addArrangedSubview(actionButton("timer", title: nil) { [weak self] in self?.chooseInterval() })
        toolbar.addArrangedSubview(actionButton("photo.badge.plus", title: "Access") { [weak self] in self?.manageAccess() })
        toolbarScroll.showsHorizontalScrollIndicator = false; toolbarScroll.addSubview(toolbar)
        toolbarScroll.backgroundColor = .secondarySystemBackground
        countLabel.font = .systemFont(ofSize: 11); countLabel.textColor = .secondaryLabel
        message.font = .systemFont(ofSize: 14); message.textAlignment = .center; message.numberOfLines = 0; message.textColor = .secondaryLabel
        permissionButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        permissionButton.addAction(UIAction { [weak self] _ in self?.manageAccess() }, for: .touchUpInside)
        imageView.contentMode = .scaleAspectFit; imageView.backgroundColor = .black
        previewSurface.backgroundColor = .black; previewSurface.addSubview(imageView); previewSurface.addSubview(spinner)
        view.addSubview(collection); view.addSubview(previewSurface); view.addSubview(toolbarScroll); view.addSubview(message); view.addSubview(permissionButton); view.addSubview(countLabel)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapPreview)); doubleTap.numberOfTapsRequired = 2
        previewSurface.addGestureRecognizer(doubleTap)
        for name in [UIApplication.didReceiveMemoryWarningNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                if notification.name == UIApplication.didEnterBackgroundNotification { self.suspendForInactiveApp() }
                else { self.pause(); self.imageManager.stopCachingImagesForAllAssets(); self.cancelPreview() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.suspendForInactiveApp() })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.appActive = true; self?.refreshLibrary()
        })
        refreshLibrary()
    }
    deinit {
        timer?.invalidate()
        pendingLibraryRefresh?.cancel()
        if registered { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
        if previewRequest != PHInvalidImageRequestID { imageManager.cancelImageRequest(previewRequest) }
        imageManager.stopCachingImagesForAllAssets()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width, height = view.bounds.height
        toolbarScroll.frame = CGRect(x: presentationOnly ? 10 : 0, y: presentationOnly ? 10 : 0, width: max(0, width - (presentationOnly ? 20 : 0)), height: 44)
        toolbarScroll.layer.cornerRadius = presentationOnly ? 12 : 0
        let toolbarSize = toolbar.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        toolbar.frame = CGRect(x: 6, y: 0, width: max(width - 12, toolbarSize.width), height: 44)
        toolbarScroll.contentSize = CGSize(width: toolbar.frame.maxX + 6, height: 44)
        let top: CGFloat = 44, bottom: CGFloat = 24
        let sideWidth: CGFloat = previewing && width >= 760 && !presentationOnly ? min(320, width * 0.38) : width
        collection.frame = CGRect(x: 0, y: top, width: sideWidth, height: max(0, height - top - bottom))
        collection.isHidden = presentationOnly || (previewing && width < 760)
        previewSurface.isHidden = !previewing
        if presentationOnly { previewSurface.frame = view.bounds }
        else if width >= 760 { previewSurface.frame = CGRect(x: sideWidth + 8, y: top, width: max(0, width - sideWidth - 8), height: max(0, height - top - bottom)) }
        else { previewSurface.frame = CGRect(x: 0, y: top, width: width, height: max(0, height - top - bottom)) }
        imageView.frame = previewSurface.bounds
        spinner.center = CGPoint(x: previewSurface.bounds.midX, y: previewSurface.bounds.midY)
        countLabel.frame = CGRect(x: 12, y: height - bottom, width: max(0, width - 24), height: bottom)
        countLabel.isHidden = presentationOnly
        message.frame = CGRect(x: 24, y: max(60, height * 0.35), width: max(0, width - 48), height: 80)
        permissionButton.frame = CGRect(x: max(12, width / 2 - 120), y: message.frame.maxY + 12, width: min(240, max(0, width - 24)), height: 44)
        if lastCollectionSize != collection.bounds.size { lastCollectionSize = collection.bounds.size; collection.collectionViewLayout.invalidateLayout() }
        view.bringSubviewToFront(toolbarScroll)
    }
    private func refreshLibrary() {
        pendingLibraryRefresh?.cancel(); pendingLibraryRefresh = nil
        guard appActive, UIApplication.shared.applicationState == .active else { return }
        pause()
        let status = access
        guard status == .authorized || status == .limited else {
            libraryGeneration = UUID(); assets = nil; slideshow.updateCount(0); previewing = false; presentationOnly = false
            imageView.image = nil; cancelPreview(); collection.reloadData(); updateEmptyState(); updateControls(); view.setNeedsLayout()
            if registered { PHPhotoLibrary.shared().unregisterChangeObserver(self); registered = false }
            return
        }
        if !registered { PHPhotoLibrary.shared().register(self); registered = true }
        let generation = UUID(); libraryGeneration = generation
        let selectedID = selectedAsset?.localIdentifier
        message.text = "Loading your photo library…"; message.isHidden = false; permissionButton.isHidden = true
        fetchQueue.async { [weak self] in
            let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]; options.fetchLimit = 1000
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var selected: Int?
            if let selectedID {
                let same = PHAsset.fetchAssets(withLocalIdentifiers: [selectedID], options: nil)
                if let asset = same.firstObject { let index = result.index(of: asset); if index != NSNotFound { selected = index } }
            }
            DispatchQueue.main.async { [weak self = self] in
                guard let self, self.appActive, UIApplication.shared.applicationState == .active,
                      self.libraryGeneration == generation, self.access == .authorized || self.access == .limited else { return }
                self.imageManager.stopCachingImagesForAllAssets(); self.cancelPreview()
                self.assets = result; self.slideshow.updateCount(result.count)
                if let selected { self.slideshow.select(selected) }
                if result.count == 0 { self.previewing = false; self.presentationOnly = false; self.imageView.image = nil }
                self.collection.reloadData(); self.updateEmptyState(); self.updateControls(); self.view.setNeedsLayout()
                if self.previewing { self.requestPreview() }
            }
        }
    }
    private var selectedAsset: PHAsset? {
        guard let index = slideshow.selectedIndex, let assets, index >= 0, index < assets.count else { return nil }
        return assets.object(at: index)
    }
    private func updateEmptyState() {
        let authorized = access == .authorized || access == .limited
        message.isHidden = authorized && (assets?.count ?? 0) > 0
        permissionButton.isHidden = authorized && access != .limited
        switch access {
        case .notDetermined:
            message.text = "Display your photos on the desktop.\nChoose which photos ExtendDesk can access."
            permissionButton.setTitle("Choose photo access", for: .normal)
        case .denied:
            message.text = "Photo access is turned off.\nYou can enable Selected Photos or All Photos in Settings."
            permissionButton.setTitle("Open app settings", for: .normal)
        case .restricted:
            message.text = "Photo access is restricted on this device."
            permissionButton.isHidden = true
        case .limited:
            message.text = "No selected photos are available.\nUse Access to select more photos."
            permissionButton.setTitle("Manage selected photos", for: .normal)
            permissionButton.isHidden = (assets?.count ?? 0) > 0
        case .authorized:
            message.text = "Your photo library has no images yet."
        @unknown default: message.text = "Photo access is unavailable."
        }
    }
    private func manageAccess() {
        switch access {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in DispatchQueue.main.async { [weak self = self] in self?.refreshLibrary() } }
        case .limited: PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .authorized: refreshLibrary()
        default: alert("Photo access is restricted", message: "This device does not currently allow photo library access.")
        }
    }
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.appActive else { return }
            self.pendingLibraryRefresh?.cancel()
            let work = DispatchWorkItem { [weak self = self] in self?.refreshLibrary() }
            self.pendingLibraryRefresh = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { assets?.count ?? 0 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "photo", for: indexPath) as! PhotoThumbnailCell
        guard let assets, indexPath.item < assets.count else { return cell }
        let asset = assets.object(at: indexPath.item)
        cell.represent(asset.localIdentifier, manager: imageManager)
        let options = thumbnailOptions()
        let request = imageManager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: options) { [weak cell] image, info in
            guard (info?[PHImageCancelledKey] as? Bool) != true else { return }
            DispatchQueue.main.async { [weak cell = cell] in if cell?.representedIdentifier == asset.localIdentifier { cell?.setImage(image) } }
        }
        cell.requestID = request
        cell.isSelected = indexPath.item == slideshow.selectedIndex
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = max(1, collectionView.bounds.width)
        let columns = max(2, Int(width / 138))
        let size = max(44, floor((width - CGFloat(columns + 1) * 8) / CGFloat(columns)))
        return CGSize(width: size, height: size)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets { UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8) }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat { 8 }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat { 8 }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        pause(); slideshow.select(indexPath.item); previewing = true; view.setNeedsLayout(); view.layoutIfNeeded(); requestPreview(); updateControls()
    }
    private func thumbnailOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions(); options.deliveryMode = .opportunistic; options.resizeMode = .fast; options.isNetworkAccessAllowed = false; return options
    }
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let assets else { return }
        let nearby = indexPaths.prefix(30).filter { $0.item < assets.count }.map { assets.object(at: $0.item) }
        imageManager.startCachingImages(for: nearby, targetSize: thumbnailSize, contentMode: .aspectFill, options: thumbnailOptions())
    }
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        guard let assets else { return }
        let nearby = indexPaths.filter { $0.item < assets.count }.map { assets.object(at: $0.item) }
        imageManager.stopCachingImages(for: nearby, targetSize: thumbnailSize, contentMode: .aspectFill, options: thumbnailOptions())
    }
    private func cancelPreview() {
        previewGeneration = UUID()
        if previewRequest != PHInvalidImageRequestID { imageManager.cancelImageRequest(previewRequest); previewRequest = PHInvalidImageRequestID }
        spinner.stopAnimating()
    }
    private func requestPreview() {
        cancelPreview()
        guard desktopVisible, appActive, UIApplication.shared.applicationState == .active, let asset = selectedAsset else { return }
        let generation = previewGeneration
        spinner.startAnimating(); countLabel.text = "Loading photo…"
        let size = CGSize(width: min(2048, max(800, imageView.bounds.width * 2)), height: min(2048, max(600, imageView.bounds.height * 2)))
        let options = PHImageRequestOptions(); options.deliveryMode = .highQualityFormat; options.resizeMode = .fast; options.isNetworkAccessAllowed = true
        options.progressHandler = { [weak self] progress, _, _, _ in
            DispatchQueue.main.async { [weak self = self] in
                guard let self, self.previewGeneration == generation else { return }
                self.countLabel.text = "Downloading from iCloud · \(Int(progress * 100))%"
            }
        }
        previewRequest = imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { [weak self] image, info in
            DispatchQueue.main.async { [weak self = self] in
                guard let self, self.previewGeneration == generation, (info?[PHImageCancelledKey] as? Bool) != true else { return }
                self.spinner.stopAnimating(); self.previewRequest = PHInvalidImageRequestID
                if let image { self.imageView.image = image; self.updateControls() }
                else { self.imageView.image = nil; self.countLabel.text = (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "This photo is unavailable. Check the connection or choose another image." }
                self.armSlideshow()
            }
        }
    }
    private func updateControls() {
        let count = assets?.count ?? 0
        playButton.isEnabled = count > 0; fullButton.isEnabled = previewing && count > 0
        playButton.setImage(UIImage(systemName: slideshow.playing ? "pause.fill" : "play.fill"), for: .normal)
        fullButton.setImage(UIImage(systemName: presentationOnly ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"), for: .normal)
        let position = slideshow.selectedIndex.map { "Photo \($0 + 1) of \(count) · " } ?? ""
        countLabel.text = position + (access == .limited ? "Selected Photos" : "Library") + (count == 1000 ? " · Latest 1,000 images" : " · \(count) images")
    }
    func nextPhoto() { movePhoto(1) }
    func previousPhoto() { movePhoto(-1) }
    private func movePhoto(_ offset: Int) {
        guard slideshow.count > 0 else { return }
        timer?.invalidate(); timer = nil; slideshow.move(offset); previewing = true
        view.setNeedsLayout(); view.layoutIfNeeded(); requestPreview(); updateControls()
        if let index = slideshow.selectedIndex, !collection.isHidden { collection.selectItem(at: IndexPath(item: index, section: 0), animated: false, scrollPosition: .centeredVertically) }
    }
    func toggleSlideshow() {
        guard slideshow.count > 0 else { return }
        if slideshow.playing { pause(); return }
        slideshow.setPlaying(true); previewing = true
        view.setNeedsLayout(); view.layoutIfNeeded(); updateControls(); requestPreview()
    }
    private func armSlideshow() {
        timer?.invalidate(); timer = nil
        guard slideshow.playing, desktopVisible, appActive, UIApplication.shared.applicationState == .active else { return }
        timer = Timer.scheduledTimer(withTimeInterval: slideshow.interval, repeats: false) { [weak self] _ in self?.nextPhoto() }
    }
    private func pause() { timer?.invalidate(); timer = nil; slideshow.setPlaying(false); if isViewLoaded { updateControls() } }
    private func suspendForInactiveApp() {
        appActive = false; libraryGeneration = UUID()
        pendingLibraryRefresh?.cancel(); pendingLibraryRefresh = nil
        pause(); imageManager.stopCachingImagesForAllAssets(); cancelPreview()
    }
    private func showLibrary() { pause(); cancelPreview(); previewing = false; presentationOnly = false; imageView.image = nil; view.setNeedsLayout() }
    func togglePresentation() { guard previewing else { return }; presentationOnly.toggle(); view.setNeedsLayout(); updateControls() }
    @objc private func doubleTapPreview() { togglePresentation() }
    func setDesktopVisible(_ visible: Bool) {
        guard desktopVisible != visible else { return }; desktopVisible = visible
        if !visible { pause(); cancelPreview(); imageManager.stopCachingImagesForAllAssets() }
        else if previewing { requestPreview() }
    }
    private func chooseInterval() {
        let menu = UIAlertController(title: "Slideshow speed", message: nil, preferredStyle: .actionSheet)
        for interval in [3.0, 5.0, 10.0] {
            menu.addAction(UIAlertAction(title: "\(Int(interval)) seconds", style: .default) { [weak self] _ in self?.slideshow.interval = interval; self?.armSlideshow() })
        }
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel)); menu.popoverPresentationController?.sourceView = presenter.view
        menu.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: 60, width: 1, height: 1); presenter.present(menu, animated: true)
    }
    override func pointerClick(at point: CGPoint, secondary: Bool) {
        if !collection.isHidden, collection.frame.contains(point), let index = collection.indexPathForItem(at: view.convert(point, to: collection)) {
            collection.selectItem(at: index, animated: false, scrollPosition: []); collectionView(collection, didSelectItemAt: index); return
        }
        super.pointerClick(at: point, secondary: secondary)
    }
    override func pointerScroll(at point: CGPoint, delta: CGPoint) {
        if toolbarScroll.frame.contains(point) {
            toolbarScroll.contentOffset.x = min(max(0, toolbarScroll.contentOffset.x + delta.x + delta.y), max(0, toolbarScroll.contentSize.width - toolbarScroll.bounds.width)); return
        }
        super.pointerScroll(at: point, delta: delta)
    }
    override func insertText(_ text: String) {
        if text == " " { toggleSlideshow() }
        else if text == "\u{1B}" { if presentationOnly { togglePresentation() } else { showLibrary() } }
    }
}

private final class PhotoThumbnailCell: UICollectionViewCell {
    private let image = UIImageView()
    private weak var manager: PHImageManager?
    var representedIdentifier: String?
    var requestID: PHImageRequestID = PHInvalidImageRequestID
    override init(frame: CGRect) {
        super.init(frame: frame); image.contentMode = .scaleAspectFill; image.clipsToBounds = true
        image.layer.cornerRadius = 7; contentView.addSubview(image); contentView.layer.cornerRadius = 8; contentView.layer.borderWidth = 2
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() {
        super.prepareForReuse(); cancel(); representedIdentifier = nil; image.image = nil
    }
    func represent(_ id: String, manager: PHImageManager) { cancel(); representedIdentifier = id; self.manager = manager; image.image = UIImage(systemName: "photo"); image.tintColor = .tertiaryLabel; accessibilityLabel = "Photo thumbnail" }
    func setImage(_ value: UIImage?) { image.image = value ?? UIImage(systemName: "icloud.and.arrow.down") }
    private func cancel() { if requestID != PHInvalidImageRequestID { manager?.cancelImageRequest(requestID); requestID = PHInvalidImageRequestID } }
    override var isSelected: Bool { didSet { contentView.layer.borderColor = (isSelected ? UIColor.systemBlue : .clear).cgColor } }
    override func layoutSubviews() { super.layoutSubviews(); image.frame = contentView.bounds.insetBy(dx: 3, dy: 3) }
    deinit { cancel() }
}
