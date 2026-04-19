import SwiftUI

struct ConnectServerView: View {
    @Binding var serverInput: String
    let errorMessage: String?
    let onConnect: () async -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)

                Text("EarWorm")
                    .font(.largeTitle.bold())

                Text("Connect to your EarWorm server")
                    .font(.headline)

                Text("Enter your HTTPS EarWorm URL once. EarWorm's own mobile login opens next.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("https://your-earworm-host", text: $serverInput)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .focused($isTextFieldFocused)

                Text("HTTPS only. Example: https://192.168.1.24:4533")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }

            Button {
                Task {
                    await onConnect()
                }
            } label: {
                Text("Connect")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(serverInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(24)
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}
