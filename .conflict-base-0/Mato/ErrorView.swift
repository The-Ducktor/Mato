
import SwiftUI

struct ErrorView: View {
    let error: String
    let onTryAgain: () -> Void

    var body: some View {
        VStack {
            Text("Error: \(error)")
                .foregroundColor(.red)
            Button("Try Again", action: onTryAgain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
