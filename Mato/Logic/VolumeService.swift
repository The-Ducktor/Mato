//
//  VolumeService.swift
//  Mato
//

import Foundation
import AppKit
import SwiftUI

struct Volume: Identifiable, Hashable {
    let id: URL
    let name: String
    let url: URL
    let isRemovable: Bool
    let isEjectable: Bool
    let isLocal: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Volume, rhs: Volume) -> Bool {
        lhs.id == rhs.id
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    var systemImage: String {
        if !isLocal { return "network" }
        if isRemovable || isEjectable { return "externaldrive" }
        return "externaldrive"
    }
}

@MainActor
@Observable
final class VolumeService {
    var volumes: [Volume] = []

    init() {
        refreshVolumes()
        observeMountEvents()
    }

    func refreshVolumes() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey
        ]

        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: []
        ) else {
            self.volumes = []
            return
        }

        let systemVolumePaths: Set<String> = [
            "/",
            "/System",
            "/System/Volumes/Data",
            "/System/Volumes/Preboot",
            "/System/Volumes/VM",
            "/System/Volumes/Update",
            "/System/Volumes/iSCPreboot",
            "/System/Volumes/Hardware",
            "/private/var/vm"
        ]

        self.volumes = volumes.compactMap { url in
            let resolvedURL = url.resolvingSymlinksInPath()
            guard !systemVolumePaths.contains(resolvedURL.path) else { return nil }

            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }

            let isInternal = values.volumeIsInternal ?? true
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false
            let isLocal = values.volumeIsLocal ?? true

            guard !isInternal || isRemovable || isEjectable || !isLocal else { return nil }

            let volumeName = values.volumeName ?? url.lastPathComponent

            return Volume(
                id: url,
                name: volumeName,
                url: url,
                isRemovable: isRemovable,
                isEjectable: isEjectable,
                isLocal: isLocal
            )
        }
    }

    func eject(_ volume: Volume) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
        } catch {
            if FileManager.default.fileExists(atPath: volume.url.path) {
                let task = Process()
                task.launchPath = "/usr/sbin/diskutil"
                task.arguments = ["eject", volume.url.path]
                try? task.run()
                task.waitUntilExit()
            }
        }
        refreshVolumes()
    }

    private func observeMountEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
    }

    @objc private func refresh() {
        refreshVolumes()
    }
}
