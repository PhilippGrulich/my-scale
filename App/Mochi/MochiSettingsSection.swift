import SwiftUI
import MyOpenScaleCore

/// Settings → Mochi: master switch, reminders and haptics.
struct MochiSettingsSection: View {
    @ObservedObject var mochi: MochiCoordinator

    var body: some View {
        Section {
            Toggle("Mochi", isOn: $mochi.settings.enabled)

            if mochi.settings.enabled {
                Toggle("Reminders", isOn: $mochi.settings.remindersEnabled)

                if mochi.settings.remindersEnabled {
                    Picker("Reminder style", selection: $mochi.settings.reminderMode) {
                        Text("Smart").tag(ReminderMode.smart)
                        Text("Fixed time").tag(ReminderMode.fixed)
                    }

                    switch mochi.settings.reminderMode {
                    case .fixed:
                        DatePicker("Reminder time", selection: time($mochi.settings.fixedMinuteOfDay),
                                   displayedComponents: .hourAndMinute)
                    case .smart:
                        Toggle("Choose my own time", isOn: ownSmartTime)
                        if let override = Binding($mochi.settings.smartMinuteOverride) {
                            DatePicker("Reminder time", selection: time(override),
                                       displayedComponents: .hourAndMinute)
                        }
                    }
                }

                Toggle("Haptics", isOn: $mochi.settings.haptics)
            }
        } header: {
            Text("Mochi")
        } footer: {
            if !mochi.settings.enabled {
                Text("Turn Mochi on to get a little companion, weigh-in cheers and reminders.")
            } else if mochi.settings.remindersEnabled,
                      mochi.settings.reminderMode == .smart,
                      mochi.settings.smartMinuteOverride == nil {
                Text("Mochi reminds you around the time you usually weigh in.")
            }
        }
    }

    /// Smart mode's "Choose my own time": switching it on starts from the usual weigh-in time.
    private var ownSmartTime: Binding<Bool> {
        Binding {
            mochi.settings.smartMinuteOverride != nil
        } set: { on in
            mochi.settings.smartMinuteOverride = on
                ? ReminderPlanner.usualMinuteOfDay(history: mochi.historyProvider(), calendar: .current)
                    ?? ReminderPlanner.defaultMinuteOfDay
                : nil
        }
    }

    /// A time-of-day `Date` (today) backed by minutes after midnight.
    private func time(_ minuteOfDay: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minuteOfDay.wrappedValue / 60,
                                  minute: minuteOfDay.wrappedValue % 60,
                                  second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minuteOfDay.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}
