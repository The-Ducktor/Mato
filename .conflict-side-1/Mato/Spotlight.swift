//
//  Spotlight.swift
//  Mato
//
//  Created by Jackson Powell on 7/26/25.
//
import Foundation

func getDateAdded(for filePath: String) -> Date? {
    let url = URL(fileURLWithPath: filePath)
    do {
        let values = try url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        if let added = values.addedToDirectoryDate {
            return added
        }
        return values.creationDate
    } catch {
        return nil
    }
}
