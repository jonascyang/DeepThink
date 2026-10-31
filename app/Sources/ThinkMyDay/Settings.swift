import Foundation
import ThinkMyDayCore

/// Small preferences kept in UserDefaults. Anything recorded goes to the store instead.
enum Settings {
    private static let plannedStartKey = "plannedStart"
    private static let ocrKey = "ocrEnabled"
    private static let idleKey = "idleMinutes"

    /// OCR when a window has no readable text. On by default (PRD §6.3).
    static var ocrEnabled: Bool {
        get { UserDefaults.standard.object(forKey: ocrKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: ocrKey) }
    }

    /// Minutes without input before a record marks no input: 1, 3 (default) or 5.
    static var idleMinutes: Int {
        get { UserDefaults.standard.object(forKey: idleKey) as? Int ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: idleKey) }
    }

    static var captureOptions: Capturer.Options {
        Capturer.Options(ocrEnabled: ocrEnabled, idleThreshold: TimeInterval(idleMinutes * 60))
    }

    static var plannedStart: PlannedStart? {
        get {
            UserDefaults.standard.data(forKey: plannedStartKey).flatMap { try? JSONDecoder().decode(PlannedStart.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: plannedStartKey)
        }
    }
}
