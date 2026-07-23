import Foundation
import SwiftData
enum ModelContainerFactory {
    static var liveSchema: Schema {
        Schema([LocationEntity.self, APIKeyEntity.self, PVSiteEntity.self,
                ForecastPointEntity.self, QuotaUsageEntity.self])
    }
    static func makeLiveContainer() throws -> ModelContainer {
        try ModelContainer(for: liveSchema,
            configurations: [ModelConfiguration(schema: liveSchema, isStoredInMemoryOnly: false)])
    }
    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: liveSchema,
            configurations: [ModelConfiguration(schema: liveSchema, isStoredInMemoryOnly: true)])
    }
}
