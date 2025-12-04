//
//  TurnHUDManager.swift
//  WalkWithMe
//

import SwiftUI
import UIKit
import CoreLocation

/// ------------------------------------------------------------
/// WALKWITHME — TurnHUDManager
/// ------------------------------------------------------------
/// Responsible for:
///   • Showing / hiding TurnPanel
///   • Updating distance + instruction
///   • Keeping HUD locked to top-center of screen
///
/// Works independently from AR hazards + YOLO.
/// Non-intrusive overlay.
/// ------------------------------------------------------------
final class TurnHUDManager {

    static let shared = TurnHUDManager()
    private init() {}

    // --------------------------------------------------------
    //   UI Elements
    // --------------------------------------------------------
    private var hostingController: UIHostingController<TurnPanel>?
    private weak var parentView: UIView?

    // Current values
    private var currentInstruction: String = ""
    private var currentDistance: Double = 0

    // --------------------------------------------------------
    // Attach HUD to ARView
    // --------------------------------------------------------
    func attach(to view: UIView) {
        self.parentView = view
        showPanelIfNeeded(on: view)
    }

    // --------------------------------------------------------
    // UPDATE turn instruction
    // Called by ARSessionManager
    // --------------------------------------------------------
    func update(instruction: String, distance: Double) {

        currentInstruction = instruction
        currentDistance = distance

        guard let host = hostingController else { return }

        host.rootView = TurnPanel(
            distance: distance,
            instruction: instruction
        )
    }

    // --------------------------------------------------------
    // INTERNAL — Add TurnPanel if missing
    // --------------------------------------------------------
    private func showPanelIfNeeded(on view: UIView) {

        guard hostingController == nil else { return }

        let panel = TurnPanel(distance: 0, instruction: "Loading…")
        let host = UIHostingController(rootView: panel)
        hostingController = host

        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(host.view)

        // Pin to top-center
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            host.view.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    // --------------------------------------------------------
    // HIDE when no upcoming turn
    // --------------------------------------------------------
    func hide() {
        hostingController?.view.isHidden = true
    }

    // --------------------------------------------------------
    // SHOW when needed
    // --------------------------------------------------------
    func show() {
        hostingController?.view.isHidden = false
    }
}
