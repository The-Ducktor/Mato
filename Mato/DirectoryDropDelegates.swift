
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Delegates

struct DirectoryDropDelegate: DropDelegate {
    let viewModel: DirectoryViewModel

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.fileURL]).first else {
            return false
        }

        item.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
            guard let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) else {
                return
            }

            Task { @MainActor in
                if let currentDirectory = viewModel.currentDirectory {
                    viewModel.moveFile(from: url, to: currentDirectory)
                }
            }
        }

        return true
    }
}

struct ItemDropDelegate: DropDelegate {
    let item: DirectoryItem
    let viewModel: DirectoryViewModel

    func performDrop(info: DropInfo) -> Bool {
        guard item.isDirectory else {
            return false
        }

        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        var sourceURLs: [URL] = []
        let dispatchGroup = DispatchGroup()

        for itemProvider in itemProviders {
            dispatchGroup.enter()
            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    sourceURLs.append(url)
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            let destinationURL = item.url
            Task { @MainActor in
                viewModel.moveFiles(from: sourceURLs, to: destinationURL)
            }
        }

        return true
    }
}
