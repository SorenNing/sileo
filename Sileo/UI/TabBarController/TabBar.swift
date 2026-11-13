//
//  TabBar.swift
//  Sileo
//
//  Created by CoolStar on 7/27/19.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import UIKit

// ThemeBoard-style source adaptation by Ning. Keep UIKit's real items/controls:
// they own localization, badges, VoiceOver and UITabBarController selection.
class TabBar: UITabBar, UIGestureRecognizerDelegate {
    static let dockHeight: CGFloat = 64
    static let dockMargin: CGFloat = 18
    static let dockBottom: CGFloat = 34
    static let pillInset: CGFloat = 4
    private static let dockMaterialTag = 0x5442444B
    private static let stretchDuration: TimeInterval = 0.26
    private static let settleDuration: TimeInterval = 0.14
    private static let squash: CGFloat = 0.92

    var onDockSelection: ((Int) -> Void)?
    private let surface = UIView()
    private let material = UIVisualEffectView(effect: nil)
    private let fill = UIView()
    private let pill = UIView()
    private var pillAnimator: UIViewPropertyAnimator?
    private var animationGeneration: UInt = 0
    private var selectedDockIndex = -1
    private var previousSurfaceSize = CGSize.zero
    private var draggingDock = false
    private var panStartFrame = CGRect.zero
    private var panStartIndex = -1
    private var didConfigureDock = false

    var dockBottomSpacing: CGFloat {
        max(Self.dockBottom, window?.safeAreaInsets.bottom ?? safeAreaInsets.bottom)
    }

