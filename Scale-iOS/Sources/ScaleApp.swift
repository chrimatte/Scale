import SwiftUI

@main struct ScaleApp: App {
    @StateObject private var model: ScaleModel
    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview-weigh-in") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let preview = ScaleModel(storageDirectory: directory, uploader: { _ in })
            preview.athleteID = "preview"
            preview.bluetooth.onWeight?(74.4)
            _model = StateObject(wrappedValue: preview)
            return
        }
        #endif
        _model = StateObject(wrappedValue: ScaleModel())
    }
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WeighInView(model: model, bluetooth: model.bluetooth)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { model.enteredBackground() }
                }
        }
    }
}

struct WeighInView: View {
    @ObservedObject var model: ScaleModel
    @ObservedObject var bluetooth: ScaleBluetooth
    @ScaledMetric(relativeTo: .largeTitle) private var weightSize = 76.0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Renpho → Intervals.icu").font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.verified ? "SAVED WEIGH-IN" : "YOUR WEIGH-IN")
                            .font(.caption.weight(.medium)).tracking(1.4).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(model.weight.map { String(format: "%.2f", $0) } ?? "—")
                                .font(.system(size: weightSize, weight: .light, design: .rounded))
                                .monospacedDigit().minimumScaleFactor(0.45).lineLimit(1)
                            Text("kg").font(.title2).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Weight")
                        .accessibilityValue(model.weight.map { "\($0.formatted()) kilograms" } ?? "No weight available")
                    }.padding(.vertical, 24)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            if model.busy { ProgressView() }
                            else { Image(systemName: model.verified ? "checkmark.circle" : "scalemass") }
                            Text(model.title).font(.headline)
                        }
                        Text(model.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.accessibilityElement(children: .combine)
                    if model.scanning, !bluetooth.devices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NEARBY SCALES").font(.caption).foregroundStyle(.secondary)
                            ForEach(bluetooth.devices) { device in
                                Button { bluetooth.select(device) } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(device.name)
                                            Text(device.id.uuidString.suffix(8)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }.frame(minHeight: 44)
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                    if !bluetooth.connectionDetails.isEmpty {
                        DisclosureGroup("Connection details") {
                            Text(bluetooth.connectionDetails).font(.caption.monospaced())
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.footnote)
                    }
                    VStack(spacing: 12) {
                        if model.pending != nil, !model.busy {
                            Button { model.requestShare() } label: {
                                Text("Share with Intervals.icu")
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.borderedProminent).tint(.primary)
                            Button("New weigh-in") { model.newWeighIn() }.frame(minHeight: 44)
                            Text("A new weigh-in replaces the saved reading on this iPhone.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button { model.start() } label: {
                                Text(model.verified ? "New weigh-in" : "Start weigh-in")
                                    .foregroundStyle(Color(uiColor: .systemBackground))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.borderedProminent).tint(.primary).disabled(model.busy)
                        }
                        if model.busy { Button("Stop") { model.stop() }.frame(minHeight: 44) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Weight only. Existing body fat on Intervals.icu stays unchanged.")
                        Text("Close Renpho and Scale on your Mac. Keep this app open and your iPhone near the scale.")
                        Link("Open Intervals.icu ↗", destination: URL(string: "https://intervals.icu")!)
                    }.font(.footnote).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .navigationTitle("Scale")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { model.settingsPresented = true }.disabled(model.busy)
                }
            }
            .alert("Vuoi condividere il peso su Intervals?", isPresented: $model.shareConfirmationPresented) {
                Button("Condividi") { model.shareConfirmed() }
                Button("Non ora", role: .cancel) { }
            } message: {
                Text("Il peso verrà inviato a Intervals.icu solo premendo Condividi.")
            }
            .sheet(isPresented: $model.settingsPresented) { SettingsView(model: model) }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: ScaleModel
    @Environment(\.dismiss) private var dismiss
    @State private var id = ""
    @State private var key = ""
    @State private var saving = false
    @State private var error: String?
    @AppStorage("height") private var height = 170.0
    @AppStorage("age") private var age = 30
    @AppStorage("sex") private var sex = "male"
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Athlete ID", text: $id).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Intervals.icu") } footer: {
                    Text("Find your athlete ID and API key in Intervals.icu Settings → Developer. Leave the key blank to keep the saved one. Your key is stored in this iPhone’s Keychain.")
                }
                Section {
                    Stepper("Height: \(height.formatted()) cm", value: $height, in: 100...230, step: 1)
                    Stepper("Age: \(age)", value: $age, in: 18...100)
                    Picker("Renpho profile sex", selection: $sex) {
                        Text("Male").tag("male"); Text("Female").tag("female")
                    }
                } header: { Text("Scale profile") } footer: {
                    Text("Set these values before your first weigh-in. Some Renpho revisions need a guest profile to start measuring. Scale uploads weight only.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button {
                        saving = true; error = nil
                        Task {
                            do { try await model.saveSettings(id: id, key: key); key = ""; dismiss() }
                            catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    } label: {
                        HStack { Text("Save and verify"); Spacer(); if saving { ProgressView() } }
                    }.disabled(saving || id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .disabled(saving)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .onAppear { id = model.athleteID }
        }
    }
}
