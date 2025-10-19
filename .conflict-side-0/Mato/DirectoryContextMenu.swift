
import SwiftUI

struct DirectoryContextMenu: ViewModifier {
    @ObservedObject var viewModel: DirectoryViewModel
    let ids: Set<DirectoryItem.ID>
    let quickLookAction: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: DirectoryItem.ID.self) { ids in
                // Primary Actions Group
                Group {
                    Button("Open") {
                        viewModel.openSelectedItems(ids)
                    }

                    Button("Open in Terminal") {
                        viewModel.openInTerminal(ids)
                    }
                    .disabled(
                        ids.isEmpty || !viewModel
                            .canOpenInTerminal(ids))
                }

                Divider()

                // Edit Actions Group
                Group {
                    if ids.count == 1 {
                        Button("Rename") {
                            viewModel.startRename(ids.first!)
                        }
                    }

                    Button("Copy") {
                        viewModel.copyItems(ids)
                    }

                    Button("Cut") {
                        viewModel.cutItems(ids)
                    }

                    if viewModel.hasItemsInPasteboard() {
                        Button("Paste") {
                            viewModel.pasteItems()
                        }
                    }

                }

                Divider()

                // Path Actions Group
                Group {
                    Button("Copy Path") {
                        viewModel.copyPaths(ids)
                    }

                    Button("Copy as Pathname") {
                        viewModel.copyAsPathname(ids)
                    }

                    if ids.count == 1 {
                        Button("Copy Alias") {
                            viewModel.copyAlias(ids.first!)
                        }
                    }
                }

                Divider()

                // View Actions Group
                Group {
                    Button("Quick Look") {
                        if let firstId = ids.first, let item = viewModel.getItem(firstId) {
                            quickLookAction(item.url)
                        }
                    }
                    .disabled(ids.isEmpty)

                    Button("Show in Finder") {
                        viewModel.showInFinder(ids)
                    }

                    if ids.count == 1, let item = viewModel.getItem(ids.first!) {
                        Button("Show Package Contents") {
                            viewModel.showPackageContents(item)
                        }
                        .disabled(
                            !item.url.pathExtension.lowercased().contains(
                                "app"
                            ) && !item.isDirectory
                        )
                    }
                }

                Divider()

                // Utility Actions Group
                Group {
                    if viewModel.canCompress(ids) {
                        Button("Compress \"\(viewModel.getCompressionName(ids))\"") {
                            viewModel.compressItems(ids)
                        }
                    }

                    if viewModel.canCreateAlias(ids) {
                        Button("Make Alias") {
                            viewModel.makeAlias(ids)
                        }
                    }

                    Button("Move to Trash") {
                        viewModel.moveToTrash(ids)
                    }
                    .foregroundColor(.red)
                }

                // Services submenu (if needed)
                if !ids.isEmpty {
                    Divider()
                    Button("Services") {
                        // Services are typically handled by the system
                        viewModel.showServices(ids)
                    }
                }
            } primaryAction: { ids in
                viewModel.openSelectedItems(ids)
            }
    }
}
