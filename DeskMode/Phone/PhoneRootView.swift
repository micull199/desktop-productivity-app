import SwiftUI
import UIKit

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

// MARK: - Shared style

private enum PhoneStyle {
    static let cornerRadius: CGFloat = 16
    static let padding: CGFloat = 16
    static let gutter: CGFloat = 20
    static let accent = Color(red: 0.25, green: 0.52, blue: 0.98)
    static let accentDeep = Color(red: 0.12, green: 0.36, blue: 0.9)
    static let good = Color(red: 0.2, green: 0.82, blue: 0.4)
    static let warn = Color.orange
    static let idle = Color.white.opacity(0.3)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Haptics for the handful of actions that deserve them.
@MainActor
enum PhoneHaptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)

    static func tap() { light.impactOccurred() }
    static func action() { medium.impactOccurred() }
}

/// A grouped card: thin material over black, 16 pt continuous corners, hairline edge.
private struct PhoneCard<Content: View>: View {
    var padding: CGFloat = PhoneStyle.padding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PhoneStyle.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PhoneStyle.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
    }
}

private struct InsetDivider: View {
    var body: some View {
        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 36)
    }
}

// MARK: - Setup (no display attached)

private struct SetupView: View {
    @ObservedObject private var session = DesktopSession.shared
    @ObservedObject private var input = InputRouter.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PhoneStyle.gutter) {
                hero
                statusCard
                howItWorks
                previewButton
                quickSettings
                diagnostics
                Text("Every setting is also available in Settings on the desktop (⌘,).")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, PhoneStyle.gutter)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(
            ZStack {
                Color.black
                RadialGradient(colors: [PhoneStyle.accentDeep.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 420)
            }
            .ignoresSafeArea()
        )
    }

    // Hero

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(PhoneStyle.accentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: PhoneStyle.accent.opacity(0.35), radius: 18, y: 8)
            VStack(spacing: 4) {
                Text("DeskMode")
                    .font(.system(size: 34, weight: .bold))
                Text("Your iPhone, as a desktop.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    // Status

    private var statusCard: some View {
        PhoneCard(padding: 0) {
            VStack(spacing: 0) {
                StatusRow(tone: session.displayState.isConnected ? .good : .idle,
                          title: "Display",
                          state: session.displayState.isConnected ? "Connected · \(session.displayDescription)" : "Not connected",
                          fix: session.displayState.isConnected ? nil :
                            StatusFix(text: "Keep DeskMode open, then connect USB-C to a monitor or an HDMI adapter."))
                InsetDivider()
                StatusRow(tone: input.keyboardConnected ? .good : .idle,
                          title: "Keyboard",
                          state: input.keyboardConnected ? "Connected" : "Not detected",
                          fix: input.keyboardConnected ? nil :
                            StatusFix(text: "Pair in Settings › Bluetooth, or plug in over USB-C. The on-screen keyboard also works."))
                InsetDivider()
                StatusRow(tone: mouseTone, title: "Mouse", state: mouseState, fix: mouseFix)
            }
        }
    }

    private var mouseTone: StatusTone {
        guard input.mouseConnected else { return .idle }
        return input.mouseMovementSeen ? .good : .warn
    }

    private var mouseState: String {
        guard input.mouseConnected else { return "Not detected" }
        return input.mouseMovementSeen ? "Connected" : "Connected, no movement"
    }

    private var mouseFix: StatusFix? {
        if input.mouseConnected, !input.mouseMovementSeen {
            return StatusFix(text: "Turn on Settings › Accessibility › Touch › AssistiveTouch, then move the mouse.",
                             buttonTitle: "Open Settings", action: openSystemSettings)
        }
        if !input.mouseConnected {
            return StatusFix(text: "Pair in Settings › Bluetooth. Without a mouse this screen works as a trackpad.")
        }
        return nil
    }

    private func openSystemSettings() {
        PhoneHaptics.tap()
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "How it works")
            PhoneCard {
                VStack(alignment: .leading, spacing: 14) {
                    StepRow(number: 1, symbol: "cable.connector", title: "Connect the display",
                            text: "Plug into a monitor over USB-C. The desktop appears on it automatically.")
                    StepRow(number: 2, symbol: "cursorarrow.motionlines", title: "Move the mouse",
                            text: "Drive the cursor on the big screen. This screen dims and stays unlocked.")
                    StepRow(number: 3, symbol: "command", title: "Work like a Mac",
                            text: "⌘Space opens the launcher, ⌘T a new tab, ⌘` switches windows.")
                }
            }
        }
    }

    // Preview

    private var previewButton: some View {
        Button {
            PhoneHaptics.action()
            session.beginPhonePreview()
        } label: {
            Label("Preview the desktop on this iPhone", systemImage: "iphone.landscape")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(PhoneStyle.accentGradient, in: RoundedRectangle(cornerRadius: PhoneStyle.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }

    // Quick settings

    private var quickSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Quick settings")
            PhoneCard(padding: 0) {
                VStack(spacing: 0) {
                    SettingToggle(symbol: "moon.fill", title: "Dim iPhone screen while connected", isOn: $settings.dimPhoneWhenConnected)
                    InsetDivider()
                    SettingToggle(symbol: "hand.draw.fill", title: "Use the iPhone as a trackpad", isOn: $settings.phoneAsTrackpad)
                    InsetDivider()
                    SettingToggle(symbol: "arrow.up.and.down", title: "Natural scrolling", isOn: $settings.naturalScrolling)
                    InsetDivider()
                    SettingToggle(symbol: "macwindow", title: "Request desktop websites", isOn: $settings.desktopWebsites)
                    InsetDivider()
                    VStack(spacing: 10) {
                        HStack {
                            Label("Cursor speed", systemImage: "cursorarrow")
                                .labelStyle(SettingLabelStyle())
                            Spacer()
                            Text(String(format: "%.1f×", settings.cursorSpeed))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.cursorSpeed, in: 0.4...4.0, step: 0.2)
                            .tint(PhoneStyle.accent)
                    }
                    .padding(.horizontal, PhoneStyle.padding)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // Diagnostics

    private var diagnostics: some View {
        PhoneCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    if session.diagnostics.isEmpty {
                        Text("No display events yet. Connect the monitor while DeskMode is open and events will appear here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(session.diagnostics.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    HStack(spacing: 10) {
                        SmallButton(title: "Check now", symbol: "arrow.clockwise") {
                            PhoneHaptics.tap()
                            ExternalDisplayMonitor.shared.recheck(reason: "manual check")
                        }
                        SmallButton(title: "Copy", symbol: "doc.on.doc") {
                            PhoneHaptics.tap()
                            UIPasteboard.general.string = session.diagnostics.joined(separator: "\n")
                        }
                        Spacer()
                    }
                }
                .padding(.top, 12)
            } label: {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
                    .labelStyle(SettingLabelStyle())
            }
            .tint(.secondary)
        }
    }
}

// MARK: - Setup building blocks

private enum StatusTone {
    case good, warn, idle

    var color: Color {
        switch self {
        case .good: return PhoneStyle.good
        case .warn: return PhoneStyle.warn
        case .idle: return PhoneStyle.idle
        }
    }
}

private struct StatusFix {
    var text: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil
}

private struct StatusRow: View {
    let tone: StatusTone
    let title: String
    let state: String
    let fix: StatusFix?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Circle()
                    .fill(tone.color)
                    .frame(width: 9, height: 9)
                    .shadow(color: tone == .idle ? .clear : tone.color.opacity(0.6), radius: 4)
                    .frame(width: 12)
                Text(title).font(.body.weight(.medium))
                Spacer()
                Text(state)
                    .font(.subheadline)
                    .foregroundStyle(tone == .idle ? AnyShapeStyle(.secondary) : AnyShapeStyle(tone.color))
                    .multilineTextAlignment(.trailing)
            }
            if let fix {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(fix.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let buttonTitle = fix.buttonTitle, let action = fix.action {
                        Spacer(minLength: 0)
                        Button(buttonTitle, action: action)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PhoneStyle.accent)
                            .buttonStyle(.plain)
                            .fixedSize()
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.horizontal, PhoneStyle.padding)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}

private struct StepRow: View {
    let number: Int
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PhoneStyle.accent.opacity(0.18))
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PhoneStyle.accent)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number). \(title)").font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            configuration.title.font(.body)
        }
    }
}

