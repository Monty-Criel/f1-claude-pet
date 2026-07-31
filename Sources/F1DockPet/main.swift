import AppKit

// `--probe` reports what the app can work out about the Dock and exits.
// Useful for diagnosing geometry without staring at a moving car.
if CommandLine.arguments.contains("--probe") {
    let dock = DockGeometry.current()
    print("Accessibility trusted : \(DockGeometry.isTrusted)")
    print("Measured exactly      : \(dock.measured)")
    print("Dock edge             : \(dock.edge.rawValue)")
    print("Dock rect             : \(dock.rect)")
    print("On screen             : \(dock.screen.frame)")
    let s = dock.straight
    print("Straight              : y=\(s.y) from x=\(s.minX) to x=\(s.maxX)")
    exit(0)
}

// `--export-sprite <path>` writes a magnified PNG of the car for art review.
if let i = CommandLine.arguments.firstIndex(of: "--export-sprite") {
    let path = CommandLine.arguments.count > i + 1
        ? CommandLine.arguments[i + 1] : "sprite.png"
    let carId = CommandLine.arguments.firstIndex(of: "--car").map { CommandLine.arguments[$0 + 1] }
    let car = carId.flatMap { CarRegistry.car(id: $0) } ?? CarRegistry.selected
    // `--deflate 0.8` renders the car with a punctured rear tyre.
    let deflation = CommandLine.arguments.firstIndex(of: "--deflate").flatMap { i -> CGFloat? in
        CommandLine.arguments.count > i + 1 ? CGFloat(Double(CommandLine.arguments[i + 1]) ?? 0) : nil
    } ?? 0
    let ok = CarRenderer.exportPNG(car: car, to: path, deflation: deflation)
    print(ok ? "wrote \(path) for \(car.displayName)" : "failed to write \(path)")
    exit(ok ? 0 : 1)
}

// `--notify <state> [--message "<text>"]` pushes a state to the running pet.
// This is what the Claude Code hooks call; it is a no-op if the pet is not
// running.
//
// Two hard rules, because this runs as a hook:
//   * absolutely nothing on stdout — stdout from some hook events is injected
//     straight into Claude's context, so a chatty hook would tax every prompt;
//   * never exit 2 — that is Claude Code's "block this tool call" signal, and a
//     typo in a hook must never be able to stop real work.
if let i = CommandLine.arguments.firstIndex(of: "--notify") {
    guard CommandLine.arguments.count > i + 1,
          let state = PetState(rawValue: CommandLine.arguments[i + 1]) else {
        let names = PetState.allCases.map(\.rawValue).joined(separator: ", ")
        FileHandle.standardError.write(Data("usage: --notify <\(names)> [--message <text>]\n".utf8))
        exit(1)
    }
    let message = CommandLine.arguments.firstIndex(of: "--message").flatMap { m -> String? in
        CommandLine.arguments.count > m + 1 ? CommandLine.arguments[m + 1] : nil
    }
    StateChannel.write(state, message: message)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory = no Dock icon, no menu bar entry. The pet is the whole UI.
app.setActivationPolicy(.accessory)
app.run()
