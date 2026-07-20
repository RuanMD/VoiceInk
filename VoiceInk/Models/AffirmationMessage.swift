import Foundation

struct AffirmationMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var isEnabled: Bool = true
}
