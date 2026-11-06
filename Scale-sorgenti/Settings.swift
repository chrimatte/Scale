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
    @Published var message = "Caricamento del profilo…"
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
        formatter.locale = Locale(identifier: "it_IT")
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
            busy = false; failed = true; message = "Impossibile aprire le impostazioni."; return
        }
        busy = true; failed = false; received = false; buffer = ""
        message = action == "settings-save" ? "Verifico Intervals.icu prima di salvare…" : "Caricamento del profilo…"
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
                    self.failed = true; self.message = "Impossibile completare l’operazione. Riprova."
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
            message = "Impossibile accedere alla configurazione. Riprova."
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
                loaded = true; message = "I dati vengono salvati solo quando premi Salva e verifica."
            } else if type == "settings-saved" {
                saved = true; hasKey = true; apiKey = ""; message = event["message"] as? String ?? "Impostazioni salvate."
            } else if type == "error" {
                failed = true; message = event["message"] as? String ?? "Impossibile salvare."
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
                    Text("Impostazioni").font(.title2.weight(.semibold))
                    Text("Il tuo profilo, la tua bilancia.").foregroundStyle(.secondary)
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
                    Link("Dove trovo la chiave API? ↗", destination: URL(string: "https://intervals.icu/settings")!).font(.caption)
                    Spacer()
                    Button(form.saved ? "Fine" : "Annulla") { dismiss() }
                        .keyboardShortcut(.cancelAction).disabled(form.busy)
                    Button("Salva e verifica") { form.save() }
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
        Section("Profilo personale") {
            TextField("Nome", text: $form.name)
            TextField("Altezza (cm)", text: $form.height)
            DatePicker("Data di nascita", selection: $form.birthDate, in: ...Date(), displayedComponents: .date)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                .environment(\.locale, Locale(identifier: "it_IT"))
            Picker("Sesso del profilo Renpho", selection: $form.gender) {
                Text("Maschile").tag("male")
                Text("Femminile").tag("female")
            }
            TextField("Peso indicativo (kg)", text: $form.weight)
            Toggle("Modalità atleta", isOn: $form.athlete)
        }
    }
    private var intervalsSection: some View {
        Section {
            TextField("ID atleta", text: $form.athleteID, prompt: Text("i123456"))
            SecureField("Chiave API", text: $form.apiKey, prompt: Text(form.hasKey ? "Già salvata: lascia vuoto per mantenerla" : "Incolla la tua chiave API"))
            if form.hasKey { Label("Chiave salvata su questo Mac", systemImage: "lock").font(.caption).foregroundStyle(.secondary) }
        } header: { Text("Intervals.icu") }
        footer: { Text("La chiave resta protetta nella configurazione locale. Una nuova chiave sostituisce la precedente solo dopo la verifica del collegamento.") }
    }
    private var scaleSection: some View {
        Section {
            LabeledContent("Bilancia", value: "Renpho ES-CS20M")
            TextField("Identificativo Bluetooth", text: $form.scaleID)
                .font(.system(.body, design: .monospaced))
        } header: { Text("Bilancia") }
        footer: { Text("Identificativo già rilevato per la tua bilancia. Modificalo solo se cambi dispositivo.") }
    }
}
