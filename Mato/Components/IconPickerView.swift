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
    
    let iconCategories: [(String, [String])] = [
        ("Folders", [
            "folder", "folder.fill", "folder.badge.plus", "folder.badge.minus",
            "folder.badge.gear", "folder.badge.person.crop", "externaldrive",
            "externaldrive.fill", "internaldrive", "internaldrive.fill"
        ]),
        ("Files & Documents", [
            "doc", "doc.fill", "doc.text", "doc.text.fill",
            "note.text", "newspaper", "book", "book.fill"
        ]),
        ("Media", [
            "photo", "photo.fill", "film", "film.fill",
            "music.note", "headphones", "tv", "tv.fill"
        ]),
        ("Development", [
            "hammer", "hammer.fill", "wrench", "wrench.fill",
            "terminal", "terminal.fill", "chevron.left.forwardslash.chevron.right",
            "curlybraces"
        ]),
        ("Objects", [
            "house", "house.fill", "building.2", "building.2.fill",
            "briefcase", "briefcase.fill", "tray", "tray.fill",
            "archivebox", "archivebox.fill", "shippingbox", "shippingbox.fill"
        ]),
        ("Symbols", [
            "star", "star.fill", "heart", "heart.fill",
            "flag", "flag.fill", "bookmark", "bookmark.fill",
            "tag", "tag.fill", "bolt", "bolt.fill"
        ]),
        ("Shapes", [
            "circle", "circle.fill", "square", "square.fill",
            "triangle", "triangle.fill", "diamond", "diamond.fill",
            "hexagon", "hexagon.fill", "octagon", "octagon.fill"
        ]),
        ("Nature", [
            "leaf", "leaf.fill", "tree", "tree.fill",
            "drop", "drop.fill", "flame", "flame.fill",
            "sun.max", "sun.max.fill", "moon", "moon.fill"
        ])
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose Icon")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            Divider()
            
            // Icon Grid
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(iconCategories, id: \.0) { category, icons in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 6)], spacing: 6) {
                                ForEach(icons, id: \.self) { icon in
                                    Button {
                                        onSelect(icon)
                                        dismiss()
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.system(size: 14))
                                            .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                            .frame(width: 32, height: 32)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(selectedIcon == icon ? Color.accentColor : Color.clear)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .strokeBorder(
                                                        selectedIcon == icon ? Color.clear : Color.primary.opacity(0.1),
                                                        lineWidth: 0.5
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(icon)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 320, height: 400)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }
}

#Preview {
    IconPickerView(selectedIcon: "folder") { icon in
        print("Selected: \(icon)")
    }
}
