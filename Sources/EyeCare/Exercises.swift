import Foundation

struct Exercise: Equatable {
    let title: String
    let detail: String
}

extension ExerciseCategory {
    var exercises: [Exercise] {
        switch self {
        case .eyes:
            return [
                Exercise(title: "20-20-20", detail: "Look at something about 20 feet (6 m) away for 20 seconds."),
                Exercise(title: "Palming", detail: "Rub your palms together and cup them over closed eyes for 30 seconds."),
                Exercise(title: "Blink reset", detail: "Blink slowly 10 times, then close your eyes for 10 seconds."),
                Exercise(title: "Figure eight", detail: "Trace a large sideways 8 with your eyes, slowly, 5 times each way."),
                Exercise(title: "Near and far", detail: "Focus on your thumb up close, then on a far object. Repeat 10 times."),
            ]
        case .stretch:
            return [
                Exercise(title: "Neck rolls", detail: "Slowly roll your head in a circle, 5 times each direction."),
                Exercise(title: "Shoulder shrugs", detail: "Lift shoulders to your ears, hold 3 seconds, release. Repeat 10 times."),
                Exercise(title: "Chest opener", detail: "Clasp hands behind your back, straighten arms and lift gently. Hold 20 seconds."),
                Exercise(title: "Seated twist", detail: "Sit tall, rotate your torso to one side and hold 15 seconds. Switch sides."),
                Exercise(title: "Wrist stretch", detail: "Extend one arm, gently pull fingers back with the other hand. 15 seconds each."),
                Exercise(title: "Standing side bend", detail: "Reach one arm overhead and lean to the opposite side. 15 seconds each."),
                Exercise(title: "Hamstring reach", detail: "Stand and slowly reach towards your toes. Hold 20 seconds, knees soft."),
            ]
        case .exercise:
            return [
                Exercise(title: "Squats", detail: "15 bodyweight squats. Keep your chest up and heels down."),
                Exercise(title: "Desk push-ups", detail: "Hands on the edge of your desk, 12 slow push-ups."),
                Exercise(title: "Calf raises", detail: "20 calf raises, holding the top for a second."),
                Exercise(title: "Lunges", detail: "10 alternating lunges per leg."),
                Exercise(title: "Wall sit", detail: "Back against a wall, knees at 90°. Hold for 30-45 seconds."),
                Exercise(title: "March in place", detail: "March briskly in place for 60 seconds, knees high."),
                Exercise(title: "Plank", detail: "Hold a forearm plank for 30 seconds."),
            ]
        case .posture:
            return [
                Exercise(title: "Posture check", detail: "Feet flat, back against the chair, screen at eye level, shoulders relaxed."),
                Exercise(title: "Chin tucks", detail: "Pull your chin straight back, hold 5 seconds. Repeat 10 times."),
                Exercise(title: "Shoulder blade squeeze", detail: "Squeeze shoulder blades together, hold 5 seconds. Repeat 10 times."),
            ]
        case .hydrate:
            return [
                Exercise(title: "Water break", detail: "Drink a full glass of water."),
                Exercise(title: "Refill", detail: "Walk to refill your bottle. Bonus steps!"),
            ]
        case .custom:
            return []
        }
    }

    func randomExercise(excluding current: Exercise? = nil) -> Exercise? {
        let pool = exercises.filter { $0 != current }
        return pool.randomElement() ?? exercises.first
    }
}