    var dockTotalHeight: CGFloat { Self.dockHeight + dockBottomSpacing }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureDock()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureDock()
    }

    private func configureDock() {
        guard !didConfigureDock else { return }
        didConfigureDock = true
        isTranslucent = true
        backgroundColor = .clear
        backgroundImage = UIImage()
        shadowImage = UIImage()
        selectionIndicatorImage = UIImage()
        // WhiteBlur.m exempts only descendants of this surface from its old
        // opaque .85 overlay. No other Sileo materials are changed.
        surface.tag = Self.dockMaterialTag
        surface.isUserInteractionEnabled = false
        surface.clipsToBounds = true
        surface.layer.cornerRadius = Self.dockHeight / 2
        pill.layer.cornerRadius = (Self.dockHeight - Self.pillInset * 2) / 2
        if #available(iOS 13.0, *) {
            surface.layer.cornerCurve = .continuous
            pill.layer.cornerCurve = .continuous
        }
        material.isUserInteractionEnabled = false
        fill.isUserInteractionEnabled = false
        pill.isUserInteractionEnabled = false
        surface.addSubview(material)
        surface.addSubview(fill)
        surface.addSubview(pill)
        insertSubview(surface, at: 0)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(dockPanned(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        addGestureRecognizer(pan)
        // ThemeManager may not be initialized while the storyboard decodes.
        // Apply the final material after the tab bar enters a window.
    }

    override var selectedItem: UITabBarItem? {
        didSet {
            guard didConfigureDock else { return }
            synchronizeSelection(animated: window != nil)
        }
    }

    override func setItems(_ items: [UITabBarItem]?, animated: Bool) {
        super.setItems(items, animated: animated)
        guard didConfigureDock else { return }
        previousSurfaceSize = .zero
        setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var result = super.sizeThatFits(size)
        result.height = dockTotalHeight
        return result
    }

    override var traitCollection: UITraitCollection {
        // Preserve Sileo's original iPad compact treatment. The dock changes
        // geometry only; it does not change the source's size-class policy.
        if UIDevice.current.userInterfaceIdiom == .phone {
            return super.traitCollection
        }
        if UIApplication.shared.statusBarOrientation.isLandscape && bounds.width >= 400 {
            return super.traitCollection
        }
        return UITraitCollection(traitsFrom: [super.traitCollection,
            UITraitCollection(horizontalSizeClass: .compact)])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshDockAppearance()
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshDockAppearance()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard didConfigureDock else { return }
        // Only real UITabBarItem views; never replace them with copies.
        let itemViews = nativeItemViews()
        guard let items = items, !items.isEmpty else {
            surface.isHidden = true
            return
        }
        surface.isHidden = false
        let left = Self.dockMargin + safeAreaInsets.left
        let right = Self.dockMargin + safeAreaInsets.right
        surface.frame = CGRect(x: left, y: 0, width: max(0, bounds.width - left - right),
                               height: Self.dockHeight)
        material.frame = surface.bounds
        fill.frame = surface.bounds
        // Keep UIKit's own background below the glass, and its real tab
        // controls above the glass. No copied buttons or copied badge views.
        bringSubviewToFront(surface)
        let width = surface.bounds.width / CGFloat(items.count)
        for (index, control) in itemViews.enumerated() {
            let slot = visualIndex(for: index, count: items.count)
            control.frame = CGRect(x: left + CGFloat(slot) * width, y: 0,
                                   width: width, height: Self.dockHeight)
            control.setNeedsLayout()
            control.layoutIfNeeded()
            layoutNativeContent(in: control)
            control.superview?.bringSubviewToFront(control)
        }
        let resized = previousSurfaceSize != surface.bounds.size
        previousSurfaceSize = surface.bounds.size
        if resized {
            draggingDock = false
            cancelPillAnimation()
        }
        synchronizeSelection(animated: !resized && window != nil)
    }

    private func nativeItemViews() -> [UIView] {
        // Sileo already exposes UITabBarItem.view() in its bridging header and
        // uses it for source-refresh badges. Keep this in model-item order;
        // no guessing private class names or relying on current frame order.
        (items ?? []).compactMap { $0.view() }
    }

    private func layoutNativeContent(in control: UIView) {
        let imageFrame = CGRect(x: (control.bounds.width - 22) / 2, y: 12, width: 22, height: 22)
        let nativeImage = control.subviews.compactMap { $0 as? UIImageView }.first
        let oldImageFrame = nativeImage?.frame
        for view in control.subviews {
            if let image = view as? UIImageView, image === nativeImage {
                image.contentMode = .scaleAspectFit
                image.frame = imageFrame
            } else if let label = view as? UILabel {
                label.font = UIFont.systemFont(ofSize: 10, weight: .medium)
                label.textAlignment = .center
                label.frame = CGRect(x: 2, y: 36, width: max(0, control.bounds.width - 4), height: 14)
            } else if NSStringFromClass(type(of: view)).contains("Badge"), let old = oldImageFrame {
                // Keep UIKit's badge view/value; only carry its icon-relative offset.
                view.frame = view.frame.offsetBy(dx: imageFrame.maxX - old.maxX,
                                                 dy: imageFrame.minY - old.minY)
            }
        }
    }

    func refreshDockAppearance() {
        let dark = UIColor.isDarkModeEnabled
        if #available(iOS 13.0, *) {
            material.overrideUserInterfaceStyle = dark ? .dark : .light
            material.effect = UIBlurEffect(style: .systemThinMaterial)
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            standardAppearance = appearance
            if #available(iOS 15.0, *) { scrollEdgeAppearance = appearance }
        } else {
            material.effect = UIBlurEffect(style: dark ? .dark : .light)
        }
        let pixel = 1 / UIScreen.main.scale
        fill.backgroundColor = UIColor(white: 1, alpha: dark ? 0.12 : 0.55)
        surface.layer.borderWidth = pixel
        surface.layer.borderColor = UIColor(white: 1, alpha: dark ? 0.165 : 0.55).cgColor
        pill.backgroundColor = UIColor(white: 1, alpha: dark ? 0.13 : 0.42)
        pill.layer.borderWidth = pixel
        pill.layer.borderColor = UIColor(white: 1, alpha: dark ? 0.165 : 0.55).cgColor
        tintColor = .sileoLabel
        unselectedItemTintColor = .sileoLabel
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor.sileoLabel
        ]
        for item in items ?? [] {
            item.setTitleTextAttributes(attributes, for: .normal)
            item.setTitleTextAttributes(attributes, for: .selected)
        }
    }

    private func visualIndex(for index: Int, count: Int) -> Int {
        effectiveUserInterfaceLayoutDirection == .rightToLeft ? count - 1 - index : index
    }

    private func pillFrame(for index: Int) -> CGRect {
        let count = items?.count ?? 0
        guard count > 0 else { return .zero }
        let width = surface.bounds.width / CGFloat(count)
        let slot = visualIndex(for: max(0, min(index, count - 1)), count: count)
        return CGRect(x: CGFloat(slot) * width + Self.pillInset, y: Self.pillInset,
                      width: max(0, width - Self.pillInset * 2),
                      height: Self.dockHeight - Self.pillInset * 2)
    }

    func synchronizeSelection(animated: Bool) {
        guard let items = items, let item = selectedItem,
              let index = items.firstIndex(where: { $0 === item }),
              !draggingDock, surface.bounds.width > 0 else { return }
        let changed = selectedDockIndex != index
        let hadSelection = selectedDockIndex >= 0
        selectedDockIndex = index
        let views = nativeItemViews()
        for (position, view) in views.enumerated() {
            view.alpha = position == index ? 1 : 0.75
        }
        if changed && animated && hadSelection, views.indices.contains(index) {
            animateSelectedIcon(in: views[index])
        }
        if changed || (!animated && pillAnimator == nil) {
            movePill(to: index, animated: animated && hadSelection)
        }
    }

    private func animateSelectedIcon(in itemView: UIView) {
        guard let image = itemView.subviews.compactMap({ $0 as? UIImageView }).first else { return }
        image.layer.removeAllAnimations()
        image.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        UIView.animate(withDuration: 0.40, delay: 0,
                       usingSpringWithDamping: 0.75,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            image.transform = .identity
        }
    }

    @discardableResult
    private func cancelPillAnimation() -> CGRect {
        // Capture BEFORE removing animations; otherwise quick taps jump to the
        // previous model-layer destination instead of the visible position.
        let visible = pill.layer.presentation()?.frame ?? pill.frame
        animationGeneration &+= 1
        pillAnimator?.stopAnimation(true)
        pillAnimator = nil
        pill.layer.removeAllAnimations()
        pill.frame = visible
        return visible
    }

    private func movePill(to index: Int, animated: Bool) {
        let start = cancelPillAnimation()
        let target = pillFrame(for: index)
        guard animated, !UIAccessibility.isReduceMotionEnabled, start.width > 0 else {
            pill.frame = target
            return
        }
        let generation = animationGeneration
        let height = target.height * Self.squash
        let stretch = CGRect(x: min(start.minX, target.minX), y: target.midY - height / 2,
                             width: max(start.maxX, target.maxX) - min(start.minX, target.minX),
                             height: height)
        let animator = UIViewPropertyAnimator(duration: Self.stretchDuration, dampingRatio: 1) {
            [weak self] in self?.pill.frame = stretch
        }
        pillAnimator = animator
        animator.addCompletion { [weak self] position in
            guard let self = self, position == .end,
                  self.animationGeneration == generation else { return }
            let settle = UIViewPropertyAnimator(duration: Self.settleDuration, dampingRatio: 0.82) {
                [weak self] in self?.pill.frame = target
            }
            self.pillAnimator = settle
            settle.addCompletion { [weak self] position in
                guard let self = self, position == .end,
                      self.animationGeneration == generation else { return }
                self.pillAnimator = nil
                self.pill.frame = target
            }
            settle.startAnimation()
        }
        animator.startAnimation()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The bottom reserve and rounded corners are genuinely transparent;
        // they must not steal touches from list content or the Home indicator.
        let local = convert(point, to: surface)
        guard !isHidden, alpha > 0.01, !surface.isHidden,
              UIBezierPath(roundedRect: surface.bounds, cornerRadius: Self.dockHeight / 2)
                .contains(local) else { return nil }
        return super.hitTest(point, with: event)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              surface.frame.contains(pan.location(in: self)),
              onDockSelection != nil else { return false }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func dockPanned(_ pan: UIPanGestureRecognizer) {
        let count = items?.count ?? 0
        guard count > 0, selectedDockIndex >= 0 else { return }
        let width = surface.bounds.width / CGFloat(count)
        guard width > 0 else { return }
        switch pan.state {
        case .began:
            panStartFrame = cancelPillAnimation()
            panStartIndex = selectedDockIndex
            draggingDock = true
        case .changed:
            guard draggingDock else { return }
            var frame = panStartFrame
            frame.size = pillFrame(for: selectedDockIndex).size
            frame.origin.y = Self.pillInset
            frame.origin.x = max(Self.pillInset,
                min(surface.bounds.width - frame.width - Self.pillInset,
                    panStartFrame.midX + pan.translation(in: self).x - frame.width / 2))
            pill.frame = frame
        case .ended, .cancelled, .failed:
            guard draggingDock else { return }
            draggingDock = false
            // A URL/quick action can change tabs while a finger is down. Never
            // let that stale drag override the newer programmatic selection.
            let actual = items?.firstIndex(where: { $0 === selectedItem }) ?? selectedDockIndex
            guard pan.state == .ended, actual == panStartIndex else {
                synchronizeSelection(animated: true)
                if pillAnimator == nil { movePill(to: actual, animated: true) }
                return
            }
            var slot = Int(floor(pill.frame.midX / width))
            let velocity = pan.velocity(in: self).x
            if velocity > 320 { slot += 1 }
            if velocity < -320 { slot -= 1 }
            slot = max(0, min(slot, count - 1))
            let index = visualIndex(for: slot, count: count)
            if index != selectedDockIndex, items?[index].isEnabled == true {
                onDockSelection?(index)
            }
            // Native/programmatic selection already starts the animation. A
            // drag within the same slot only needs a single snap-back.
            synchronizeSelection(animated: true)
            if pillAnimator == nil { movePill(to: selectedDockIndex, animated: true) }
        default:
            break
        }
    }
}
