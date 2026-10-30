import SwiftUI

/// Everything shown on the iPhone's own screen.
struct PhoneRootView: View {
    @ObservedObject private var session = DesktopSession.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if session.displayState.isConnected {
                ConnectedView()
                    .transition(.opacity)
            } else {
                SetupView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.displayState.isConnected)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Setup (no display attached)

private struct SetupView: View {
    @ObservedObject private var session = DesktopSession.shared
    @ObservedObject private var input = InputRouter.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                statusCards
                displayLog
                steps
                Button {
                    session.beginPhonePreview()
                } label: {
                    Label("Preview the desktop on this iPhone", systemImage: "iphone.landscape")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                settingsSection
                tips
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(colors: [Color(red: 0.07, green: 0.1, blue: 0.2), .black], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("DeskMode").font(.system(size: 30, weight: .bold))
                    Text("Your iPhone, as a desktop").foregroundStyle(.secondary)
                }
            }
            Text("Plug your iPhone into a monitor, pair a keyboard and mouse, and DeskMode turns the display into a desktop with a cursor, windows and a full browser. The phone screen goes dark while you work.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var statusCards: some View {
        VStack(spacing: 10) {
            StatusCard(symbol: "display", title: "Display", detail: session.displayDescription, ok: session.displayState.isConnected,
                       hint: "Keep DeskMode open, then connect USB-C to a monitor (DisplayPort) or an HDMI adapter.")
            StatusCard(symbol: "keyboard", title: "Keyboard", detail: input.keyboardConnected ? "Connected" : "Not detected", ok: input.keyboardConnected,
                       hint: "Pair in Settings › Bluetooth, or plug in over USB-C.")
            StatusCard(symbol: "computermouse", title: "Mouse", detail: input.mouseConnected ? "Connected" : "Not detected", ok: input.mouseConnected,
                       hint: "Pair in Settings › Bluetooth. Without a mouse the iPhone screen works as a trackpad.")
        }
    }

    private var displayLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Display log").font(.headline)
                Spacer()
                Button("Check now") { ExternalDisplayMonitor.shared.recheck(reason: "manual check") }
                    .font(.caption)
            }
            .padding(.bottom, 2)
            if session.diagnostics.isEmpty {
                Text("No display events yet. Connect the monitor while DeskMode is open and events will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.diagnostics.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works").font(.headline)
            Step(number: 1, text: "Open DeskMode and connect the display. The desktop appears on the monitor automatically.")
            Step(number: 2, text: "Move the mouse to drive the cursor on the big screen. The iPhone screen dims to black and stays unlocked.")
            Step(number: 3, text: "Use ⌘Space for the launcher, ⌘T for a new browser tab and ⌘` to switch windows, just like a Mac.")
            Step(number: 4, text: "Keep DeskMode in the foreground; switching apps hands the display back to iOS mirroring.")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quick settings").font(.headline).padding(.bottom, 6)
            Toggle("Dim iPhone screen while connected", isOn: $settings.dimPhoneWhenConnected)
            Toggle("Use the iPhone as a trackpad", isOn: $settings.phoneAsTrackpad)
            Toggle("Natural scrolling", isOn: $settings.naturalScrolling)
            Toggle("Request desktop websites", isOn: $settings.desktopWebsites)
            HStack {
                Text("Cursor speed")
                Spacer()
                Text(String(format: "%.1f×", settings.cursorSpeed)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $settings.cursorSpeed, in: 0.4...4.0, step: 0.2)
            Text("Every setting is also available in the Settings app on the desktop.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tips").font(.headline)
            Text("• If the cursor does not move with a Bluetooth mouse, enable Settings › Accessibility › Touch › AssistiveTouch once; iOS then exposes the mouse to apps.")
            Text("• A powered USB-C hub lets you charge, connect the display and use wired peripherals at the same time.")
            Text("• Press and hold one finger on the dark phone screen to wake it and show the controls.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct StatusCard: View {
    let symbol: String
    let title: String
    let detail: String
    let ok: Bool
    let hint: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(ok ? Color.green.opacity(0.25) : Color.white.opacity(0.08)))
                .foregroundStyle(ok ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(detail).font(.subheadline).foregroundStyle(ok ? Color.green : Color.secondary)
                }
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Connected (desktop running on the monitor)

private struct ConnectedView: View {
    @ObservedObject private var session = DesktopSession.shared
    @ObservedObject private var input = InputRouter.shared
    @ObservedObject private var settings = Settings.shared
    @State private var softKeyboard = false
    @State private var showControls = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if settings.phoneAsTrackpad {
                TrackpadView(onLongHold: { toggleControls() })
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                    .onLongPressGesture(minimumDuration: 0.9) { toggleControls() }
            }
            VStack {
                if showControls || !session.phoneScreenDimmed {
                    controls
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if settings.phoneAsTrackpad, showControls || !session.phoneScreenDimmed {
                    Text(input.mouseConnected ? "Trackpad active alongside your mouse" : "Drag to move the cursor · tap to click · two fingers to scroll")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 24)
                }
            }
            SoftKeyboardBridge(isActive: $softKeyboard)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .onChange(of: session.phoneScreenDimmed) { _, dimmed in
            if !dimmed { showControls = true }
        }
        .onAppear { showControls = !session.phoneScreenDimmed }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Desktop is on your display").font(.headline)
                    Text("\(session.displayDescription) · \(session.openWindowCount) window\(session.openWindowCount == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "keyboard").foregroundStyle(input.keyboardConnected ? Color.green : Color.secondary)
                    Image(systemName: "computermouse").foregroundStyle(input.mouseConnected ? Color.green : Color.secondary)
                }
            }
            HStack(spacing: 10) {
                ControlButton(symbol: softKeyboard ? "keyboard.chevron.compact.down" : "keyboard", title: softKeyboard ? "Hide keys" : "Keyboard") {
                    softKeyboard.toggle()
                }
                ControlButton(symbol: session.phoneScreenDimmed ? "sun.max" : "moon", title: session.phoneScreenDimmed ? "Wake screen" : "Dim screen") {
                    if session.phoneScreenDimmed { session.wakePhoneScreen() } else { session.dimPhoneScreen(); showControls = false }
                }
                ControlButton(symbol: "safari", title: "Browser") { session.openApp(.browser) }
                ControlButton(symbol: "gearshape", title: "Settings") { session.openApp(.settings) }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.08)))
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private func toggleControls() {
        if session.phoneScreenDimmed {
            session.wakePhoneScreen()
            showControls = true
        } else {
            showControls.toggle()
        }
    }
}

private struct ControlButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
