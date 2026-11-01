import UIKit

/// Original, resolution-independent landscapes. No external art or continuous animation.
final class WallpaperView: UIView {
    private let sky = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let farRidge = CAShapeLayer()
    private let middleRidge = CAShapeLayer()
    private let nearRidge = CAShapeLayer()
    private let photo = UIImageView()
    private var preset = -1
    private var observation: NSObjectProtocol?
    private var request = UUID()
    override init(frame: CGRect) {
        super.init(frame: frame); isUserInteractionEnabled = false
        layer.addSublayer(sky); layer.addSublayer(glow)
        [farRidge, middleRidge, nearRidge].forEach { layer.addSublayer($0) }
        photo.contentMode = .scaleAspectFill; photo.clipsToBounds = true; addSubview(photo)
        observation = NotificationCenter.default.addObserver(forName: .appearanceChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
    func refresh() {
        let preferences = DesktopPreferences.shared
        preset = preferences.wallpaperPreset; request = UUID(); let current = request
        photo.image = nil; photo.isHidden = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let palettes: [[UIColor]] = [
            [UIColor(red: 0.10, green: 0.22, blue: 0.43, alpha: 1), UIColor(red: 0.50, green: 0.66, blue: 0.77, alpha: 1), UIColor(red: 0.25, green: 0.42, blue: 0.42, alpha: 1), UIColor(red: 0.12, green: 0.32, blue: 0.31, alpha: 1), UIColor(red: 0.05, green: 0.21, blue: 0.25, alpha: 1)],
            [UIColor(red: 0.10, green: 0.30, blue: 0.52, alpha: 1), UIColor(red: 0.59, green: 0.78, blue: 0.82, alpha: 1), UIColor(red: 0.32, green: 0.61, blue: 0.67, alpha: 1), UIColor(red: 0.13, green: 0.43, blue: 0.58, alpha: 1), UIColor(red: 0.06, green: 0.27, blue: 0.43, alpha: 1)],
            [UIColor(red: 0.13, green: 0.10, blue: 0.30, alpha: 1), UIColor(red: 0.77, green: 0.43, blue: 0.48, alpha: 1), UIColor(red: 0.46, green: 0.28, blue: 0.47, alpha: 1), UIColor(red: 0.30, green: 0.21, blue: 0.39, alpha: 1), UIColor(red: 0.17, green: 0.14, blue: 0.30, alpha: 1)],
            [UIColor(white: 0.10, alpha: 1), UIColor(white: 0.42, alpha: 1), UIColor(white: 0.28, alpha: 1), UIColor(white: 0.19, alpha: 1), UIColor(white: 0.10, alpha: 1)]
        ]
        let colors = palettes[preset]
        sky.colors = [colors[0].cgColor, colors[1].cgColor]; sky.startPoint = .zero; sky.endPoint = CGPoint(x: 0.8, y: 1)
        glow.type = .radial; glow.colors = [UIColor.white.withAlphaComponent(0.13).cgColor, UIColor.clear.cgColor]; glow.startPoint = CGPoint(x: 0.72, y: 0.2); glow.endPoint = CGPoint(x: 1, y: 0.8)
        farRidge.fillColor = colors[2].cgColor; middleRidge.fillColor = colors[3].cgColor; nearRidge.fillColor = colors[4].cgColor
        CATransaction.commit(); setNeedsLayout()
        if preferences.hasCustomWallpaper {
            preferences.loadCustomWallpaper { [weak self] image in
                guard let self, request == current else { return }; photo.image = image; photo.isHidden = image == nil
            }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sky.frame = bounds; glow.frame = bounds; photo.frame = bounds
        let width = bounds.width, height = bounds.height
        farRidge.path = ridge(width: width, height: height, start: 0.62, crest: 0.30, end: 0.55, bend: 0.62)
        middleRidge.path = ridge(width: width, height: height, start: 0.54, crest: 0.76, end: 0.47, bend: 0.44)
        nearRidge.path = ridge(width: width, height: height, start: 0.84, crest: 0.51, end: 0.87, bend: 0.32)
        CATransaction.commit()
    }
    private func ridge(width: CGFloat, height: CGFloat, start: CGFloat, crest: CGFloat, end: CGFloat, bend: CGFloat) -> CGPath {
        let path = UIBezierPath(); path.move(to: CGPoint(x: 0, y: height * start))
        path.addCurve(to: CGPoint(x: width, y: height * end), controlPoint1: CGPoint(x: width * bend, y: height * crest), controlPoint2: CGPoint(x: width * 0.70, y: height * crest))
        path.addLine(to: CGPoint(x: width, y: height)); path.addLine(to: CGPoint(x: 0, y: height)); path.close(); return path.cgPath
    }
}
