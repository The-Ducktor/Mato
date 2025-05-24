//
//  DirectoryItem.swift
//  Mato
//
//  Created by on 5/22/25.
//

import Foundation
import UniformTypeIdentifiers

public struct DirectoryItem: Identifiable, Hashable, Sendable {
    public let id = UUID()
    let isDirectory: Bool
    let url: URL
    let name: String?
    let size: Int?
    let fileType: UTType?
    let lastModified: Date?
    let creationDate: Date?
    let isHidden: Bool?
}
