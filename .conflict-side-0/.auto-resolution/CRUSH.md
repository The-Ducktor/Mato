# CRUSH.md

## Build/Lint/Test Commands

- **Build:** `xcodebuild build`
- **Test all targets:** `xcodebuild test`
- **Test a specific scheme:** `xcodebuild test -scheme Mato`
- **Run a single test:**
  - For a specific test class: `xcodebuild test -scheme Mato -destination 'platform=macOS,arch=arm64' -only-testing "MatoTests/MatoTests"`
  - For a specific test method: `xcodebuild test -scheme Mato -destination 'platform=macOS,arch=arm64' -only-testing "MatoTests/MatoTests/testExample"`

## Code Style Guidelines (Swift)

- **Imports:** Group related imports. Prefer explicit imports over `@_exported`.
- **Formatting:** Adhere to Xcode's default formatting or SwiftLint if configured (run `swiftlint` if available).
- **Types:** Use Swift's type inference where appropriate, but explicitly declare complex types for clarity.
- **Naming Conventions:**
  - **Types (Classes, Structs, Enums):** `PascalCase` (e.g., `MyStruct`).
  - **Functions, Methods, Variables, Properties:** `camelCase` (e.g., `myFunction`, `myVariable`).
  - **Constants:** `camelCase` for Swift constants (e.g., `let maximumValue`).
- **Error Handling:** Use Swift's `Error` protocol and `do-catch` blocks for error propagation and handling. Avoid `try!` or `!` for unwrapping unless absolutely certain of success.
- **Optionals:** Use optionals (`?` and `!`) appropriately. Prefer optional binding (`if let`, `guard let`) over forced unwrapping.
- **Comments:** Use comments to explain _why_ a piece of code exists, not _what_ it does (unless the "what" is not obvious).
