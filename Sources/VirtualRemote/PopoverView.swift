import SwiftUI
import VirtualRemoteCore

struct PopoverView: View {
    @Environment(\.openSettings) private var openSettings
    let app: AppModel

    var body: some View {
        VStack(spacing: 12) {
            header
            if app.mode.isController {
                ControllerSection(model: app.controller)
            } else {
                Divider()
                ReceiverStatusLines(model: app.receiver)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Pairing key…") { open(.modes) }
                    .buttonStyle(.link)
                    .pointerCursor()
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(WindowFitter())
        // While the window is taller than the content, keep the content at the
        // top instead of centered.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if app.mode.isController {
                ReceiverPicker(model: app.controller)
            } else {
                Label("Virtual Remote", systemImage: "appletvremote.gen4.fill")
                    .font(.headline)
                Spacer()
            }
            iconButton("gearshape", help: "Settings") { open(.general) }
            iconButton("power", help: "Quit") { NSApp.terminate(nil) }
        }
    }

    private func iconButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.plain)
            .pointerCursor()
            .help(help)
    }

    /// The app has no Dock icon, so bring it to the front or the window opens behind others.
    private func open(_ tab: SettingsTab) {
        app.settingsTab = tab
        NSApp.activate()
        openSettings()
    }
}

private struct ControllerSection: View {
    let model: ControllerModel

