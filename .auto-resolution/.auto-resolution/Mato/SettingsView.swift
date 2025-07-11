import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsModel.shared
    @State private var folderPath: String
    @State private var showingFolderPicker = false
    @State private var sliderValue: Double
    
    init() {
        let defaultCount = Double(SettingsModel.shared.defaultPaneCount)
        _folderPath = State(initialValue: SettingsModel.shared.defaultFolder)
        _sliderValue = State(initialValue: defaultCount)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header - Clean and minimal like Safari preferences
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.accentColor)
                        
                        Text("Preferences")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    
                    Text("Customize your workspace settings")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
                
                // Settings Cards - Modern card-based layout
                VStack(spacing: 16) {
                    // Sort Method Card
                    SettingsCard(
                        title: "Default Sort Method",
                        subtitle: "Choose how items are sorted by default",
                        icon: "arrow.up.arrow.down"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Sort by", selection: $settings.defaultSortMethod) {
                                ForEach(settings.sortMethods, id: \.self) { method in
                                    Text(method.capitalized).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.regular)
                        }
                    }
                   
                    
                    // Folder Selection Card
                    SettingsCard(
                        title: "Default Folder",
                        subtitle: "Set the folder that opens when you start the app",
                        icon: "folder"
                    ) {
                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                    
                                    if folderPath.isEmpty {
                                        Text("No folder selected")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 13))
                                    } else {
                                        Text(URL(fileURLWithPath: folderPath).lastPathComponent)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.primary)
                                        
                                        Text(folderPath)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Choose...") {
                                    showingFolderPicker = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .help("Select a folder")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                            )
                            
                            if !folderPath.isEmpty {
                                HStack {
                                    Spacer()
                                    Button("Set as Default") {
                                        settings.defaultFolder = folderPath
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.regular)
                                    .help("Apply the folder path as default")
                                }
                            }
                        }
                        .fileImporter(
                            isPresented: $showingFolderPicker,
                            allowedContentTypes: [.folder],
                            allowsMultipleSelection: false
                        ) { result in
                            switch result {
                            case .success(let urls):
                                if let url = urls.first {
                                    folderPath = url.path
                                    settings.defaultFolder = url.path
                                }
                            case .failure(let error):
                                print("Folder selection error: \(error.localizedDescription)")
                            }
                        }
                    }
                    
                    // Panel Count Card
                    SettingsCard(
                        title: "Workspace Layout",
                        subtitle: "Configure how many panels to display",
                        icon: "rectangle.split.3x1"
                    ) {
                        VStack(spacing: 20) {
                            HStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Number of Panels")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    HStack(spacing: 12) {
                                        Slider(value: $sliderValue, in: 1...4, step: 1)
                                            .frame(width: 140)
                                            .controlSize(.regular)
                                        
                                        Text("\(Int(sliderValue))")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.accentColor)
                                            .frame(width: 24, alignment: .center)
                                    }
                                    
                                    Text(panelDescription(for: Int(sliderValue)))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .frame(width: 180, height: 50, alignment: .leading) // set explict size for info text
                                }
                                
                                Spacer()
                                
                                ModernPanelPreview(panelCount: Int(sliderValue))
                                    .frame(width: 160, height: 100)
                                    .animation(.easeInOut(duration: 0.3), value: sliderValue)
                            }
                        }
                        .onChange(of: sliderValue) { _, newValue in
                            settings.defaultPaneCount = Int(newValue)
                        }
                        .help("Use the slider to select how many panels to display")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .frame(minWidth: 520, maxWidth: 680, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func panelDescription(for count: Int) -> String {
        switch count {
        case 1: return "Single panel view for focused work"
        case 2: return "Split view for comparing content"
        case 3: return "Three-panel layout for multitasking"
        case 4: return "Quad view for maximum productivity"
        default: return ""
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let content: Content
    
    init(title: String, subtitle: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 20, height: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Card Content
            VStack(alignment: .leading, spacing: 0) {
                content
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct ModernPanelPreview: View {
    let panelCount: Int
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            
            ZStack {
                // Background container
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(NSColor.windowBackgroundColor),
                                Color(NSColor.windowBackgroundColor).opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(NSColor.separatorColor).opacity(0.3),
                                        Color(NSColor.separatorColor).opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                
                // Panel representations
                ForEach(1...4, id: \.self) { panelIndex in
                    let frame = panelFrame(for: panelIndex, totalWidth: width, totalHeight: height)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    panelColor(for: panelIndex),
                                    panelColor(for: panelIndex).opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(panelColor(for: panelIndex).opacity(0.3), lineWidth: 0.5)
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(frame.center)
                        .opacity(panelIndex <= panelCount ? 1 : 0)
                        .scaleEffect(panelIndex <= panelCount ? 1 : 0.7)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: panelCount)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func panelColor(for index: Int) -> Color {
        switch index {
        case 1: return Color.accentColor
        case 2: return Color.blue
        case 3: return Color.green
        case 4: return Color.orange
        default: return Color.accentColor
        }
    }
    
    private func panelFrame(for panel: Int, totalWidth: CGFloat, totalHeight: CGFloat) -> (width: CGFloat, height: CGFloat, center: CGPoint) {
        let padding: CGFloat = 10
        let spacing: CGFloat = 4
        
        switch panelCount {
        case 1:
            return (
                width: totalWidth - padding * 2,
                height: totalHeight - padding * 2,
                center: CGPoint(x: totalWidth / 2, y: totalHeight / 2)
            )
            
        case 2:
            let panelWidth = (totalWidth - padding * 2 - spacing) / 2
            let panelHeight = totalHeight - padding * 2
            let yCenter = totalHeight / 2
            
            if panel == 1 {
                return (panelWidth, panelHeight, CGPoint(x: padding + panelWidth/2, y: yCenter))
            } else if panel == 2 {
                return (panelWidth, panelHeight, CGPoint(x: padding + panelWidth + spacing + panelWidth/2, y: yCenter))
            }
            
        case 3:
            let panelWidth = (totalWidth - padding * 2 - spacing * 2) / 3
            let panelHeight = totalHeight - padding * 2
            let yCenter = totalHeight / 2
            
            if panel == 1 {
                return (panelWidth, panelHeight, CGPoint(x: padding + panelWidth/2, y: yCenter))
            } else if panel == 2 {
                return (panelWidth, panelHeight, CGPoint(x: padding + panelWidth + spacing + panelWidth/2, y: yCenter))
            } else if panel == 3 {
                return (panelWidth, panelHeight, CGPoint(x: padding + 2 * (panelWidth + spacing) + panelWidth/2, y: yCenter))
            }
            
        case 4:
            let panelWidth = (totalWidth - padding * 2 - spacing) / 2
            let panelHeight = (totalHeight - padding * 2 - spacing) / 2
            
            let topY = padding + panelHeight/2
            let bottomY = padding + panelHeight + spacing + panelHeight/2
            
            if panel == 1 {
                return (panelWidth, panelHeight, CGPoint(x: padding + panelWidth/2, y: topY))
            } else if panel == 2 {
                return (panelWidth, panelHeight, CGPoint(x: padding + panelWidth + spacing + panelWidth/2, y: topY))
            } else if panel == 3 {
                return (panelWidth, panelHeight, CGPoint(x: padding + panelWidth/2, y: bottomY))
            } else if panel == 4 {
                return (panelWidth, panelHeight, CGPoint(x: padding + panelWidth + spacing + panelWidth/2, y: bottomY))
            }
            
        default:
            return (
                width: totalWidth - padding * 2,
                height: totalHeight - padding * 2,
                center: CGPoint(x: totalWidth / 2, y: totalHeight / 2)
            )
        }
        
        return (0, 0, .zero)
    }
}
|||||||
