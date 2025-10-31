//
//  PinnedFolder.swift
//  Mato
//
//  Created by on 5/23/25.
//

import Foundation

struct PinnedFolder: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    
    init(url: URL, name: String? = nil) {
        self.id = UUID()
        self.url = url
        self.name = name ?? url.lastPathComponent
    }
}

@MainActor
class PinnedFolderStore: ObservableObject {
    @Published var pinnedFolders: [PinnedFolder] = []
    private let storeKey = "pinnedFolders"
    
    static let shared = PinnedFolderStore()
    
    init() {
        loadPinnedFolders()
    }
    
    func addPinnedFolder(_ url: URL, name: String? = nil) {
        let folder = PinnedFolder(url: url, name: name)
        if !pinnedFolders.contains(where: { $0.url == url }) {
            pinnedFolders.append(folder)
            savePinnedFolders()
        }
    }
    
    func removePinnedFolder(at index: Int) {
        guard index < pinnedFolders.count else { return }
        pinnedFolders.remove(at: index)
        savePinnedFolders()
    }
    
    func removePinnedFolder(with id: UUID) {
        if let index = pinnedFolders.firstIndex(where: { $0.id == id }) {
            pinnedFolders.remove(at: index)
            savePinnedFolders()
        }
    }
    
    private func loadPinnedFolders() {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return }
        
        do {
            let decoder = JSONDecoder()
            pinnedFolders = try decoder.decode([PinnedFolder].self, from: data)
        } catch {
            print("Failed to load pinned folders: \(error.localizedDescription)")
        }
    }
    
    private func savePinnedFolders() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pinnedFolders)
            UserDefaults.standard.set(data, forKey: storeKey)
        } catch {
            print("Failed to save pinned folders: \(error.localizedDescription)")
        }
    }
}
