import Foundation

struct Expense: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var amount: Double
    var date: Date
    var category: String
}