    var body: some View {
        VStack(spacing: 12) {
            Divider()
            if model.needsPairing, model.selected != nil {
                PairingForm(model: model)
            } else if model.isConnected {
                NowPlayingView(
                    info: model.state?.nowPlaying,
                    artwork: model.state?.nowPlaying?.artworkID.flatMap { model.artworkImages[$0] },
                    appIcon: model.state?.nowPlaying.flatMap { model.appIcons[$0.bundleIdentifier] },
                    appName: model.state?.nowPlaying.flatMap { model.appNames[$0.bundleIdentifier] }
                )
                Divider()
                TransportView(model: model)
                VolumeView(model: model)
            } else {
                StatusView(model: model)
            }
            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ReceiverPicker: View {
    let model: ControllerModel

    var body: some View {
        HStack {
            Image(systemName: "desktopcomputer")
            if model.receivers.isEmpty {
                Text("Searching for receivers…").foregroundStyle(.secondary)
            } else {
                Picker("Receiver", selection: selection) {
                    Text("Choose…").tag(DiscoveredReceiver?.none)
                    ForEach(model.receivers, id: \.self) { receiver in
                        Text(receiver.name).tag(DiscoveredReceiver?.some(receiver))
                    }
                }
                .labelsHidden()
                .pointerCursor()
            }
            Spacer()
            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
        }
    }

    private var selection: Binding<DiscoveredReceiver?> {
        Binding(
            get: { model.selected },
            set: { if let receiver = $0 { model.select(receiver) } }
        )
    }
}

private struct StatusView: View {
    let model: ControllerModel

    var body: some View {
        Group {
            switch model.connection {
            case .connecting: Text("Connecting…")
            case .timedOut:
                VStack(spacing: 6) {
                    Text(
                        "No answer after 10 s. Check that the receiver is running and that "
                            + "VirtualRemote is allowed to use the local network."
                    )
                    .multilineTextAlignment(.center)
                    Button("Open Local Network settings") { PrivacyLinks.openLocalNetwork() }
                        .buttonStyle(.link)
                        .pointerCursor()
                }
            case .failed(let reason): Text(reason)
            case .idle:
                Text(model.selected == nil ? "Pick a receiver." : "Not connected.")
            case .connected: EmptyView()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 60)
    }
}

private struct PairingForm: View {
    let model: ControllerModel
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter the pairing key shown on \(model.selected?.name ?? "the receiver").")
                .font(.callout)
            TextField("XXXX-XXXX-XXXX-XXXX-XXXX-XXXX", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(submit)
            if invalid {
                Text("That is not a valid key.").font(.caption).foregroundStyle(.red)
            }
            Button("Pair", action: submit)
                .keyboardShortcut(.defaultAction)
                .pointerCursor()
            Text("macOS may ask for access to your Keychain. Choose Always Allow so it does not ask again.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        invalid = !model.submitPairing(text)
        if !invalid { text = "" }
    }
}

private struct NowPlayingView: View {
    let info: NowPlayingInfo?
    let artwork: NSImage?
    /// Icon and name of the player app, read on the receiver. Nil until it arrives
    /// or when the receiver could not read them.
    let appIcon: NSImage?
    let appName: String?

    var body: some View {
        VStack(spacing: 6) {
            if let info {
                HStack(alignment: .top, spacing: 10) {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title ?? "Unknown title")
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            if let artist = info.artist, !artist.isEmpty {
                                Text(artist + " ·").lineLimit(1)
                            }
                            playerIcon
                            Text(appName ?? fallbackName(info.bundleIdentifier))
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if info.duration != nil, info.elapsedTime != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Progress(
                            elapsed: info.estimatedElapsed(at: context.date) ?? 0,
                            duration: info.duration ?? 0
                        )
                    }
                }
            } else {
                Text("Nothing playing")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var playerIcon: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 14, height: 14)
        }
    }

    /// Used until the receiver's own name for the app arrives.
    private func fallbackName(_ bundleID: String) -> String {
        let known = [
            "tv.plex.desktop": "Plex",
            "company.thebrowser.Browser": "Arc",
            "com.google.Chrome": "Chrome",
            "com.apple.Safari": "Safari",
            "org.mozilla.firefox": "Firefox",
            "com.spotify.client": "Spotify",
        ]
        return known[bundleID] ?? bundleID
    }
}

private struct Progress: View {
    let elapsed: Double
    let duration: Double

    var body: some View {
        VStack(spacing: 2) {
            ProgressView(value: min(max(elapsed, 0), duration), total: max(duration, 1))
            HStack {
                Text(format(elapsed))
                Spacer()
                Text(format(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

private struct TransportView: View {
    let model: ControllerModel
    @AppStorage(AppSettings.Key.skipShortSeconds) private var skipShort = AppSettings.Default.skipShortSeconds
    @AppStorage(AppSettings.Key.skipLongSeconds) private var skipLong = AppSettings.Default.skipLongSeconds

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                skip(-skipLong)
                skip(-skipShort)
                Button { model.send(.togglePlayPause) } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .frame(width: 44, height: 44)
                }
                .pointerCursor()
                skip(skipShort)
                skip(skipLong)
            }
            HStack(spacing: 32) {
                Button { model.send(.previous) } label: { Image(systemName: "backward.fill") }
                    .pointerCursor()
                    .help("Previous")
                if supportsStop {
                    Button { model.send(.stop) } label: { Image(systemName: "stop.fill") }
                        .pointerCursor()
                        .help("Stop")
                }
                Button { model.send(.next) } label: { Image(systemName: "forward.fill") }
                    .pointerCursor()
                    .help("Next")
            }
        }
        .buttonStyle(.plain)
        .font(.title3)
    }

    private var playing: Bool { model.state?.nowPlaying?.playing ?? false }

    private var supportsStop: Bool {
        PlayerCapabilities.supportsStop(bundleIdentifier: model.state?.nowPlaying?.bundleIdentifier)
    }

    private func skip(_ seconds: Int) -> some View {
        Button { model.send(.skip(seconds: Double(seconds))) } label: {
            SkipSymbol(seconds: seconds)
        }
        .pointerCursor()
        .help("\(seconds > 0 ? "Forward" : "Back") \(abs(seconds)) seconds")
    }
}

private struct SkipSymbol: View {
    let seconds: Int

    var body: some View {
        let magnitude = abs(seconds)
        let direction = seconds > 0 ? "goforward" : "gobackward"
        if [5, 10, 15, 30, 45, 60, 75, 90].contains(magnitude) {
            Image(systemName: "\(direction).\(magnitude)")
        } else {
            Image(systemName: direction)
                .overlay { Text("\(magnitude)").font(.system(size: 8, weight: .bold)) }
        }
    }
}

private struct VolumeView: View {
    let model: ControllerModel
    @State private var dragging = false
    @State private var level = 0.0
    @State private var lastSent = Date.distantPast

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.send(.setMuted(!(model.state?.muted ?? false)))
            } label: {
                Image(systemName: icon).frame(width: 20)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            Slider(value: $level, in: 0...1) { editing in
                dragging = editing
                if !editing { model.send(.setVolume(level)) }  // final value
            }
            .pointerCursor()
            .onChange(of: level) { _, new in
                // At most ~12 updates per second while dragging.
                guard dragging, Date().timeIntervalSince(lastSent) > 0.08 else { return }
                lastSent = Date()
                model.send(.setVolume(new))
            }
        }
        .onChange(of: model.state?.volume) { _, new in
            if !dragging, let new { level = new }
        }
        .onAppear { level = model.state?.volume ?? 0 }
    }

    private var icon: String {
        if model.state?.muted == true || level == 0 { return "speaker.slash.fill" }
        return level < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"
    }
}