private struct SettingToggle: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: symbol).labelStyle(SettingLabelStyle())
        }
        .tint(PhoneStyle.accent)
        .padding(.horizontal, PhoneStyle.padding)
        .padding(.vertical, 10)
        .onChange(of: isOn) { _, _ in PhoneHaptics.tap() }
    }
}

private struct SmallButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(.primary)
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Connected (desktop running on the monitor)

private struct ConnectedView: View {
    @ObservedObject private var session = DesktopSession.shared
    @ObservedObject private var input = InputRouter.shared
    @ObservedObject private var settings = Settings.shared
    @State private var softKeyboard = false
    @State private var showControls = false
    @State private var hintsVisible = false
    @State private var hintsShown = false
    @State private var hintTask: Task<Void, Never>?

    private var controlsVisible: Bool { showControls || !session.phoneScreenDimmed }

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
            VStack(spacing: 0) {
                if controlsVisible {
                    controls
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if hintsVisible, !session.phoneScreenDimmed, settings.phoneAsTrackpad {
                    GestureHints()
                        .transition(.opacity)
                        .padding(.bottom, 28)
                }
                if input.mouseConnected, !input.mouseMovementSeen, controlsVisible {
                    assistiveTouchHint
                        .transition(.opacity)
                }
            }
            SoftKeyboardBridge(isActive: $softKeyboard)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .animation(.easeInOut(duration: 0.22), value: controlsVisible)
        .animation(.easeOut(duration: 0.6), value: hintsVisible)
        .onChange(of: session.phoneScreenDimmed) { _, dimmed in
            if !dimmed {
                showControls = true
                if !hintsShown { showHints() }
            } else {
                softKeyboard = false
            }
        }
        .onAppear {
            showControls = !session.phoneScreenDimmed
            if !session.phoneScreenDimmed { showHints() }
        }
        .onDisappear { hintTask?.cancel() }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Desktop is on your display").font(.headline)
                    Text("\(session.displayDescription) · \(session.openWindowCount) window\(session.openWindowCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(input.keyboardConnected ? PhoneStyle.good : Color.secondary)
                    Image(systemName: "computermouse")
                        .foregroundStyle(input.mouseConnected ? (input.mouseMovementSeen ? PhoneStyle.good : PhoneStyle.warn) : Color.secondary)
                    Button {
                        PhoneHaptics.tap()
                        showControls = false
                        if settings.dimPhoneWhenConnected, !session.phoneScreenDimmed { session.dimPhoneScreen() }
                    } label: {
                        Text("Hide")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .font(.system(size: 14, weight: .medium))
            }
            HStack(spacing: 10) {
                ControlButton(symbol: softKeyboard ? "keyboard.chevron.compact.down" : "keyboard",
                              title: softKeyboard ? "Hide Keys" : "Keyboard", active: softKeyboard) {
                    softKeyboard.toggle()
                }
                ControlButton(symbol: session.phoneScreenDimmed ? "sun.max" : "moon",
                              title: session.phoneScreenDimmed ? "Wake" : "Dim") {
                    if session.phoneScreenDimmed { session.wakePhoneScreen() } else { session.dimPhoneScreen(); showControls = false }
                }
                ControlButton(symbol: "globe", title: "Chrome") { session.openApp(.browser) }
                ControlButton(symbol: "gearshape", title: "Settings") { session.openApp(.settings) }
            }
        }
        .padding(PhoneStyle.padding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PhoneStyle.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PhoneStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var assistiveTouchHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Mouse connected but silent. Turn on Settings › Accessibility › Touch › AssistiveTouch.")
        }
        .font(.footnote)
        .foregroundStyle(PhoneStyle.warn)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PhoneStyle.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func toggleControls() {
        if session.phoneScreenDimmed {
            session.wakePhoneScreen()
            showControls = true
        } else {
            showControls.toggle()
        }
        PhoneHaptics.tap()
    }

    private func showHints() {
        hintsShown = true
        hintsVisible = true
        hintTask?.cancel()
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            hintsVisible = false
        }
    }
}

private struct GestureHints: View {
    private let hints: [(String, String)] = [
        ("hand.draw", "Drag to move the cursor"),
        ("hand.tap", "Tap to click"),
        ("arrow.up.and.down", "Two fingers to scroll"),
        ("hand.tap.fill", "Two-finger tap to right-click"),
        ("cursorarrow.click.2", "Double-tap, then drag to move things")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(hints, id: \.1) { symbol, text in
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 22)
                    Text(text).font(.subheadline)
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .allowsHitTesting(false)
    }
}

private struct ControlButton: View {
    let symbol: String
    let title: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button {
            PhoneHaptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(active ? PhoneStyle.accent : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}
