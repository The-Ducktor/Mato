// SettingsModel.swift
// Stores user settings and persists them
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Observation

@MainActor
@Observable
class SettingsModel {
    static let shared = SettingsModel()
    
    // @AppStorage properties must NOT be marked @ObservationIgnored when used
    // inside an @Observable class — removing that annotation lets the
    // @Observable macro track changes and re-render dependent views.
    @AppStorage("defaultSortMethod") var defaultSortMethod: String = "date"
    @AppStorage("defaultFolder") var defaultFolder: String = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    @AppStorage("defaultPaneCount") var defaultPaneCount: Int = 2
    @AppStorage("viewMode") var viewMode: String = "list"
    @AppStorage("useSavedViewMode") var useSavedViewMode: Bool = true
    
    let sortMethods: [String] = ["name", "date", "size", "type", "created"]
    
    var defaultFolderURL: URL {
        URL(filePath: defaultFolder)
    }
    
    static func keyPathComparator(for method: String) -> [KeyPathComparator<DirectoryItem>] {
        switch method {
        case "name":
            return [KeyPathComparator(\DirectoryItem.name)]
        case "date":
            // "date" means Date Modified — was incorrectly using creationDate
            return [KeyPathComparator(\DirectoryItem.lastModified, order: .reverse)]
        case "size":
            return [KeyPathComparator(\DirectoryItem.size, order: .reverse)]
        case "type":
            return [KeyPathComparator(\DirectoryItem.fileTypeDescription)]
        case "created":
            return [KeyPathComparator(\DirectoryItem.creationDate, order: .reverse)]
        default:
            return [KeyPathComparator(\DirectoryItem.lastModified, order: .reverse)]
        }
    }
}
