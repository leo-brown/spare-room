import Foundation

struct Person: Codable, Identifiable { let id: String; let name: String; let email: String }
struct Network: Codable, Identifiable { let id: String; let name: String; let code: String; let ownerId: String; let muted: Int }
struct Member: Codable, Identifiable { let networkId: String; let id: String; let name: String }
struct Room: Codable, Identifiable {
    let id: String; let networkId: String; let ownerId: String; let title: String
    let street: String; let city: String; let postalCode: String; let country: String
    let roomType: String; let timezone: String; let description: String; let guests: Int; let hostName: String
    var location: String { "\(city), \(country)" }
}
struct Period: Codable, Identifiable { let id: String; let roomId: String; let start: String; let end: String; let kind: String }
struct Stay: Codable, Identifiable {
    let id: String; let roomId: String; let guestId: String; let start: String; let end: String
    let guests: Int; let message: String; let status: String; let guestName: String
    let roomTitle: String; let hostId: String; let networkId: String
}
struct Booking: Codable { let id: String; let roomId: String; let start: String; let end: String }
struct Photo: Codable, Identifiable { let id: String; let roomId: String }
struct Snapshot: Codable {
    let photos: [Photo]
    let user: Person; let networks: [Network]; let rooms: [Room]; let periods: [Period]
    let stays: [Stay]; let bookings: [Booking]; let members: [Member]; let cursor: Int
}
struct AuthResponse: Codable { let token: String; let user: Person; let recoveryKey: String? }
struct RoomEvent: Codable, Identifiable { let id: Int; let networkId: String; let kind: String; let title: String; let body: String }
struct EventPage: Codable { let events: [RoomEvent]; let cursor: Int }

extension Date {
    var dayCode: String {
        let parts = Calendar.current.dateComponents([.year,.month,.day], from: self)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    func addingDays(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: self)! }
}
func dayLabel(_ s: String) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: s) else { return s }
    return d.formatted(date: .abbreviated, time: .omitted)
}
extension Snapshot {
    func isFree(_ room: Room, _ date: String) -> Bool {
        let matches = periods.filter { $0.roomId == room.id && $0.start <= date && date < $0.end }
        return matches.contains { $0.kind == "free" } && !matches.contains { $0.kind == "busy" }
            && !bookings.contains { $0.roomId == room.id && $0.start <= date && date < $0.end }
    }
    func isFree(_ room: Room, start: Date, end: Date) -> Bool {
        guard start.dayCode < end.dayCode else { return false }
        var d = start
        while d.dayCode < end.dayCode {
            if !isFree(room, d.dayCode) { return false }
            d = d.addingDays(1)
        }
        return true
    }
}
