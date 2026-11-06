import SwiftUI
import AppKit

@MainActor final class SettingsModel: ObservableObject {
    @Published var name = ""
    @Published var height = ""
    @Published var birthDate = Date()
    @Published var gender = "male"
    @Published var athlete = false
    @Published var weight = ""
    @Published var athleteID = ""
    @Published var apiKey = ""
    @Published var scaleID = ""
    @Published var hasKey = false
    @Published var busy = true
    @Published var loaded = false
    @Published var saved = false
    @Published var message = "Loading your profile…"
    @Published var failed = false
    private var process: Process?
    private var buffer = ""
    private var received = false
    private let formatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private func numberText(_ value: Any?) -> String {
        guard let number = value as? NSNumber else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? ""
    }
    func load() { run(action: "settings-read", payload: nil) }
    func save() {
        let payload: [String: Any] = ["name": name, "height": height, "birthDate": formatter.string(from: birthDate), "gender": gender, "isAthlete": athlete, "weight": weight, "athleteId": athleteID, "apiKey": apiKey, "scaleId": scaleID]
        run(action: "settings-save", payload: payload)
    }
    private func run(action: String, payload: [String: Any]?) {
        guard process == nil else { return }
        let root = Bundle.main.object(forInfoDictionaryKey: "ScaleProjectRoot") as? String ?? ""
        let node = URL(fileURLWithPath: root).appendingPathComponent("../work/runtime/node_modules/.bin/node").standardized.path
        guard let helper = Bundle.main.url(forResource: "bridge", withExtension: "mjs") else {
            busy = false; failed = true; message = "Could not open settings."; return
        }
        busy = true; failed = false; received = false; buffer = ""
        message = action == "settings-save" ? "Checking Intervals.icu before saving…" : "Loading your profile…"
        let task = Process(), output = Pipe(), input = Pipe(), errors = Pipe()
        task.executableURL = URL(fileURLWithPath: node)
        task.arguments = [helper.path, "--root", root, "--action", action]
        task.standardOutput = output; task.standardInput = input; task.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consume(text) }
        }
        task.terminationHandler = { [weak self] task in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                guard let self else { return }
                self.process = nil; self.busy = false
                if !self.received {
                    self.failed = true; self.message = "Could not complete the operation. Try again."
                }
            }
        }
        process = task
        do {
            try task.run()
            if let payload { let data = try JSONSerialization.data(withJSONObject: payload); try input.fileHandleForWriting.write(contentsOf: data) }
            try input.fileHandleForWriting.close()
        } catch {
            if task.isRunning { task.terminate() }; process = nil; busy = false; failed = true
            message = "Could not access the configuration. Try again."
        }
    }
    private func consume(_ text: String) {
        buffer += text
        while let end = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<end]); buffer.removeSubrange(...end)
            guard let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else { continue }
            if type == "settings" {
                name = event["name"] as? String ?? ""
                height = numberText(event["height"])
                weight = numberText(event["weight"])
                birthDate = formatter.date(from: event["birthDate"] as? String ?? "") ?? Date()
                gender = event["gender"] as? String ?? "male"; athlete = event["isAthlete"] as? Bool ?? false
                athleteID = event["athleteId"] as? String ?? ""; scaleID = event["scaleId"] as? String ?? ""
                hasKey = event["hasKey"] as? Bool ?? false; apiKey = ""
                loaded = true; message = "Changes are saved only when you click Save and verify."
            } else if type == "settings-saved" {
                saved = true; hasKey = true; apiKey = ""; message = event["message"] as? String ?? "Settings saved."
            } else if type == "error" {
                failed = true; message = event["message"] as? String ?? "Could not save settings."
            } else { continue }
            received = true
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = SettingsModel()
    var onSaved: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings").font(.title2.weight(.semibold))
                    Text("Your profile, your scale.").foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            Form {
                profileSection
                intervalsSection
                scaleSection
            }
            .formStyle(.grouped).disabled(form.busy || form.saved || !form.loaded)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    if form.busy { ProgressView().controlSize(.small) }
                    else if form.saved { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    else if form.failed { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                    Text(form.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Link("Where can I find my API key? ↗", destination: URL(string: "https://intervals.icu/settings")!).font(.caption)
                    Spacer()
                    Button(form.saved ? "Done" : "Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction).disabled(form.busy)
                    Button("Save and verify") { form.save() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(form.busy || form.saved || !form.loaded)
                }
            }.padding(24)
        }
        .frame(width: 580, height: 730)
        .onAppear { form.load() }
        .onChange(of: form.saved) { _, saved in if saved { onSaved() } }
        .interactiveDismissDisabled(form.busy)
    }
    private var profileSection: some View {
        Section("Personal profile") {
            TextField("Name", text: $form.name)
            TextField("Height (cm)", text: $form.height)
            DatePicker("Date of birth", selection: $form.birthDate, in: ...Date(), displayedComponents: .date)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                .environment(\.locale, Locale(identifier: "en_US"))
            Picker("Renpho profile sex", selection: $form.gender) {
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            TextField("Approximate weight (kg)", text: $form.weight)
            Toggle("Athlete mode", isOn: $form.athlete)
        }
    }
    private var intervalsSection: some View {
        Section {
            TextField("Athlete ID", text: $form.athleteID, prompt: Text("i123456"))
            SecureField("API key", text: $form.apiKey, prompt: Text(form.hasKey ? "Already saved: leave blank to keep it" : "Paste your API key"))
            if form.hasKey { Label("Key saved on this Mac", systemImage: "lock").font(.caption).foregroundStyle(.secondary) }
        } header: { Text("Intervals.icu") }
        footer: { Text("The key is kept in the local configuration. A new key replaces the previous one only after the connection is verified.") }
    }
    private var scaleSection: some View {
        Section {
            LabeledContent("Scale", value: "Renpho ES-CS20M")
            TextField("Bluetooth identifier", text: $form.scaleID)
                .font(.system(.body, design: .monospaced))
        } header: { Text("Scale") }
        footer: { Text("Identifier previously detected for your scale. Change it only when switching devices.") }
    }
}
