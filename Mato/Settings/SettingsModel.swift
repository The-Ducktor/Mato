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

    // @AppStorage cannot be combined with @Observable — the macro synthesises
    // a _propertyName backing store that collides with @AppStorage's own storage.
    // Instead we use plain stored vars (tracked by @Observable) and mirror
    // reads/writes to UserDefaults manually.

    var defaultSortMethod: String {
        didSet { UserDefaults.standard.set(defaultSortMethod, forKey: "defaultSortMethod") }
    }
    var defaultFolder: String {
        didSet { UserDefaults.standard.set(defaultFolder, forKey: "defaultFolder") }
    }
    var defaultPaneCount: Int {
        didSet { UserDefaults.standard.set(defaultPaneCount, forKey: "defaultPaneCount") }
    }
    var viewMode: String {
        didSet { UserDefaults.standard.set(viewMode, forKey: "viewMode") }
    }
    var useSavedViewMode: Bool {
        didSet { UserDefaults.standard.set(useSavedViewMode, forKey: "useSavedViewMode") }
    }

    private init() {
        let ud = UserDefaults.standard
        defaultSortMethod = ud.string(forKey: "defaultSortMethod") ?? "date"
        defaultFolder     = ud.string(forKey: "defaultFolder")
                            ?? FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        defaultPaneCount  = ud.object(forKey: "defaultPaneCount") != nil
                            ? ud.integer(forKey: "defaultPaneCount") : 2
        viewMode          = ud.string(forKey: "viewMode") ?? "list"
        useSavedViewMode  = ud.object(forKey: "useSavedViewMode") != nil
                            ? ud.bool(forKey: "useSavedViewMode") : true
    }

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
