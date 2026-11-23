import Foundation
import HealthKit

/// A workout read from Apple Health, reduced to what the app shows.
struct WorkoutSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let icon: String          // SF Symbol
    let start: Date
    let duration: TimeInterval
    let kcal: Double
    let distanceKm: Double?

    var detail: String {
        var parts = [DayKey.time(start), Self.durationLabel(duration)]
        if let km = distanceKm, km >= 0.05 { parts.append(String(format: "%.1f km", km)) }
        return parts.joined(separator: " · ")
    }

    /// 52 min · 1 h 26 min · 2 h
    static func durationLabel(_ t: TimeInterval) -> String {
        let mins = Int((t / 60).rounded())
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static func describe(_ type: HKWorkoutActivityType, indoor: Bool?) -> (name: String, icon: String) {
        switch type {
        case .traditionalStrengthTraining: return ("Strength training", "dumbbell.fill")
        case .functionalStrengthTraining: return ("Functional strength", "dumbbell.fill")
        case .coreTraining: return ("Core training", "figure.core.training")
        case .highIntensityIntervalTraining: return ("HIIT", "figure.highintensity.intervaltraining")
        case .walking: return (indoor == true ? "Indoor walk" : "Outdoor walk", "figure.walk")
        case .running: return (indoor == true ? "Indoor run" : "Outdoor run", "figure.run")
        case .cycling: return (indoor == true ? "Indoor cycle" : "Outdoor cycle", "figure.outdoor.cycle")
        case .hiking: return ("Hike", "figure.hiking")
        case .swimming: return ("Swim", "figure.pool.swim")
        case .rowing: return ("Rowing", "figure.rower")
        case .elliptical: return ("Elliptical", "figure.elliptical")
        case .stairClimbing, .stairs: return ("Stairs", "figure.stairs")
        case .yoga: return ("Yoga", "figure.yoga")
        case .pilates: return ("Pilates", "figure.pilates")
        case .flexibility: return ("Flexibility", "figure.flexibility")
        case .cooldown: return ("Cooldown", "figure.cooldown")
        case .mixedCardio: return ("Mixed cardio", "figure.mixed.cardio")
        case .crossTraining: return ("Cross training", "figure.cross.training")
        case .boxing, .kickboxing, .martialArts: return ("Combat training", "figure.boxing")
        case .dance, .socialDance, .cardioDance: return ("Dance", "figure.dance")
        case .soccer: return ("Football", "figure.soccer")
        case .tennis: return ("Tennis", "figure.tennis")
        case .golf: return ("Golf", "figure.golf")
        case .climbing: return ("Climbing", "figure.climbing")
        default: return ("Workout", "figure.mixed.cardio")
        }
    }
}
