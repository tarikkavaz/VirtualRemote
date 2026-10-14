import SwiftUI
import VirtualRemoteCore

struct PopoverView: View {
    @Environment(\.openWindow) private var openWindow
    let model: ControllerModel

    var body: some View {
        VStack(spacing: 14) {
            ReceiverPicker(model: model)
            if model.needsPairing, model.selected != nil {
                PairingForm(model: model)
            } else if model.isConnected {
                NowPlayingView(info: model.state?.nowPlaying)
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
            Divider()
            HStack {
                Button("Hotkeys…") {
                    openWindow(id: "hotkeys")
                    NSApp.activate()
                }
                Spacer()
                if model.selected != nil {
                    Button("Forget key") { model.forgetSelected() }
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 300)
        .task { model.startBrowsing() }
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
        }
    }

    private func submit() {
        invalid = !model.submitPairing(text)
        if !invalid { text = "" }
    }
}

private struct NowPlayingView: View {
    let info: NowPlayingInfo?

    var body: some View {
        VStack(spacing: 4) {
            if let info {
                Text(info.title ?? "Unknown title")
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(subtitle(info))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if info.duration != nil, info.elapsedTime != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Progress(
                            elapsed: info.estimatedElapsed(at: context.date) ?? 0,
                            duration: info.duration ?? 0
                        )
                    }
                }
            } else {
                Text("Nothing playing").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
    }

    private func subtitle(_ info: NowPlayingInfo) -> String {
        [info.artist, appName(info.bundleIdentifier)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func appName(_ bundleID: String) -> String {
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

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                skip(-20)
                skip(-10)
                Button { model.send(.togglePlayPause) } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .frame(width: 44, height: 44)
                }
                skip(10)
                skip(20)
            }
            HStack(spacing: 40) {
                Button { model.send(.previous) } label: { Image(systemName: "backward.fill") }
                Button { model.send(.next) } label: { Image(systemName: "forward.fill") }
            }
        }
        .buttonStyle(.plain)
        .font(.title3)
    }

    private var playing: Bool { model.state?.nowPlaying?.playing ?? false }

    private func skip(_ seconds: Int) -> some View {
        Button { model.send(.skip(seconds: Double(seconds))) } label: {
            SkipSymbol(seconds: seconds)
        }
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
            Slider(value: $level, in: 0...1) { editing in
                dragging = editing
                if !editing { model.send(.setVolume(level)) }  // final value
            }
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
