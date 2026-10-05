import SwiftUI

struct ErrorView: View {
    let error: ShellError
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color("BrandGreen"))
            Text(error.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("shell.error.title")
            Text(error.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text(error.action)
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("BrandGreen"))
            .padding(.top, 8)
            .accessibilityIdentifier("shell.error.action")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("LaunchBackground"), ignoresSafeAreaEdges: [])
    }

    private var symbol: String {
        switch error {
        case .offline: return "wifi.slash"
        case .ssl: return "lock.slash"
        case .page: return "exclamationmark.triangle"
        }
    }
}
