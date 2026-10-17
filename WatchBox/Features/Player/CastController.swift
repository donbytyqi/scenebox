//
//  CastController.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

#if os(iOS)
import Foundation
import Observation
import SwiftVLC

@MainActor
@Observable
final class CastController {
    private(set) var renderers: [RendererItem] = []
    private(set) var active: RendererItem?
    private(set) var isSwitching = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var discoverer: RendererDiscoverer?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    var isCasting: Bool { active != nil }
    var isAvailable: Bool { !renderers.isEmpty || isCasting }

    func startDiscovery() {
        guard discoverer == nil,
              let service = RendererDiscoverer.availableServices().first else { return }
        do {
            let discoverer = try RendererDiscoverer(name: service.name)
            try discoverer.start()
            self.discoverer = discoverer
            eventsTask = Task { [weak self] in
                for await event in discoverer.events {
                    guard let self, !Task.isCancelled else { return }
                    if let added = event.itemAdded {
                        if added.canVideo, !renderers.contains(added) {
                            renderers.append(added)
                        }
                    } else if let deleted = event.itemDeleted {
                        renderers.removeAll { $0 == deleted }
                    }
                }
            }
        } catch {
        }
    }

    func stopDiscovery() {
        eventsTask?.cancel()
        eventsTask = nil
        discoverer?.stop()
        discoverer = nil
        renderers = []
    }

    func cast(to renderer: RendererItem?, player: Player) {
        guard !isSwitching else { return }
        isSwitching = true
        errorMessage = nil
        Task {
            defer { isSwitching = false }
            do {
                try await player.recast(to: renderer)
                active = renderer
            } catch {
                errorMessage = renderer.map { "Couldn't cast to \($0.name)." }
                    ?? "Couldn't switch back to this device."
            }
        }
    }
}
#endif
