import SwiftUI
import AppKit

@MainActor
final class ScaleModel: ObservableObject {
    @Published var stage = "idle"
    @Published var message = "Una pesata, senza aprire il Terminale."
    @Published var weight: Double?
    @Published var fat: Double?
    @Published var date = ""
    @Published var connected = false
    @Published var busy = false
    @Published var isNewReading = false
    @Published var estimate = false
    @Published var settingsPresented = false
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = ""
    private var token = UUID()
    private var activity: NSObjectProtocol?

    var weightText: String { weight.map { String(format: "%.1f", locale: Locale(identifier: "it_IT"), $0) } ?? "—" }
    var title: String {
        switch stage {
        case "checking": return "Controllo del collegamento"
        case "scanning": return "Accendi la bilancia"
        case "ready": return "Puoi salire"
        case "measuring": return "Peso acquisito"
        case "uploading", "verifying": return "Quasi fatto"
        case "success": return "Pesata sincronizzata"
        case "error": return "Riproviamo?"
        case "cancelled": return "Pesata interrotta"
        default: return "Pronto per la tua pesata"
        }
    }
    func launch(measure: Bool) {
        guard !busy else { return }
        let root = Bundle.main.object(forInfoDictionaryKey: "ScaleProjectRoot") as? String ?? ""
        let node = URL(fileURLWithPath: root).appendingPathComponent("../work/runtime/node_modules/.bin/node").standardized.path
        guard let helper = Bundle.main.url(forResource: "bridge", withExtension: "mjs"), FileManager.default.isExecutableFile(atPath: node) else {
            stage = "error"; message = "Non trovo il progetto. Ripristina la cartella completa di Scale oppure ricompila e reinstalla l’app dopo averla spostata."; return
        }
        token = UUID(); let current = token
        stage = "checking"; message = "Verifico il collegamento a Intervals.icu…"
        busy = true; buffer = ""; isNewReading = false
        if measure { weight = nil; fat = nil }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Pesata Bluetooth in corso")
        let task = Process(); let output = Pipe(); let errors = Pipe()
        task.executableURL = URL(fileURLWithPath: node)
        task.arguments = [helper.path, "--root", root, "--action", measure ? "measure" : "check"] + (measure && estimate ? ["--estimate"] : [])
        task.standardOutput = output; task.standardError = errors
        // Drain diagnostics without exposing configuration or credentials in the UI.
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consume(text, token: current) }
        }
        task.terminationHandler = { [weak self] task in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard let self = self, self.token == current else { return }
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                self.finishActivity()
                self.busy = false; self.process = nil; self.pipe = nil
                if self.stage == "checking" && task.terminationStatus == 0 {
                    self.stage = "idle"; self.message = "Collegamento verificato. Avvia quando sei pronto."
                } else if !["success", "error", "cancelled"].contains(self.stage) {
                    self.stage = "error"; self.message = "La lettura si è interrotta. Controlla Bluetooth e connessione, poi riprova."
                }
            }
        }
        process = task; pipe = output
        do { try task.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
            busy = false; finishActivity(); process = nil
            stage = "error"; message = "Impossibile avviare la pesata. Controlla che la cartella del progetto sia disponibile."
        }
    }
    private func consume(_ text: String, token current: UUID) {
        guard current == token else { return }
        buffer += text
        while let end = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<end]); buffer.removeSubrange(...end)
            guard let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else { continue }
            switch type {
            case "status":
                stage = event["stage"] as? String ?? stage
                message = event["message"] as? String ?? message
            case "connected":
                connected = true; date = event["date"] as? String ?? ""
                // During a new measurement, keep the main display empty until it is acquired.
                if process?.arguments?.contains("measure") != true {
                    weight = event["weight"] as? Double; fat = event["bodyFat"] as? Double
                }
            case "measurement":
                weight = event["weight"] as? Double; isNewReading = true
                stage = "measuring"; message = "Resta fermo finché la bilancia termina."
            case "success":
                weight = event["weight"] as? Double; fat = event["bodyFat"] as? Double
                date = event["date"] as? String ?? date; isNewReading = true
                stage = "success"; message = "Salvata su Intervals.icu e verificata. Puoi scendere."
            case "error":
                stage = "error"; message = event["message"] as? String ?? "Qualcosa non ha funzionato. Riprova."
            default: break
            }
        }
    }
    private func finishActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
    func cancel() {
        guard let task = process, task.isRunning else { return }
        stage = "cancelled"
        message = "Lettura fermata. Un invio già completato resta su Intervals.icu."
        task.terminate()
        // The helper owns cleanup of its Bluetooth child before it exits.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if task.isRunning { task.interrupt() } }
    }
}

