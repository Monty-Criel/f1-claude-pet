import Foundation

/// Every car the pet knows how to drive. Add new models here — a model needs
/// nothing beyond its own file conforming to `Car` and an entry in `all`.
enum CarRegistry {
    static let all: [any Car] = [
        RB22(),
        SF26(),
    ] + F1Grid.all + GT3Grid.all

    /// Cars grouped for the menu bar, in category order.
    static var byCategory: [(CarCategory, [any Car])] {
        CarCategory.allCases.compactMap { category in
            let cars = all.filter { $0.category == category }
            return cars.isEmpty ? nil : (category, cars)
        }
    }

    static let fallback: any Car = RB22()

    static func car(id: String) -> (any Car)? {
        all.first { $0.id == id }
    }

    /// The car to drive: whatever was last chosen in the menu bar, else the RB22.
    static var selected: any Car {
        get {
            guard let id = UserDefaults.standard.string(forKey: "selectedCar") else { return fallback }
            return car(id: id) ?? fallback
        }
        set { UserDefaults.standard.set(newValue.id, forKey: "selectedCar") }
    }
}
