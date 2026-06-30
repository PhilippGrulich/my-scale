import SwiftUI

/// Clear Apple Health sync indicator. Reflects only knowable facts: HealthKit
/// availability/authorization + the most recent write result. (HealthKit never
/// reveals read-authorization, so we never claim a read status.)
struct SyncBadgeView: View {
    let auth: HealthKitSink.AuthState
    let lastStatus: LoggedReading.SinkStatus?
    let lastError: String?
    let onAuthorize: () -> Void

    var body: some View {
        Group {
            if needsAuthorization {
                Button(action: onAuthorize) {
                    Label("Connect Apple Health", systemImage: "heart.text.square.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(Theme.accent)
            } else {
                Label {
                    Text(text)
                } icon: {
                    Image(systemName: icon)
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.pulse, isActive: isSyncing)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(in: .capsule)
            }
        }
        .animation(.snappy, value: text)
    }

    // MARK: - State mapping

    private var needsAuthorization: Bool {
        switch auth {
        case .notRequested, .failed: return true
        default: return false
        }
    }

    private var isSyncing: Bool { lastStatus == .pending }

    private var text: String {
        if case .unavailable = auth { return "Health unavailable" }
        switch lastStatus {
        case .written: return "Saved to Apple Health"
        case .pending: return "Saving to Apple Health…"
        case .failed: return "Sync failed — tap to retry"
        case .skipped(let why): return "Health: \(why)"
        case .none: return "Connected to Apple Health"
        }
    }

    private var icon: String {
        switch lastStatus {
        case .written, .none: return "checkmark.heart.fill"
        case .pending: return "heart.fill"
        case .failed: return "exclamationmark.heart.fill"
        case .skipped: return "minus.circle"
        }
    }

    private var color: Color {
        if case .unavailable = auth { return .secondary }
        switch lastStatus {
        case .written, .none: return Theme.accent
        case .pending: return .secondary
        case .failed: return .red
        case .skipped: return .secondary
        }
    }
}
