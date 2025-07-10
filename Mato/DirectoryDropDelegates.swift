
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

        guard let provider = info.itemProviders(for: [.fileURL]).first else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
            guard let urlData = data as? Data, let sourceURL = URL(dataRepresentation: urlData, relativeTo: nil) else {
                return
            }

            let destinationURL = item.url

            Task { @MainActor in
                viewModel.moveFile(from: sourceURL, to: destinationURL)
            }
        }

        return true
    }
}
