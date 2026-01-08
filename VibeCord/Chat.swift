import Foundation

struct Chat: Identifiable, Codable, Equatable {
    let id: String           // Channel ID from Discord
    let name: String         // Username or channel name
    let avatarURL: URL?      // User avatar or channel icon
    let type: ChatType       // DM or Group DM
    let lastMessage: String? // Preview text (optional)

    // For Equatable conformance
    static func == (lhs: Chat, rhs: Chat) -> Bool {
        return lhs.id == rhs.id
    }
}

enum ChatType: String, Codable {
    case dm = "DM"
    case groupDM = "GROUP_DM"
    case textChannel = "GUILD_TEXT"
}
