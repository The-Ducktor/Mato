struct PathBar: View {
    @State private var isEditing = false
    @State private var pathString: String
    let path: URL
    
    init(path: URL) {
        self.path = path
        self._pathString = State(initialValue: path.path)
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            if isEditing {
                TextField("", text: $pathString, onCommit: {
                    isEditing = false
                    // Optionally update `path` based on pathString
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    isEditing = false
                }
                .onDisappear {
                    isEditing = false
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(pathComponents(path: URL(fileURLWithPath: pathString)), id: \.self) { component in
                        Text(component)
                            .font(.system(size: 14, weight: .medium))
                        if component != pathComponents(path: URL(fileURLWithPath: pathString)).last {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .onTapGesture {
                    isEditing = true
                }
            }
        }
        .animation(.easeInOut, value: isEditing)
    }
    
    private func pathComponents(path: URL) -> [String] {
        return path.pathComponents.filter { $0 != "/" }
    }
}