struct ContentView: View {
    @ObservedObject var model: ScaleModel
    @ScaledMetric(relativeTo: .largeTitle) private var weightSize = 76.0
    private let accent = Color(red: 0.10, green: 0.46, blue: 0.40)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Divider()
                weightDisplay
                statusDisplay
                actions
                Divider()
                options
                footer
            }.padding(30)
        }
        .frame(minWidth: 440, idealWidth: 500, minHeight: 620, idealHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.launch(measure: false) }
        .toolbar {
            Button { model.settingsPresented = true } label: { Label("Impostazioni", systemImage: "gearshape") }
                .disabled(model.busy).help("Profilo e collegamento Intervals.icu")
        }
        .sheet(isPresented: $model.settingsPresented) {
            SettingsView { model.connected = false; model.launch(measure: false) }
        }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let url = Bundle.main.url(forResource: "Scale", withExtension: "png"), let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().frame(width: 44, height: 44).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Scale").font(.title2.weight(.semibold))
                Text("Renpho → Intervals.icu").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Label(model.connected ? "Collegato" : "Da verificare", systemImage: model.connected ? "checkmark.circle" : "circle.dashed")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var weightDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isNewReading ? "LA TUA PESATA" : "SU INTERVALS OGGI")
                .font(.caption.weight(.medium)).tracking(1.4).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.weightText).font(.system(size: weightSize, weight: .light, design: .rounded)).monospacedDigit()
                Text("kg").font(.title2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Peso")
            .accessibilityValue(model.weight.map { "\($0) chilogrammi" } ?? "Nessun peso disponibile")
            if model.stage == "success", let fat = model.fat {
                Text(String(format: "Grasso stimato: %.1f%%", locale: Locale(identifier: "it_IT"), fat))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private var statusSymbol: String {
        if model.stage == "success" { return "checkmark.circle.fill" }
        if model.stage == "error" { return "exclamationmark.circle" }
        return "scalemass"
    }
    private var statusDisplay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if model.busy { ProgressView().controlSize(.small) }
                else { Image(systemName: statusSymbol).foregroundStyle(model.stage == "error" ? Color.orange : accent) }
                Text(model.title).font(.headline)
            }
            Text(model.message).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
    }
    private var buttonTitle: String {
        if model.stage == "success" { return "Nuova pesata" }
        if model.stage == "error" { return "Riprova la pesata" }
        return "Avvia pesata"
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { model.launch(measure: true) } label: {
                Text(buttonTitle).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(accent)
            .keyboardShortcut(.defaultAction).disabled(model.busy)
            if model.busy {
                Button("Interrompi") { model.cancel() }
                    .keyboardShortcut(.cancelAction).frame(maxWidth: .infinity)
            }
        }
    }
    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Invia anche il grasso stimato", isOn: $model.estimate)
                .toggleStyle(.checkbox).disabled(model.busy)
            Text("Questa connessione legge solo il peso. La stima del grasso non è il valore mostrato dall’app Renpho.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var footer: some View {
        HStack(alignment: .top) {
            Text("Chiudi Renpho sul telefono.\nTieni il Mac acceso e vicino alla bilancia.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Link("Apri Intervals.icu ↗", destination: URL(string: "https://intervals.icu")!)
                .font(.caption)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: ScaleModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.cancel() }
}

@main struct ScaleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = ScaleModel()
    var body: some Scene {
        WindowGroup("Scale") {
            ContentView(model: model).onAppear { delegate.model = model }
        }
        .defaultSize(width: 500, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Impostazioni…") { model.settingsPresented = true }
                    .keyboardShortcut(",", modifiers: .command).disabled(model.busy)
            }
        }
    }
}
