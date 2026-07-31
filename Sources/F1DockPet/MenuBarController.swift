import AppKit

/// Menu bar control for the pet.
///
/// The app runs as an `.accessory` — no Dock icon, no menu bar of its own — so
/// a status item is the only place to put controls. It also means the pet can
/// be paused or quit without going back to a terminal, which matters once it
/// starts automatically with every shell.
@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private weak var trackView: TrackView?
    private let onQuit: () -> Void

    /// Opens the pit-wall chat. Wired by the app delegate.
    var onReply: (() -> Void)?

    init(trackView: TrackView, onQuit: @escaping () -> Void) {
        self.trackView = trackView
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "flag.checkered",
                                   accessibilityDescription: "F1 Dock Pet")
            button.image?.isTemplate = true
        }
        rebuild()
    }

    /// Menus are rebuilt on demand so checkmarks always reflect live state.
    func rebuild() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(item("Reply to Claude…", #selector(reply)))
        menu.addItem(.separator())

        let paused = trackView?.isPaused ?? false
        menu.addItem(item(paused ? "Resume" : "Pause", #selector(togglePause)))
        menu.addItem(.separator())

        // Cars, grouped by category with a submenu per class.
        let carsItem = NSMenuItem(title: "Car", action: nil, keyEquivalent: "")
        let cars = NSMenu()
        for (category, entries) in CarRegistry.byCategory {
            let group = NSMenuItem(title: category.displayName, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for car in entries {
                let entry = item(car.displayName, #selector(selectCar(_:)))
                entry.representedObject = car.id
                entry.state = (trackView?.car.id == car.id) ? .on : .off
                sub.addItem(entry)
            }
            group.submenu = sub
            cars.addItem(group)
        }
        carsItem.submenu = cars
        menu.addItem(carsItem)

        // Behaviour
        let lively = item("Lively mode", #selector(toggleLively))
        lively.state = (trackView?.livelyMode ?? false) ? .on : .off
        lively.toolTip = "Full-Dock laps and bigger smoke. Off by default so the pet "
            + "stays out of your peripheral vision."
        menu.addItem(lively)
        menu.addItem(.separator())

        // Manual triggers, mostly for checking the animations.
        let testItem = NSMenuItem(title: "Trigger", action: nil, keyEquivalent: "")
        let tests = NSMenu()
        for state in PetState.allCases {
            let entry = item(state.rawValue.capitalized, #selector(trigger(_:)))
            entry.representedObject = state.rawValue
            tests.addItem(entry)
        }
        testItem.submenu = tests
        menu.addItem(testItem)
        menu.addItem(.separator())

        menu.addItem(item("Restart", #selector(restart)))
        menu.addItem(item("Quit", #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.isEnabled = true
        return entry
    }

    // MARK: - actions

    @objc private func togglePause() {
        trackView?.isPaused.toggle()
        rebuild()
    }

    @objc private func selectCar(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let car = CarRegistry.car(id: id) else { return }
        trackView?.car = car
        CarRegistry.selected = car      // remembered across restarts
        rebuild()
    }

    @objc private func toggleLively() {
        trackView?.livelyMode.toggle()
        rebuild()
    }

    @objc private func trigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let state = PetState(rawValue: raw) else { return }
        trackView?.apply(state)
    }

    /// Relaunch in place.
    ///
    /// A detached shell waits for this process to die and then reopens us —
    /// relaunching from inside the app that is quitting cannot work, and
    /// `open` on an already-running bundle would just activate the existing
    /// instance rather than starting a fresh one.
    @objc private func restart() {
        let bundle = Bundle.main.bundlePath
        let command: String
        if bundle.hasSuffix(".app") {
            command = "sleep 0.6; open \"\(bundle)\""
        } else {
            // Running the bare binary (swift build), not the bundle.
            let exe = Bundle.main.executablePath ?? ""
            command = "sleep 0.6; \"\(exe)\" >/dev/null 2>&1 &"
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        try? task.run()

        onQuit()
    }

    @objc private func reply() { onReply?() }

    @objc private func quit() { onQuit() }
}
