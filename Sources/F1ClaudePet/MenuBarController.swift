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

    /// Second car management, wired by the app delegate: nil turns it off.
    var onSecondCar: ((Transcript.SessionRef?) -> Void)?
    var currentSecondaryId: (() -> String?)?

    /// Lets the app delegate move the second car to the opposite end.
    var onPitHomeChanged: ((TrackView.PitHome) -> Void)?

    /// Applies a new chat panel size to every open panel.
    var onChatSizeChanged: ((ChatController.Size) -> Void)?
    private var secondCandidates: [Transcript.SessionRef] = []

    /// Rebuilt menus throw their views away, so these are held here rather
    /// than recreated — the slider must survive long enough to be dragged.
    private let speedSlider = NSSlider()
    private let speedLabel = NSTextField(labelWithString: "")

    init(trackView: TrackView, onQuit: @escaping () -> Void) {
        self.trackView = trackView
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "flag.checkered",
                                   accessibilityDescription: "F1 Claude Pet")
            button.image?.isTemplate = true
        }
        rebuild()
    }

    /// Menus are rebuilt on demand so checkmarks always reflect live state.
    func rebuild() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(item("Reply to Claude…", #selector(reply)))

        // Only surfaced when it is actually missing, and it is the difference
        // between the car tracking the Dock exactly and guessing the middle.
        if !DockGeometry.isTrusted {
            let grant = item("Grant Accessibility…", #selector(grantAccessibility))
            grant.subtitle = "Needed to track the Dock exactly"
            menu.addItem(grant)
        }
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

        // A second car, parked on the left, bound to another session — its
        // bubble shows that session's name and clicking it opens that chat.
        let secondItem = NSMenuItem(title: "Second car (Beta)", action: nil, keyEquivalent: "")
        let second = NSMenu()
        let currentSecond = currentSecondaryId?()

        let off = item("Off", #selector(secondOff))
        off.state = currentSecond == nil ? .on : .off
        second.addItem(off)
        second.addItem(.separator())

        // Recent sessions. The one the primary car is living stays visible
        // but disabled — silently hiding it made the list look mis-ordered.
        let liveId = StateChannel.readSession()?.id
        secondCandidates = []
        for session in Transcript.recentSessions(limit: 5) {
            if session.id == liveId {
                let entry = NSMenuItem(title: session.label, action: nil, keyEquivalent: "")
                entry.isEnabled = false
                entry.subtitle = "first car's session"
                second.addItem(entry)
                continue
            }
            secondCandidates.append(session)
            let entry = item(session.label, #selector(secondPick(_:)))
            entry.tag = secondCandidates.count - 1
            entry.state = session.id == currentSecond ? .on : .off
            entry.subtitle = session.project
            second.addItem(entry)
        }
        secondItem.submenu = second
        menu.addItem(secondItem)

        // Pirelli compound — worn by the F1 cars only; GT3s keep their own rubber.
        let tyresItem = NSMenuItem(title: "Tyres", action: nil, keyEquivalent: "")
        let tyres = NSMenu()
        for compound in TyreCompound.allCases {
            let entry = item(compound.displayName, #selector(selectCompound(_:)))
            entry.representedObject = compound.rawValue
            entry.state = TyreCompound.selected == compound ? .on : .off
            tyres.addItem(entry)
        }
        tyresItem.submenu = tyres
        tyresItem.subtitle = "F1 cars only"
        menu.addItem(tyresItem)

        // Which end of the Dock the car calls home.
        let pitItem = NSMenuItem(title: "Pit box", action: nil, keyEquivalent: "")
        let pits = NSMenu()
        for (home, label) in [(TrackView.PitHome.left, "Left end"),
                              (TrackView.PitHome.right, "Right end")] {
            let entry = item(label, #selector(selectPitHome(_:)))
            entry.representedObject = home.rawValue
            entry.state = trackView?.pitHome == home ? .on : .off
            pits.addItem(entry)
        }
        pitItem.submenu = pits
        pitItem.subtitle = "Where it parks and idles"
        menu.addItem(pitItem)

        // Chat panel size.
        let sizeItem = NSMenuItem(title: "Chat size", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for choice in ChatController.Size.allCases {
            let entry = item(choice.displayName, #selector(selectChatSize(_:)))
            entry.representedObject = choice.rawValue
            entry.state = ChatController.Size.selected == choice ? .on : .off
            entry.subtitle = "\(Int(choice.width))×\(Int(choice.height))"
            sizes.addItem(entry)
        }
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)

        // Accent colour for the panel, bubble and spinner.
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themes = NSMenu()
        for choice in ThemeColor.allCases {
            let entry = item(choice.displayName, #selector(selectTheme(_:)))
            entry.representedObject = choice.rawValue
            entry.state = ThemeColor.selected == choice ? .on : .off
            // A colour swatch reads faster than the name alone.
            let swatch = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                choice.color.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
                return true
            }
            entry.image = swatch
            themes.addItem(entry)
        }
        themeItem.submenu = themes
        themeItem.subtitle = ThemeColor.selected.displayName
        menu.addItem(themeItem)

        // Pace while Claude is working. A slider rather than presets: the
        // right speed depends on how big your Dock is and how distracting you
        // find movement, and neither is something to guess for you.
        let speedItem = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        speedItem.view = speedView()
        menu.addItem(speedItem)

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
            let entry = item(state.displayName, #selector(trigger(_:)))
            entry.representedObject = state.rawValue
            entry.subtitle = state.summary
            tests.addItem(entry)
        }
        testItem.submenu = tests
        menu.addItem(testItem)
        menu.addItem(.separator())

        menu.addItem(item("Restart", #selector(restart)))
        menu.addItem(item("Quit", #selector(quit)))
        statusItem.menu = menu
    }

    /// A labelled slider laid out to sit inside the menu like a normal row.
    private func speedView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 44))

        let title = NSTextField(labelWithString: "Speed")
        title.frame = NSRect(x: 21, y: 24, width: 80, height: 16)
        title.font = .menuFont(ofSize: 13)
        view.addSubview(title)

        speedLabel.frame = NSRect(x: 101, y: 24, width: 98, height: 16)
        speedLabel.alignment = .right
        speedLabel.font = .menuFont(ofSize: 11)
        speedLabel.textColor = .secondaryLabelColor
        view.addSubview(speedLabel)

        // Indexed over the presets rather than the raw multiplier, so the knob
        // clicks into each named slot instead of landing between them.
        speedSlider.frame = NSRect(x: 21, y: 4, width: 178, height: 22)
        speedSlider.minValue = 0
        speedSlider.maxValue = Double(TrackView.speedPresets.count - 1)
        speedSlider.numberOfTickMarks = TrackView.speedPresets.count
        speedSlider.allowsTickMarkValuesOnly = true
        speedSlider.tickMarkPosition = .below
        speedSlider.integerValue = TrackView.speedPresetIndex
        speedSlider.isContinuous = true
        speedSlider.target = self
        speedSlider.action = #selector(speedChanged(_:))
        view.addSubview(speedSlider)

        updateSpeedLabel()
        return view
    }

    private func updateSpeedLabel() {
        let preset = TrackView.speedPresets[TrackView.speedPresetIndex]
        speedLabel.stringValue = String(format: "%@ · %.2f×", preset.name, preset.factor)
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

    @objc private func selectCompound(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let compound = TyreCompound(rawValue: raw) else { return }
        TyreCompound.selected = compound
        rebuild()
    }

    /// Live while you drag: the car changes pace under the open menu, which is
    /// the only way to judge whether the setting is right.
    @objc private func speedChanged(_ sender: NSSlider) {
        let index = min(TrackView.speedPresets.count - 1, max(0, sender.integerValue))
        TrackView.speedFactor = TrackView.speedPresets[index].factor
        updateSpeedLabel()
    }

    @objc private func selectChatSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let choice = ChatController.Size(rawValue: raw) else { return }
        onChatSizeChanged?(choice)
        rebuild()
    }

    @objc private func selectPitHome(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let home = TrackView.PitHome(rawValue: raw) else { return }
        trackView?.pitHome = home
        TrackView.preferredPitHome = home
        onPitHomeChanged?(home)
        rebuild()
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let choice = ThemeColor(rawValue: raw) else { return }
        ThemeColor.selected = choice        // posts Theme.changed
        trackView?.needsDisplay = true
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

    @objc private func secondOff() {
        onSecondCar?(nil)
        rebuild()
    }

    @objc private func secondPick(_ sender: NSMenuItem) {
        guard secondCandidates.indices.contains(sender.tag) else { return }
        onSecondCar?(secondCandidates[sender.tag])
        rebuild()
    }

    @objc private func grantAccessibility() {
        DockGeometry.requestAccessibilityIfNeeded()
        DockGeometry.openAccessibilitySettings()
    }

    @objc private func quit() { onQuit() }
}
