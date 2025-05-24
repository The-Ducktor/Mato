//
//  PaneAreaView.swift
//  Mato
//
//  Created by The-Ducktor on 5/24/25.
//

import SwiftUI

struct PaneAreaView: View {
    @ObservedObject var paneManager: PaneManager
    
    var body: some View {
        VStack(spacing: 0) {
            if !paneManager.panes.isEmpty {
                switch paneManager.layout {
                case .single:
                    if let activePane = paneManager.activePane {
                        FileManagerPane(
                            viewModel: activePane,
                            isActive: true,
                            onActivate: { }
                        )
                    }
                    
                case .dual:
                    ResizableDualPaneView(paneManager: paneManager)
                    
                case .triple:
                    ResizableTriplePaneView(paneManager: paneManager)
                    
                case .quad:
                    ResizableQuadPaneView(paneManager: paneManager)
                }
            } else {
                Text("No panes available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Resizable Dual Pane View
struct ResizableDualPaneView: View {
    @ObservedObject var paneManager: PaneManager
    @State private var splitPosition: CGFloat = 0.5
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if paneManager.panes.count >= 1 {
                    FileManagerPane(
                        viewModel: paneManager.panes[0],
                        isActive: paneManager.activePaneIndex == 0,
                        onActivate: { paneManager.setActivePane(index: 0) }
                    )
                    .frame(width: geometry.size.width * splitPosition)
                }
                
                if paneManager.panes.count >= 2 {
                    // Native-style resize handle
                    NativeResizeHandle(
                        isVertical: true,
                        containerSize: geometry.size.width
                    ) { deltaRatio in
                        splitPosition = max(0.15, min(0.85, splitPosition + deltaRatio))
                    }
                    
                    FileManagerPane(
                        viewModel: paneManager.panes[1],
                        isActive: paneManager.activePaneIndex == 1,
                        onActivate: { paneManager.setActivePane(index: 1) }
                    )
                    .frame(width: geometry.size.width * (1 - splitPosition))
                }
            }
        }
    }
}

// MARK: - Resizable Triple Pane View
struct ResizableTriplePaneView: View {
    @ObservedObject var paneManager: PaneManager
    @State private var firstSplit: CGFloat = 0.33
    @State private var secondSplit: CGFloat = 0.67
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(0..<min(3, paneManager.panes.count), id: \.self) { index in
                    if index > 0 {
                        NativeResizeHandle(
                            isVertical: true,
                            containerSize: geometry.size.width
                        ) { deltaRatio in
                            if index == 1 {
                                let newFirst = firstSplit + deltaRatio
                                firstSplit = max(0.1, min(secondSplit - 0.1, newFirst))
                            } else if index == 2 {
                                let newSecond = secondSplit + deltaRatio
                                secondSplit = max(firstSplit + 0.1, min(0.9, newSecond))
                            }
                        }
                    }
                    
                    FileManagerPane(
                        viewModel: paneManager.panes[index],
                        isActive: paneManager.activePaneIndex == index,
                        onActivate: { paneManager.setActivePane(index: index) }
                    )
                    .frame(width: paneWidth(for: index, in: geometry.size.width))
                }
            }
        }
    }
    
    private func paneWidth(for index: Int, in totalWidth: CGFloat) -> CGFloat {
        switch index {
        case 0:
            return totalWidth * firstSplit
        case 1:
            return totalWidth * (secondSplit - firstSplit)
        case 2:
            return totalWidth * (1 - secondSplit)
        default:
            return 0
        }
    }
}

// MARK: - Resizable Quad Pane View
struct ResizableQuadPaneView: View {
    @ObservedObject var paneManager: PaneManager
    @State private var verticalSplit: CGFloat = 0.5
    @State private var topLeftWidth: CGFloat = 0.5
    @State private var bottomLeftWidth: CGFloat = 0.5
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top row
                HStack(spacing: 0) {
                    if paneManager.panes.count >= 1 {
                        FileManagerPane(
                            viewModel: paneManager.panes[0],
                            isActive: paneManager.activePaneIndex == 0,
                            onActivate: { paneManager.setActivePane(index: 0) }
                        )
                        .frame(width: geometry.size.width * topLeftWidth)
                    }
                    
                    if paneManager.panes.count >= 2 {
                        NativeResizeHandle(
                            isVertical: true,
                            containerSize: geometry.size.width
                        ) { deltaRatio in
                            topLeftWidth = max(0.15, min(0.85, topLeftWidth + deltaRatio))
                        }
                        
                        FileManagerPane(
                            viewModel: paneManager.panes[1],
                            isActive: paneManager.activePaneIndex == 1,
                            onActivate: { paneManager.setActivePane(index: 1) }
                        )
                        .frame(width: geometry.size.width * (1 - topLeftWidth))
                    }
                }
                .frame(height: geometry.size.height * verticalSplit)
                
                if paneManager.panes.count >= 3 {
                    // Horizontal resize handle
                    NativeResizeHandle(
                        isVertical: false,
                        containerSize: geometry.size.height
                    ) { deltaRatio in
                        verticalSplit = max(0.15, min(0.85, verticalSplit + deltaRatio))
                    }
                    
                    // Bottom row
                    HStack(spacing: 0) {
                        FileManagerPane(
                            viewModel: paneManager.panes[2],
                            isActive: paneManager.activePaneIndex == 2,
                            onActivate: { paneManager.setActivePane(index: 2) }
                        )
                        .frame(width: geometry.size.width * bottomLeftWidth)
                        
                        if paneManager.panes.count >= 4 {
                            NativeResizeHandle(
                                isVertical: true,
                                containerSize: geometry.size.width
                            ) { deltaRatio in
                                bottomLeftWidth = max(0.15, min(0.85, bottomLeftWidth + deltaRatio))
                            }
                            
                            FileManagerPane(
                                viewModel: paneManager.panes[3],
                                isActive: paneManager.activePaneIndex == 3,
                                onActivate: { paneManager.setActivePane(index: 3) }
                            )
                            .frame(width: geometry.size.width * (1 - bottomLeftWidth))
                        }
                    }
                    .frame(height: geometry.size.height * (1 - verticalSplit))
                }
            }
        }
    }
}

// MARK: - Native Resize Handle
struct NativeResizeHandle: View {
    let isVertical: Bool
    let containerSize: CGFloat
    let onDrag: (CGFloat) -> Void
    
    @State private var isDragging = false
    @State private var lastLocation: CGFloat = 0
    
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(
                width: isVertical ? 1 : nil,
                height: isVertical ? nil : 1
            )
            .background(
                // Larger invisible drag area
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: isVertical ? 8 : nil,
                        height: isVertical ? nil : 8
                    )
                    .cursor(isVertical ? .resizeLeftRight : .resizeUpDown)
            )
            .overlay(
                // Visual feedback only when dragging
                Rectangle()
                    .fill(isDragging ? .blue.opacity(0.5) : .clear)
                    .frame(
                        width: isVertical ? 3 : nil,
                        height: isVertical ? nil : 3
                    )
            )
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let currentLocation = isVertical ? value.location.x : value.location.y
                        
                        if !isDragging {
                            isDragging = true
                            lastLocation = currentLocation
                            return
                        }
                        
                        // Calculate immediate delta
                        let delta = currentLocation - lastLocation
                        let deltaRatio = delta / containerSize
                        
                        // Apply change immediately without animation
                        onDrag(deltaRatio)
                        
                        lastLocation = currentLocation
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastLocation = 0
                    }
            )
    }
}

// MARK: - Cursor Modifier
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

#Preview {
    PaneAreaView(paneManager: PaneManager())
}
