//
//  DirectoryPreferences.swift
//  Mato
//
//  Stores per-directory view preferences (view mode, sort order)
//

import Foundation
import SwiftUI

// MARK: - View Mode Enum
enum ViewMode: String, Codable {
    case grid
    case list
}

// MARK: - Directory Preference
struct DirectoryPreference: Codable {
    var viewMode: ViewMode
    var sortMethod: String
    var sortAscending: Bool
    
    init(viewMode: ViewMode = .list, sortMethod: String = "date", sortAscending: Bool = false) {
        self.viewMode = viewMode
        self.sortMethod = sortMethod
        self.sortAscending = sortAscending
    }
}

// MARK: - Directory Preferences Manager
@MainActor
class DirectoryPreferencesManager: ObservableObject {
    static let shared = DirectoryPreferencesManager()
    
    private let userDefaults = UserDefaults.standard
    private let preferencesKey = "directoryPreferences"
    
    // In-memory cache
    private var preferences: [String: DirectoryPreference] = [:]
    
    init() {
        loadPreferences()
    }
    
    // MARK: - Load/Save
    
    private func loadPreferences() {
        guard let data = userDefaults.data(forKey: preferencesKey),
              let decoded = try? JSONDecoder().decode([String: DirectoryPreference].self, from: data) else {
            return
        }
        preferences = decoded
    }
    
    private func savePreferences() {
        guard let encoded = try? JSONEncoder().encode(preferences) else {
            return
        }
        userDefaults.set(encoded, forKey: preferencesKey)
    }
    
    // MARK: - Get/Set Preferences
    
    func getPreference(for url: URL) -> DirectoryPreference {
        let key = url.path
        return preferences[key] ?? DirectoryPreference()
    }
    
    func setPreference(for url: URL, preference: DirectoryPreference) {
        let key = url.path
        preferences[key] = preference
        savePreferences()
    }
    
    func setViewMode(for url: URL, viewMode: ViewMode) {
        let key = url.path
        var pref = preferences[key] ?? DirectoryPreference()
        pref.viewMode = viewMode
        preferences[key] = pref
        savePreferences()
    }
    
    func setSortMethod(for url: URL, sortMethod: String, ascending: Bool) {
        let key = url.path
        var pref = preferences[key] ?? DirectoryPreference()
        pref.sortMethod = sortMethod
        pref.sortAscending = ascending
        preferences[key] = pref
        savePreferences()
    }
}
