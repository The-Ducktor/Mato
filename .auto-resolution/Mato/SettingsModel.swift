// SettingsModel.swift
// Stores user settings and persists them
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class SettingsModel: ObservableObject {
    static let shared = SettingsModel()
    
    @AppStorage("defaultSortMethod") var defaultSortMethod: String = "date"
    @AppStorage("defaultFolder") var defaultFolder: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage("defaultPaneCount") var defaultPaneCount: Int = 2
    
    let sortMethods: [String] = ["name", "date", "size", "type","created"]
    
    var defaultFolderURL: URL {
        URL(fileURLWithPath: defaultFolder)
    }
    
    static func keyPathComparator(for method: String) -> [KeyPathComparator<DirectoryItem>] {
        switch method {
        case "name":
            return [KeyPathComparator(\DirectoryItem.name)]
        case "date":
            return [KeyPathComparator(\DirectoryItem.creationDate, order: .reverse)]
        case "size":
            return [KeyPathComparator(\DirectoryItem.size, order: .reverse)]
        case "type":
            return [KeyPathComparator(\DirectoryItem.fileTypeDescription)]
        case "created":
            return [KeyPathComparator(\DirectoryItem.creationDate, order: .reverse)]
        default:
            return [KeyPathComparator(\DirectoryItem.creationDate, order: .reverse)]
        }
    }
}
