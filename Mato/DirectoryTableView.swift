import SwiftUI
import UniformTypeIdentifiers

struct DirectoryTableView: View {
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var selectedItems: Set<DirectoryItem.ID>
    @Binding var sortOrder: [KeyPathComparator<DirectoryItem>]
    
    var body: some View {
        Table(selection: $selectedItems, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack {
                    ImageIcon(item: .constant(item))
                        .frame(width: 16, height: 16)
                    Text(item.name)
                        .truncationMode(.middle)
                }
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
