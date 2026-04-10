import SwiftUI
import UIKit
import CoreLocation

/// Manages the turn-instruction panel overlaid on the AR view.
/// Distance-aware: fades when the next turn is far away, pulses when close.
final class TurnHUDManager {

    static let shared = TurnHUDManager()
    private init() {}

    private var hostingController: UIHostingController<TurnPanel>?
    private weak var parentView: UIView?

    private var isPulsing = false

    // MARK: Attach

    func attach(to view: UIView) {
        parentView = view
        showPanelIfNeeded(on: view)
    }

    // MARK: Public update API

    /// Pass nil instruction/distance to hide the panel.
    func updateTurn(instruction: String?, distanceMeters: Double?) {
        guard
            let instruction,
            let distanceMeters,
            !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            hide(); return
        }
        show()
        update(instruction: instruction, distance: distanceMeters)
        applyDistanceOpacity(distanceMeters)
    }

    // MARK: Private update

    private func update(instruction: String, distance: Double) {
        guard let host = hostingController else { return }
        host.rootView = TurnPanel(distance: distance, instruction: instruction)
    }

    private func applyDistanceOpacity(_ distance: Double) {
        guard let view = hostingController?.view else { return }

        let targetAlpha: CGFloat
        if distance > 150 {
            targetAlpha = 0.30
            stopPulse()
        } else if distance < 50 {
            targetAlpha = 1.0
            startPulse()
        } else {
            targetAlpha = 1.0
            stopPulse()
        }

        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            view.alpha = targetAlpha
        }
    }

    // MARK: Pulse (< 50 m)

    private func startPulse() {
        guard !isPulsing, let view = hostingController?.view else { return }
        isPulsing = true
        UIView.animateKeyframes(
            withDuration: 0.75, delay: 0,
            options: [.repeat, .autoreverse, .calculationModeCubic]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
                view.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
            }
        }
    }

    private func stopPulse() {
        guard isPulsing, let view = hostingController?.view else { return }
        isPulsing = false
        view.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.15) { view.transform = .identity }
    }

    // MARK: Show / Hide

    func hide() {
        stopPulse()
        guard let v = hostingController?.view, !v.isHidden else { return }
        UIView.animate(withDuration: 0.2) { v.alpha = 0 } completion: { _ in v.isHidden = true }
    }

    func show() {
        guard let v = hostingController?.view else { return }
        if v.isHidden {
            v.isHidden = false
            v.alpha = 0
            UIView.animate(withDuration: 0.2) { v.alpha = 1 }
        }
    }

    // MARK: Setup

    private func showPanelIfNeeded(on view: UIView) {
        guard hostingController == nil else { return }

        let panel = TurnPanel(distance: 0, instruction: "")
        let host = UIHostingController(rootView: panel)
        hostingController = host

        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.isHidden = true

        view.addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            host.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            host.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }
}
