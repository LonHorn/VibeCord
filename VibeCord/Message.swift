import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: String
    let authorName: String
    let avatarURL: URL?
    let content: String
    let timestamp: Date = Date() // Local timestamp for UI simplicity

    // For Equatable conformance
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id
    }
}
