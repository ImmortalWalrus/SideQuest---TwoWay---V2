import SwiftUI

enum ProfileBackgroundStyle {
    static let defaultName: String = "gradient1"

    static func gradient(named name: String?) -> LinearGradient {
        switch normalizedPersistedName(name) {
        case "Sunset Blaze":
            LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Arctic Frost":
            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Royal Night":
            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "Emerald Dream":
            LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static func shopName(for persistedName: String?) -> String? {
        switch persistedName {
        case "Sunset Blaze", "gradient2":
            "Sunset Blaze"
        case "Arctic Frost":
            "Arctic Frost"
        case "Royal Night", "gradient4":
            "Royal Night"
        case "Emerald Dream", "gradient3":
            "Emerald Dream"
        default:
            nil
        }
    }

    static func normalizedPersistedName(_ name: String?) -> String {
        shopName(for: name) ?? defaultName
    }
}
