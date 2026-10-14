import KeyboardShortcuts
import SwiftUI
import VirtualRemoteCore

enum SettingsTab: Hashable {
    case general
    case shortcuts
    case modes
}

struct SettingsView: View {
    @Bindable var app: AppModel

    var body: some View {
        TabView(selection: $app.settingsTab) {
            GeneralTab(app: app)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ModesTab(app: app)
                .tabItem { Label("Modes", systemImage: "switch.2") }
                .tag(SettingsTab.modes)
            ShortcutsTab()
                .tabItem { Label("Keyboard Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
        }
        .frame(width: 460, height: 500)
    }
}

private struct GeneralTab: View {
    let app: AppModel
    @AppStorage(AppSettings.Key.autoConnect) private var autoConnect = AppSettings.Default.autoConnect
    @AppStorage(AppSettings.Key.volumeStepPercent) private var volumeStep = AppSettings.Default.volumeStepPercent
    @AppStorage(AppSettings.Key.skipShortSeconds) private var skipShort = AppSettings.Default.skipShortSeconds
    @AppStorage(AppSettings.Key.skipLongSeconds) private var skipLong = AppSettings.Default.skipLongSeconds

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: loginBinding)
                if let error = app.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Toggle("Connect to the last receiver automatically", isOn: $autoConnect)
            }
            Section("Controls") {
                Stepper(
                    "Volume step for shortcuts: \(volumeStep) %",
                    value: $volumeStep, in: AppSettings.Range.volumeStepPercent)
                Stepper(
                    "Short skip: \(skipShort) s",
                    value: $skipShort, in: AppSettings.Range.skipSeconds)
                Stepper(
                    "Long skip: \(skipLong) s",
                    value: $skipLong, in: AppSettings.Range.skipSeconds)
            }
            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Media adapter", value: adapterCommit)
                Link("Source on GitHub", destination: URL(string: "https://github.com/tarikkavaz/VirtualRemote")!)
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Short commit of the bundled mediaremote-adapter, written by scripts/make-app.sh.
    private var adapterCommit: String {
        (Bundle.main.infoDictionary?["VRAdapterCommit"] as? String).map { String($0.prefix(7)) }
            ?? "unknown"
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) })
    }
}

private struct ShortcutsTab: View {
    @AppStorage(AppSettings.Key.skipShortSeconds) private var skipShort = AppSettings.Default.skipShortSeconds
    @AppStorage(AppSettings.Key.skipLongSeconds) private var skipLong = AppSettings.Default.skipLongSeconds

    var body: some View {
        Form {
            Section("Global shortcuts") {
                ForEach(Hotkeys.all(short: skipShort, long: skipLong), id: \.name) { item in
                    KeyboardShortcuts.Recorder(item.title, name: item.name)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModesTab: View {
    let app: AppModel

    var body: some View {
        Form {
            Section("This Mac acts as") {
                Picker("Mode", selection: modeBinding) {
                    ForEach(AppMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if app.mode.isReceiver {
                ReceiverSection(model: app.receiver)
            }
            if app.mode.isController {
                ControllerKeySection(model: app.controller)
            }
        }
        .formStyle(.grouped)
    }

    private var modeExplanation: String {
        switch app.mode {
        case .controller: "Control media on another Mac from this one."
        case .receiver: "Let other Macs control media on this one."
        case .both: "Do both: control other Macs and be controlled."
        }
    }

    private var modeBinding: Binding<AppMode> {
        Binding(get: { app.mode }, set: { app.setMode($0) })
    }
}

/// The key this Mac hands out when it is a receiver.
struct ReceiverSection: View {
    let model: ReceiverModel
    @State private var confirmNewKey = false

    var body: some View {
        Section("Receiver") {
            ReceiverStatusLines(model: model)
        }
        Section("Receiver pairing key") {
            Text("Enter this key once on the controller.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(model.key.displayString)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.key.displayString, forType: .string)
                }
            }
            Button("New key…", role: .destructive) { confirmNewKey = true }
            if let warning = model.keychainWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
        }
        .confirmationDialog("Create a new pairing key?", isPresented: $confirmNewKey) {
            Button("Create new key", role: .destructive) { model.regenerateKey() }
        } message: {
            Text("Controllers paired with the old key will have to pair again.")
        }
    }
}

/// Adds, replaces or forgets the key for the receiver selected in the popover.
private struct ControllerKeySection: View {
    let model: ControllerModel
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        Section("Controller: key for the selected receiver") {
            if let selected = model.selected {
                LabeledContent("Receiver", value: selected.name)
                TextField("Key", text: $text, prompt: Text("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"))
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(save)
                if invalid {
                    Text("That is not a valid key.").font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Save key", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    Button("Forget key", role: .destructive) { model.forgetSelected() }
                }
            } else {
                Text("Pick a receiver in the menu bar popover first.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        invalid = !model.submitPairing(text)
        if !invalid { text = "" }
    }
}

/// Receiver status and adapter self-test result; shared by Settings and the popover.
struct ReceiverStatusLines: View {
    let model: ReceiverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLine
            adapterLine
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch model.status {
        case .stopped:
            Text("Not running").font(.callout).foregroundStyle(.secondary)
        case .starting:
            Text("Starting…").font(.callout).foregroundStyle(.secondary)
        case .listening(let name, _):
            Label("Visible to controllers as “\(name)”", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder private var adapterLine: some View {
        switch model.adapterWorks {
        case .none:
            EmptyView()
        case .some(true):
            Label("Media control works on this Mac", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .some(false):
            Label(
                "Media control self-test failed. A macOS update may have broken the adapter.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }
}
