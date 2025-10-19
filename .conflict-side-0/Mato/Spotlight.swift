//
//  Spotlight.swift
//  Mato
//
//  Created by Jackson Powell on 7/26/25.
//
import Foundation

func getDateAdded(for filePath: String) -> Date? {
    let task = Process()
    task.launchPath = "/usr/bin/mdls"
    task.arguments = ["-name", "kMDItemDateAdded", "-raw", filePath]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    let fileHandle = pipe.fileHandleForReading
    task.launch()
    
    let data = fileHandle.readDataToEndOfFile()
    task.waitUntilExit()
    
    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return dateFormatter.date(from: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    return nil
}
