
//  PaneAreaView.swift
//  Mato
//
//  Created by The-Ducktor on 5/24/25.
//

import SwiftUI

struct PaneAreaView: View {
    @ObservedObject var paneManager: PaneManager

    // Persist split positions using @AppStorage
    @AppStorage("dualSplit") private var dualSplit: Double = 0.5
    @AppStorage("tripleFirstSplit") private var tripleFirstSplit: Double = 0.33
    @AppStorage("tripleSecondSplit") private var tripleSecondSplit: Double = 0.67
    @AppStorage("quadVerticalSplit") private var quadVerticalSplit: Double = 0.5
    @AppStorage("quadTopLeftWidth") private var quadTopLeftWidth: Double = 0.5
    @AppStorage("quadBottomLeftWidth") private var quadBottomLeftWidth: Double = 0.5
    
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Already active in single pane mode
                        }
                    }
                    
                case .dual:
                    ResizableDualPaneView(
                        paneManager: paneManager,
                        splitPosition: Binding(
                            get: { dualSplit },
                            set: { dualSplit = $0 }
                        )
                    )
                    
                case .triple:
                    ResizableTriplePaneView(
                        paneManager: paneManager,
                        firstSplit: Binding(
                            get: { tripleFirstSplit },
                            set: { tripleFirstSplit = $0 }
                        ),
                        secondSplit: Binding(
                            get: { tripleSecondSplit },
                            set: { tripleSecondSplit = $0 }
                        )
                    )
                    
                case .quad:
                    ResizableQuadPaneView(
                        paneManager: paneManager,
                        verticalSplit: Binding(
                            get: { quadVerticalSplit },
                            set: { quadVerticalSplit = $0 }
                        ),
                        topLeftWidth: Binding(
                            get: { quadTopLeftWidth },
                            set: { quadTopLeftWidth = $0 }
                        ),
                        bottomLeftWidth: Binding(
                            get: { quadBottomLeftWidth },
                            set: { quadBottomLeftWidth = $0 }
                        )
                    )
                }
            } else {
                Text("No panes available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Draggable Pane Wrapper
struct DraggablePane: View {
    let paneIndex: Int
    @ObservedObject var paneManager: PaneManager
    @Binding var draggedPaneIndex: Int?
    @State private var isDropTarget = false
    @State private var isDragging = false
    
    var body: some View {
        FileManagerPane(
            viewModel: paneManager.panes[paneIndex],
            isActive: paneManager.activePaneIndex == paneIndex,
            onActivate: { paneManager.setActivePane(index: paneIndex) }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            paneManager.setActivePane(index: paneIndex)
        }
        .draggable("\(paneIndex)") {
            // Custom drag preview
            Text("Pane \(paneIndex + 1)")
                .padding()
                .background(Color.accentColor.opacity(0.8))
                .cornerRadius(8)
                .onAppear {
                    draggedPaneIndex = paneIndex
                    isDragging = true
                }
        }
        .dropDestination(for: String.self) { items, location in
            guard let draggedIndexString = items.first,
                  let draggedIndex = Int(draggedIndexString),
                  draggedIndex != paneIndex else {
                draggedPaneIndex = nil
                isDragging = false
                return false
            }
            
            paneManager.swapPanes(from: draggedIndex, to: paneIndex)
            draggedPaneIndex = nil
            isDragging = false
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .opacity(draggedPaneIndex == paneIndex ? 0.5 : 1.0)
               .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTarget && draggedPaneIndex != paneIndex ? Color.accentColor : Color.clear, lineWidth: 3)
                .padding(2)
        )
   
        .onChange(of: isDragging) { oldValue, newValue in
            if !newValue {
                // Small delay to ensure drop completes first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    draggedPaneIndex = nil
                }
            }
        }
    }
}

// MARK: - Resizable Dual Pane View
struct ResizableDualPaneView: View {
    @ObservedObject var paneManager: PaneManager
    @Binding var splitPosition: Double
    @State private var draggedPaneIndex: Int?
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if paneManager.panes.count >= 1 {
                    DraggablePane(
                        paneIndex: 0,
                        paneManager: paneManager,
                        draggedPaneIndex: $draggedPaneIndex
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
                    
                    DraggablePane(
                        paneIndex: 1,
                        paneManager: paneManager,
                        draggedPaneIndex: $draggedPaneIndex
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
    @Binding var firstSplit: Double
    @Binding var secondSplit: Double
    @State private var draggedPaneIndex: Int?
    
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
                    
                    DraggablePane(
                        paneIndex: index,
                        paneManager: paneManager,
                        draggedPaneIndex: $draggedPaneIndex
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
    @Binding var verticalSplit: Double
    @Binding var topLeftWidth: Double
    @Binding var bottomLeftWidth: Double
    @State private var draggedPaneIndex: Int?
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top row
                HStack(spacing: 0) {
                    if paneManager.panes.count >= 1 {
                        DraggablePane(
                            paneIndex: 0,
                            paneManager: paneManager,
                            draggedPaneIndex: $draggedPaneIndex
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
                        
                        DraggablePane(
                            paneIndex: 1,
                            paneManager: paneManager,
                            draggedPaneIndex: $draggedPaneIndex
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
                        DraggablePane(
                            paneIndex: 2,
                            paneManager: paneManager,
                            draggedPaneIndex: $draggedPaneIndex
                        )
                        .frame(width: geometry.size.width * bottomLeftWidth)
                        
                        if paneManager.panes.count >= 4 {
                            NativeResizeHandle(
                                isVertical: true,
                                containerSize: geometry.size.width
                            ) { deltaRatio in
                                bottomLeftWidth = max(0.15, min(0.85, bottomLeftWidth + deltaRatio))
                            }
                            
                            DraggablePane(
                                paneIndex: 3,
                                paneManager: paneManager,
                                draggedPaneIndex: $draggedPaneIndex
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
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // Visible separator line
            Rectangle()
                .fill(isDragging ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(
                    width: isVertical ? 1 : nil,
                    height: isVertical ? nil : 1
                )
            
            // Larger invisible hit area for easier grabbing
            Rectangle()
                .fill(.clear)
                .frame(
                    width: isVertical ? 10 : nil,
                    height: isVertical ? nil : 10
                )
                .contentShape(Rectangle())
            
            // Visual feedback when hovering or dragging
            if isHovering || isDragging {
                Rectangle()
                    .fill(Color.accentColor.opacity(isDragging ? 0.3 : 0.15))
                    .frame(
                        width: isVertical ? 4 : nil,
                        height: isVertical ? nil : 4
                    )
            }
        }
        .cursor(isVertical ? .resizeLeftRight : .resizeUpDown)
        .onHover { hovering in
            isHovering = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    
                    // Calculate delta based on translation
                    let delta = isVertical ? value.translation.width : value.translation.height
                    let deltaRatio = delta / containerSize
                    
                    // Apply change
                    onDrag(deltaRatio)
                }
                .onEnded { _ in
                    isDragging = false
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
