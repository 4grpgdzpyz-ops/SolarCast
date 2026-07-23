import Foundation
import SwiftUI
struct PVSite: Identifiable, Equatable, Sendable {
    let id: UUID
    var solcastSiteID: String
    var name: String
    var colorHex: String
    var apiKeyID: UUID?
    var createdAt: Date?
    init(id: UUID = UUID(), solcastSiteID: String, name: String, colorHex: String, apiKeyID: UUID? = nil, createdAt: Date? = nil) {
        self.id = id; self.solcastSiteID = solcastSiteID
        self.name = name; self.colorHex = colorHex; self.apiKeyID = apiKeyID
    }
    var color: Color { Color(hex: colorHex) }
}
