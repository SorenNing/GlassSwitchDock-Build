import UIKit

// No geometry, material, animation, colour or physics override is applied to
// this instance. Only the existing UISwitch's value and enabled state are bound.
@objc(NGTheseusSwitch)
final class NGTheseusSwitch: UIView {
    private let toggle = TheseusSwitch()
    @objc var onChanged: ((Bool) -> Void)?
    @objc var on: Bool {
        get { toggle.isOn }
        set { toggle.isOn = newValue }
    }
    @objc(isOn) func isOn() -> Bool { toggle.isOn }

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: 63, height: 28)))
        backgroundColor = .clear
        clipsToBounds = false
        isOpaque = false
        addSubview(toggle)
        toggle.frame = bounds
        toggle.onValueChanged = { [weak self] value in self?.onChanged?(value) }
    }
    required init?(coder: NSCoder) { return nil }
    override var intrinsicContentSize: CGSize { toggle.intrinsicContentSize }
    @objc var replacementReady: Bool { window != nil && !toggle.bounds.isEmpty && toggle.superview === self }
    override var isHidden: Bool { didSet { toggle.isHidden = isHidden } }
    override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview !== superview {
            // The lens is a sibling of this wrapper; hide it before detaching
            // so cell reuse cannot leave a lens or an active gesture behind.
            toggle.isHidden = true
        }
        super.willMove(toSuperview: newSuperview)
    }
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        toggle.isHidden = isHidden || superview == nil
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(bounds.width / 63, bounds.height / 28)
        toggle.bounds = CGRect(x: 0, y: 0, width: 63, height: 28)
        toggle.center = CGPoint(x: bounds.midX, y: bounds.midY)
        toggle.transform = CGAffineTransform(scaleX: scale, y: scale)
        toggle.layoutIfNeeded()
    }
    @objc(setOn:animated:) func setOn(_ value: Bool, animated: Bool) {
        toggle.setOn(value, animated: animated)
    }
    @objc(setControlEnabled:) func setControlEnabled(_ enabled: Bool) { toggle.isEnabled = enabled }
    override var accessibilityLabel: String? {
        get { toggle.accessibilityLabel }
        set { toggle.accessibilityLabel = newValue }
    }
    override func accessibilityActivate() -> Bool { toggle.accessibilityActivate() }
}

