import Foundation

@Observable
final class RoutinesViewModel {
    var medications: [Medication] = []
    var dailyCheckIn = DailyCheckIn()
    var rituals: [WeeklyRitual] = []

    var showAddMedication = false
    var showAddRitual = false

    private let notificationService = NotificationService()

    init() {
        loadFromStorage()
    }

    func addMedication(_ medication: Medication) {
        medications.append(medication)
        notificationService.scheduleMedicationReminder(medication)
        saveToStorage()
    }

    func removeMedication(at index: Int) {
        medications.remove(at: index)
        saveToStorage()
    }

    func addRitual(_ ritual: WeeklyRitual) {
        rituals.append(ritual)
        saveToStorage()
    }

    func removeRitual(at index: Int) {
        rituals.remove(at: index)
        saveToStorage()
    }

    // MARK: - Persistence (UserDefaults for simplicity)

    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(medications) {
            UserDefaults.standard.set(data, forKey: "medications")
        }
        if let data = try? JSONEncoder().encode(dailyCheckIn) {
            UserDefaults.standard.set(data, forKey: "dailyCheckIn")
        }
        if let data = try? JSONEncoder().encode(rituals) {
            UserDefaults.standard.set(data, forKey: "rituals")
        }
    }

    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: "medications"),
           let decoded = try? JSONDecoder().decode([Medication].self, from: data) {
            medications = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "dailyCheckIn"),
           let decoded = try? JSONDecoder().decode(DailyCheckIn.self, from: data) {
            dailyCheckIn = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "rituals"),
           let decoded = try? JSONDecoder().decode([WeeklyRitual].self, from: data) {
            rituals = decoded
        }
    }
}
