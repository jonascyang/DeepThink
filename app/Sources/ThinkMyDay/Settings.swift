import Foundation
import ThinkMyDayCore

/// Small preferences kept in UserDefaults. Anything recorded goes to the store instead.
enum Settings {
    private static let plannedStartKey = "plannedStart"

    static var plannedStart: PlannedStart? {
        get {
            UserDefaults.standard.data(forKey: plannedStartKey).flatMap { try? JSONDecoder().decode(PlannedStart.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: plannedStartKey)
        }
    }
}
