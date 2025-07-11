import SwiftUI
import UniformTypeIdentifiers

struct DirectoryTableView: View {
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var selectedItems: Set<DirectoryItem.ID>
    @Binding var sortOrder: [KeyPathComparator<DirectoryItem>]
    @State private var color: Color = .clear // testing
    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(selection: $selectedItems, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { item in
                    ZStack {
                        Rectangle()
                            .foregroundColor(isDropTargeted ? Color.blue.opacity(0.3) : .clear) // Highlight on hover
                            .contentShape(Rectangle())
                            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                                Task {
                                    var files: [URL] = []
                                    
                                    for provider in providers {
                                        // Await the async loadItem
                                        if let url = try? await loadFileURL(from: provider) {
                                            print("Dropped file URL: \(url) to \(item.url)")
                                            
                                            if item.url == url {
                                                print("Dropped on itself, ignoring.")
                                                continue
                                            }
                                            
                                            if item.isDirectory {
                                                files.append(url)
                                            } else {
                                                print("Cannot drop files on a file item.")
                                            }
                                        }
                                    }
                                    
                                    if !files.isEmpty {
                                        await viewModel.moveFiles(from: files, to: item.url)
                                        color = .green // drop occurred
                                    }
                                }
                                return true
                            }



                            HStack {
                                ImageIcon(item: .constant(item))
                                           .frame(width: 16, height: 16)
                                       Text(item.name)
                                           .truncationMode(.middle)
                                       Spacer()
                            }
                            .padding(.horizontal)
                        }
                        
                        //.border(Color.gray) // For debugging layout

                }
                .width(min: 180)
                .alignment(.leading)

                TableColumn("Size", value: \.size) { item in
                    if item.isDirectory {
                        Text("--")
                    } else {
                        Text(viewModel.formatFileSize(item.size))
                    }
                }
                .width(min: 100)
                .alignment(.trailing)

                TableColumn("Kind", value: \.fileTypeDescription) { item in
                    Text(item.fileTypeDescription)
                }
                .alignment(.trailing)

                TableColumn("Date Modified", value: \.lastModified) { item in
                    Text(formatDate(item.lastModified))
                }
                TableColumn("Date Created", value: \.creationDate) { item in
                    Text(formatDate(item.creationDate))
                }
                .width(min: 150)
                .alignment(.trailing)
            } rows: {
                ForEach(viewModel.items) { item in
                    TableRow(item)
                        .draggable(item.url)
                     
                }
            }
            .onDrop(of: [UTType.fileURL], delegate: TableDropDelegate(viewModel: viewModel))
        }
    }
    private func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    continuation.resume(throwing: NSError(domain: "InvalidData", code: 0, userInfo: nil))
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) || calendar.isDateInTomorrow(date) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .full
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

// You'll need to create a new drop delegate for the table
struct TableDropDelegate: DropDelegate {
    let viewModel: DirectoryViewModel
    var setDropMessage: ((String) -> Void)? = nil
    
    func performDrop(info: DropInfo) -> Bool {
        let itemProviders = info.itemProviders(for: [.fileURL])
        guard !itemProviders.isEmpty else { return false }

        var urls: [URL] = []
        let dispatchGroup = DispatchGroup()

        for itemProvider in itemProviders {
            dispatchGroup.enter()
            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    urls.append(url)
                }
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            Task { @MainActor in
                if let currentDirectory = viewModel.currentDirectory {
                    viewModel.moveFiles(from: urls, to: currentDirectory)
                    // Compose message
                    let fileNames = urls.map { $0.lastPathComponent }.joined(separator: ", ")
                    let source = urls.first?.deletingLastPathComponent().path ?? "?"
                    let dest = currentDirectory.path
                    let message = "file \(fileNames) from \(source) to \(dest)"
                    setDropMessage?(message)
                }
            }
        }
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Optional: Handle visual feedback when drag enters
    }
    
    func dropExited(info: DropInfo) {
        // Optional: Handle visual feedback when drag exits
    }
}
