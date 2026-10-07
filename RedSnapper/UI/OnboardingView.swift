import SwiftUI

/// Shown on launch while RED SNAPPER lacks Accessibility permission.
struct OnboardingView: View {
    @ObservedObject var status: RuntimeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "fish.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to RED SNAPPER").font(.title2.bold())
                    Text("One permission and you're ready to snap.").foregroundStyle(.secondary)
                }
            }

            Text("RED SNAPPER moves and resizes other apps' windows, which macOS only allows for apps you trust under **Accessibility**.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Click **Open System Settings** below.")
                step(2, "Go to **Privacy & Security → Accessibility**.")
                step(3, "Turn on the switch next to **RED SNAPPER** (use **+** to add it if it isn't listed).")
            }

            HStack {
                if status.isTrusted {
                    Label("Permission granted — you're all set!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Waiting for permission…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open System Settings") {
                    AccessibilityPermission.requestWithSystemPrompt()
                    AccessibilityPermission.openSystemSettings()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(status.isTrusted)
            }
        }
        .padding(24)
        .frame(width: 460)
        .tint(.red)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.caption.bold()).frame(width: 18, height: 18)
                .background(Circle().fill(Color.red.opacity(0.2)))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
