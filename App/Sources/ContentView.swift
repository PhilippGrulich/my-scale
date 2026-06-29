import SwiftUI
import MiScaleCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            DashboardView(scanner: model.scanner)
                .tabItem { Label("Dashboard", systemImage: "scalemass") }
            UnassignedView()
                .tabItem { Label("Unassigned", systemImage: "questionmark.circle") }
            UsersView()
                .tabItem { Label("Users", systemImage: "person.2") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var scanner: BLEScanner

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    Label(scanner.statusText, systemImage: scanner.isScanning ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                }
                Section("Recent readings") {
                    if model.measurements.isEmpty {
                        Text("No readings yet. Step on the scale.").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.measurements) { MeasurementRow(measurement: $0) }
                    }
                }
            }
            .navigationTitle("MiScale")
        }
    }
}

struct MeasurementRow: View {
    @EnvironmentObject var model: AppModel
    let measurement: StoredMeasurement

    private var userName: String {
        model.profile(for: measurement.assignedUserID)?.name ?? "Unassigned"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(userName).font(.headline)
                Spacer()
                Text(String(format: "%.1f kg", measurement.weightKg)).monospacedDigit()
            }
            if let c = measurement.composition {
                HStack(spacing: 12) {
                    if !c.bodyFatPercent.isNaN { Text(String(format: "Fat %.1f%%", c.bodyFatPercent)) }
                    Text(String(format: "BMI %.1f", c.bmi))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text("HK: \(measurement.healthKitState.rawValue)")
                Text("HA: \(measurement.haState.rawValue)")
                Text(measurement.capturedAt, style: .time)
            }
            .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Unassigned queue

struct UnassignedView: View {
    @EnvironmentObject var model: AppModel

    private var unassigned: [StoredMeasurement] {
        model.measurements.filter { $0.assignedUserID == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if unassigned.isEmpty {
                    Text("Nothing to confirm.").foregroundStyle(.secondary)
                }
                ForEach(unassigned) { measurement in
                    VStack(alignment: .leading) {
                        Text(String(format: "%.1f kg — %@", measurement.weightKg, measurement.resolution.rawValue))
                        Menu("Assign to…") {
                            ForEach(model.profiles) { profile in
                                Button(profile.name) { model.assign(measurementID: measurement.id, to: profile) }
                            }
                        }
                        .font(.callout)
                    }
                }
            }
            .navigationTitle("Unassigned")
        }
    }
}

// MARK: - Users

struct UsersView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: StoredProfile?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.rangeWarnings, id: \.profileIDs) { warning in
                    Label("Range \(warning.kind.rawValue) between configured users",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                ForEach(model.profiles) { profile in
                    Button { editing = profile } label: {
                        HStack {
                            Text(profile.name.isEmpty ? "Unnamed" : profile.name)
                            if profile.isHealthKitOwner { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                            Spacer()
                            Text(String(format: "%.0f–%.0f kg", profile.lowerKg, profile.upperKg))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { model.deleteProfiles(at: $0) }
            }
            .navigationTitle("Users")
            .toolbar {
                Button { editing = StoredProfile() } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { profile in
                ProfileEditor(profile: profile) { model.upsert($0); editing = nil }
            }
        }
    }
}

struct ProfileEditor: View {
    @State var profile: StoredProfile
    let onSave: (StoredProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $profile.name)
                TextField("Height (cm)", value: $profile.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                DatePicker("Date of birth", selection: $profile.dateOfBirth, displayedComponents: .date)
                Picker("Biological sex", selection: $profile.sex) {
                    Text("Male").tag(BiologicalSex.male)
                    Text("Female").tag(BiologicalSex.female)
                }
                Section("Weight range (kg)") {
                    TextField("Lower", value: $profile.lowerKg, format: .number).keyboardType(.decimalPad)
                    TextField("Upper", value: $profile.upperKg, format: .number).keyboardType(.decimalPad)
                }
                Toggle("HealthKit owner (this device)", isOn: $profile.isHealthKitOwner)
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(profile) } }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var config = HAConfig()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Health") {
                    Button("Authorize HealthKit") { model.requestHealthKitAuthorization() }
                    if model.healthKitAuthorized {
                        Label("Authorized", systemImage: "checkmark.seal").foregroundStyle(.green)
                    }
                }
                Section("Home Assistant (optional)") {
                    Toggle("Enabled", isOn: $config.enabled)
                    TextField("Endpoint URL", text: $config.endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Bearer token", text: $config.token)
                    Button("Save") { model.updateHAConfig(config) }
                }
                Section("Scale") {
                    Text("Set the scale to kilograms for best accuracy.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                if !loaded { config = model.haConfig; loaded = true }
            }
        }
    }
}
