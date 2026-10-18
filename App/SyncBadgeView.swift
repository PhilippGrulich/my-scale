import SwiftUI

/// Clear Apple Health sync indicator. Reflects only knowable facts: HealthKit
/// availability/authorization + the most recent write result. (HealthKit never
/// reveals read-authorization, so we never claim a read status.)
struct SyncBadgeView: View {
    let auth: HealthKitSink.AuthState
    let lastStatus: LoggedReading.SinkStatus?
    let lastError: String?
    let onAuthorize: () -> Void
    /// Plain row for a `Form` (Profile → Settings) instead of a glass capsule.
    var inline: Bool = false

    var body: some View {
        if inline { row } else { badge }
    }

    private var row: some View {
        HStack {
            Label("Apple Health", systemImage: "heart.text.square.fill")
                .foregroundStyle(.primary)
            Spacer()
            if needsAuthorization {
                Button("Connect", action: onAuthorize)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
            } else {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(color)
                    .multilineTextAlignment(.trailing)
            }
        }
        .animation(.snappy, value: text)
    }

    private var badge: some View {
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
        if case .unavailable = auth { return String(localized: "Health unavailable") }
        switch lastStatus {
        case .written: return String(localized: "Saved to Apple Health")
        case .pending: return String(localized: "Saving to Apple Health…")
        case .failed: return String(localized: "Sync failed — tap to retry")
        case .skipped(let why): return String(localized: "Health: \(why)")
        case .none: return String(localized: "Connected to Apple Health")
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
