import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(.orange)

            Text("Connecting to EarWorm")
                .font(.headline)

            Text("Validating server and opening app")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }
}
