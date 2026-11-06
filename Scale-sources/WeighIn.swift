import SwiftUI
import AppKit

@MainActor
final class ScaleModel: ObservableObject {
    @Published var stage = "idle"
    @Published var message = "Weigh in without opening Terminal."
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

    var weightText: String { weight.map { String(format: "%.1f", locale: Locale(identifier: "en_US"), $0) } ?? "—" }
    var title: String {
        switch stage {
        case "checking": return "Checking the connection"
        case "scanning": return "Wake up the scale"
        case "ready": return "Step on the scale"
        case "measuring": return "Weight recorded"
        case "uploading", "verifying": return "Almost done"
        case "success": return "Weigh-in synced"
        case "error": return "Try again?"
        case "cancelled": return "Weigh-in cancelled"
        default: return "Ready for your weigh-in"
        }
    }
    func launch(measure: Bool) {
        guard !busy else { return }
        let root = Bundle.main.object(forInfoDictionaryKey: "ScaleProjectRoot") as? String ?? ""
        let node = URL(fileURLWithPath: root).appendingPathComponent("../work/runtime/node_modules/.bin/node").standardized.path
        guard let helper = Bundle.main.url(forResource: "bridge", withExtension: "mjs"), FileManager.default.isExecutableFile(atPath: node) else {
            stage = "error"; message = "The project could not be found. Restore the complete Scale folder, or rebuild and reinstall the app after moving it."; return
        }
        token = UUID(); let current = token
        stage = "checking"; message = "Checking the connection to Intervals.icu…"
        busy = true; buffer = ""; isNewReading = false
        if measure { weight = nil; fat = nil }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Bluetooth weigh-in in progress")
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
                    self.stage = "idle"; self.message = "Connection verified. Start when you are ready."
                } else if !["success", "error", "cancelled"].contains(self.stage) {
                    self.stage = "error"; self.message = "The reading was interrupted. Check Bluetooth and your Internet connection, then try again."
                }
            }
        }
        process = task; pipe = output
        do { try task.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
            busy = false; finishActivity(); process = nil
            stage = "error"; message = "Could not start the weigh-in. Check that the project folder is available."
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
                stage = "measuring"; message = "Stand still until the scale finishes."
            case "success":
                weight = event["weight"] as? Double; fat = event["bodyFat"] as? Double
                date = event["date"] as? String ?? date; isNewReading = true
                stage = "success"; message = "Saved to Intervals.icu and verified. You can step off."
            case "error":
                stage = "error"; message = event["message"] as? String ?? "Something went wrong. Try again."
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
        message = "Reading stopped. Any data already uploaded remains on Intervals.icu."
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
            Button { model.settingsPresented = true } label: { Label("Settings", systemImage: "gearshape") }
                .disabled(model.busy).help("Profile and Intervals.icu connection")
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
            Label(model.connected ? "Connected" : "Not verified", systemImage: model.connected ? "checkmark.circle" : "circle.dashed")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var weightDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isNewReading ? "YOUR WEIGH-IN" : "ON INTERVALS TODAY")
                .font(.caption.weight(.medium)).tracking(1.4).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.weightText).font(.system(size: weightSize, weight: .light, design: .rounded)).monospacedDigit()
                Text("kg").font(.title2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weight")
            .accessibilityValue(model.weight == nil ? "No weight available" : "\(model.weightText) kilograms")
            if model.stage == "success", let fat = model.fat {
                Text(String(format: "Estimated body fat: %.1f%%", locale: Locale(identifier: "en_US"), fat))
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
        if model.stage == "success" { return "New weigh-in" }
        if model.stage == "error" { return "Retry weigh-in" }
        return "Start weigh-in"
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { model.launch(measure: true) } label: {
                Text(buttonTitle).frame(maxWidth: .infinity).padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(accent)
            .keyboardShortcut(.defaultAction).disabled(model.busy)
            if model.busy {
                Button("Stop") { model.cancel() }
                    .keyboardShortcut(.cancelAction).frame(maxWidth: .infinity)
            }
        }
    }
    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Include estimated body fat", isOn: $model.estimate)
                .toggleStyle(.checkbox).disabled(model.busy)
            Text("This connection reads weight only. Estimated body fat differs from the value shown in the Renpho app.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var footer: some View {
        HStack(alignment: .top) {
            Text("Close Renpho on your phone.\nKeep your Mac awake and near the scale.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Link("Open Intervals.icu ↗", destination: URL(string: "https://intervals.icu")!)
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
                Button("Settings…") { model.settingsPresented = true }
                    .keyboardShortcut(",", modifiers: .command).disabled(model.busy)
            }
        }
    }
}
