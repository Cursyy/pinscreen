import SwiftUI
import AppKit
import ServiceManagement
internal import Combine

enum Side: String, CaseIterable, Identifiable {
    case left, right, top, bottom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }
}

final class LoginItem: ObservableObject {
    @Published var enabled = SMAppService.mainApp.status == .enabled

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {}
        enabled = SMAppService.mainApp.status == .enabled
    }
}

@main
struct PinScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var login = LoginItem()

    var body: some Scene {
        MenuBarExtra("PinScreen", systemImage: "display.2") {
            Button("Show picker") { delegate.showPicker() }
            Toggle("Launch at login", isOn: Binding(
                get: { login.enabled },
                set: { login.set($0) }
            ))
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: KeyPanel?
    var clickMonitor: Any?
    var autoClose: DispatchWorkItem?
    var lastCount = AppDelegate.activeDisplays().count

    static func activeDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &n) == .success else { return [] }
        return Array(ids.prefix(Int(n)))
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let ids = AppDelegate.activeDisplays()
            let builtin = ids.filter { CGDisplayIsBuiltin($0) != 0 }.count
            if ids.count == 2 && self.lastCount == 1 && builtin == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if AppDelegate.activeDisplays().count == 2 { self.showPicker() }
                }
            }
            self.lastCount = ids.count
        }
    }

    func dismiss() {
        autoClose?.cancel()
        autoClose = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        panel?.close()
        panel = nil
    }

    func showPicker() {
        dismiss()
        let view = PickerView(
            onPick: { [weak self] side in
                self?.apply(side)
                self?.dismiss()
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        let host = NSHostingView(rootView: view)
        host.setFrameSize(host.fittingSize)

        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.contentView = host
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.hasShadow = true
        p.onEscape = { [weak self] in self?.dismiss() }
        if let s = NSScreen.screens.first {
            let f = s.frame
            p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2,
                                     y: f.midY - p.frame.height / 2))
        }
        p.orderFrontRegardless()
        p.makeKey()
        panel = p

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.dismiss() }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        autoClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    func apply(_ side: Side) {
        let ids = AppDelegate.activeDisplays()
        guard ids.count == 2,
              let mac = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }),
              let ext = ids.first(where: { $0 != mac }) else { return }

        let mb = CGDisplayBounds(mac), eb = CGDisplayBounds(ext)
        let d: CGPoint = switch side {
        case .right:  CGPoint(x: mb.width, y: 0)
        case .left:   CGPoint(x: -eb.width, y: 0)
        case .top:    CGPoint(x: (mb.width - eb.width) / 2, y: -eb.height)
        case .bottom: CGPoint(x: (mb.width - eb.width) / 2, y: mb.height)
        }

        let moved: CGDirectDisplayID
        let origin: CGPoint
        if CGMainDisplayID() == ext {
            moved = mac
            origin = CGPoint(x: eb.minX - d.x, y: eb.minY - d.y)
        } else {
            moved = ext
            origin = CGPoint(x: mb.minX + d.x, y: mb.minY + d.y)
        }

        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        CGConfigureDisplayOrigin(cfg, moved, Int32(origin.x), Int32(origin.y))
        if CGCompleteDisplayConfiguration(cfg, .permanently) != .success {
            CGCancelDisplayConfiguration(cfg)
        }
    }
}

struct PickerView: View {
    let onPick: (Side) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Where is your new monitor?")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(Side.allCases) { side in
                    LayoutButton(side: side) { onPick(side) }
                }
            }
            Button("Skip", action: onClose)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct LayoutButton: View {
    let side: Side
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                LayoutIcon(side: side)
                Text(side.title).font(.caption)
            }
            .padding(10)
            .background(hover ? Color.accentColor.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct LayoutIcon: View {
    let side: Side

    var body: some View {
        let off: CGSize = switch side {
        case .left:   .init(width: -34, height: 0)
        case .right:  .init(width: 34, height: 0)
        case .top:    .init(width: 0, height: -24)
        case .bottom: .init(width: 0, height: 24)
        }
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.5))
                .frame(width: 30, height: 20)
            RoundedRectangle(cornerRadius: 4).fill(Color.accentColor)
                .frame(width: 30, height: 20)
                .offset(off)
        }
        .frame(width: 100, height: 70)
    }
}
