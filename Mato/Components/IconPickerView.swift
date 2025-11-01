//
//  IconPickerView.swift
//  Mato
//
//  Created on 11/1/25.
//

import SwiftUI

struct IconPickerView: View {
    let selectedIcon: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var allIcons: [String] = []
    
    init(selectedIcon: String, onSelect: @escaping (String) -> Void) {
        self.selectedIcon = selectedIcon
        self.onSelect = onSelect
    }
    
    @State private var iconsByCategory: [(String, [String])] = []
    @State private var selectedCategory: String = "All"
    
    var categories: [String] {
        ["All"] + iconsByCategory.map { $0.0 }.sorted()
    }
    
    var filteredIcons: [String] {
        let categoryFiltered: [String]
        if selectedCategory == "All" {
            categoryFiltered = allIcons
        } else {
            categoryFiltered = iconsByCategory.first(where: { $0.0 == selectedCategory })?.1 ?? []
        }
        
        if searchText.isEmpty {
            return categoryFiltered
        } else {
            return categoryFiltered.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private func loadIcons() {
        guard let fileURL = Bundle.main.url(forResource: "sfsymbol6", withExtension: "txt") else {
            print("Could not find sfsymbol6.txt")
            return
        }
        
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            var categoryDict: [String: [String]] = [:]
            
            allIcons = content.components(separatedBy: .newlines)
                .compactMap { line -> (String, [String])? in
                    guard !line.isEmpty else { return nil }
                    
                    let components = line.components(separatedBy: ",")
                    let iconName = components.first?.trimmingCharacters(in: .whitespaces) ?? ""
                    guard !iconName.isEmpty else { return nil }
                    
                    // Extract categories (tags after the icon name)
                    let tags = components.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
                    
                    return (iconName, tags)
                }
                .map { iconName, tags in
                    // Organize icons by their categories
                    if tags.isEmpty {
                        // Icons without tags go to "Uncategorized"
                        categoryDict["Uncategorized", default: []].append(iconName)
                    } else {
                        for tag in tags {
                            // Clean up category names
                            let categoryName = tag.capitalized
                                .replacingOccurrences(of: "Objectsandtools", with: "Objects & Tools")
                            categoryDict[categoryName, default: []].append(iconName)
                        }
                    }
                    return iconName
                }
            
            // Sort icons within each category
            iconsByCategory = categoryDict.map { (key, value) in
                (key, value.sorted())
            }.sorted { $0.0 < $1.0 }
            
        } catch {
            print("Error reading icons file: \(error)")
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Search
            VStack(spacing: 8) {
                HStack {
                    Text("Choose Icon")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(filteredIcons.count) icons")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                
                // Category Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(categories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Text(category)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(selectedCategory == category ?
                                                  Color.accentColor : Color(nsColor: .controlBackgroundColor))
                                    )
                                    .foregroundStyle(selectedCategory == category ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 24)
                
                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Search icons...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            Divider()
            
            // Icon Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 4)], spacing: 4) {
                    ForEach(filteredIcons, id: \.self) { icon in
                        Button {
                            onSelect(icon)
                            dismiss()
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 13))
                                .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(selectedIcon == icon ? Color.accentColor : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(
                                            selectedIcon == icon ? Color.clear : Color.primary.opacity(0.08),
                                            lineWidth: 0.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(icon)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 340, height: 450)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .onAppear {
            loadIcons()
        }
    }
}

#Preview {
    IconPickerView(selectedIcon: "folder") { icon in
        print("Selected: \(icon)")
    }
}
