import AppKit

// Some MacBook Pro Touch Bars develop a hardware fault: part of the panel shows
// flickering lines while macOS is drawing a clean picture. macOS has no switch for
// the bar, so this uses the two private frameworks the system itself uses:
// DFRBrightness to blank the panel, DFRFoundation to learn when something lit it again.
enum TouchBar {
    private static let brightness = load("DFRBrightness")
    private static let foundation = load("DFRFoundation")

    // Bit of DFRGetStatus() that is set while the panel is dark (observed on
    // macOS 15.5: 0x1 lit, 0x5 dark).
    private static let panelDarkBit = 0x4

    private static func load(_ framework: String) -> UnsafeMutableRawPointer {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/\(framework).framework/\(framework)", RTLD_NOW) else {
            fatalError("\(framework).framework did not load")
        }
        return handle
    }

    private static func function<T>(_ name: String, as type: T.Type) -> T {
        guard let address = dlsym(foundation, name) else {
            fatalError("\(name) is missing from DFRFoundation.framework")
        }
        return unsafeBitCast(address, to: type)
    }

    static var isLit: Bool {
        let status = function("DFRGetStatus", as: (@convention(c) () -> Int).self)()
        return status & panelDarkBit == 0
    }

    // The handler runs on a DFRFoundation queue each time the status changes.
    static func onStatusChange(_ handler: @escaping @Sendable @convention(block) (Int) -> Void) {
        typealias Register = @convention(c) (@Sendable @convention(block) (Int) -> Void) -> Void
        function("DFRRegisterStatusChangeCallback", as: Register.self)(handler)
    }

    static func set(on: Bool) -> Bool {
        _ = brightness
        guard let clientClass = NSClassFromString("DFRBrightnessClient") as? NSObject.Type else {
            fatalError("DFRBrightnessClient is missing from DFRBrightness.framework")
        }
        // A new client per call: a client reports the state it last set rather than
        // the panel's, so a kept one cannot be trusted after the system relit the panel.
        let client = clientClass.init()
        let selector = NSSelectorFromString(on ? "turnOn" : "turnOff")
        guard client.responds(to: selector) else {
            fatalError("DFRBrightnessClient does not respond to \(selector)")
        }
        typealias Call = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(client.method(for: selector), to: Call.self)(client, selector)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    // Dark is the resting state: this app is for a panel that is faulty when lit.
    // "Turn Touch Bar On" lifts this until the next click on the icon, wake or login.
    private var keepOff = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button,
              let image = NSImage(systemSymbolName: "lightbulb.slash", accessibilityDescription: "Touch Bar off") else {
            fatalError("the status bar button or its symbol is unavailable")
        }
        image.isTemplate = true
        button.image = image
        button.toolTip = "Click: Touch Bar off. Right-click: turn it back on, quit."
        button.target = self
        button.action = #selector(clicked)
        // One click must be enough to stop the flicker, so the menu is on the right button.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        menu.addItem(withTitle: "Turn Touch Bar Off", action: #selector(turnOff), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Turn Touch Bar On", action: #selector(turnOn), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // The system lights the panel at login and after wake at a moment of its own
        // choosing, so react to the status change itself instead of timing a guess.
        TouchBar.onStatusChange { [weak self] _ in
            DispatchQueue.main.async { self?.darkenIfLit() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        darkenIfLit()
    }

    private func darkenIfLit() {
        if keepOff && TouchBar.isLit { apply(on: false) }
    }

    @objc private func woke() {
        keepOff = true
        darkenIfLit()
    }

    @objc private func clicked() {
        guard let event = NSApp.currentEvent else {
            fatalError("the status item was clicked without an event")
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            turnOff()
        }
    }

    @objc private func turnOff() {
        keepOff = true
        apply(on: false)
    }

    @objc private func turnOn() {
        keepOff = false
        apply(on: true)
    }

    private func apply(on: Bool) {
        if TouchBar.set(on: on) { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The Touch Bar did not turn \(on ? "on" : "off")"
        alert.informativeText = "DFRBrightnessClient refused the request."
        alert.runModal()
    }
}

// `TouchBarOff off|on` does the same from a terminal; without arguments it is the menu bar item.
// While the menu bar item is running and keeping the bar off, a terminal `on` is undone at once.
let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty {
    guard arguments == ["off"] || arguments == ["on"] else {
        FileHandle.standardError.write(Data("usage: TouchBarOff [off|on]\n".utf8))
        exit(64)
    }
    guard TouchBar.set(on: arguments == ["on"]) else {
        FileHandle.standardError.write(Data("DFRBrightnessClient refused the request\n".utf8))
        exit(1)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
