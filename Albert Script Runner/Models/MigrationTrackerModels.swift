import Foundation
import SwiftData

// MARK: - Shared helpers

/// Use a stable unique key that is safe for SwiftData uniqueness constraints.
/// We cannot enforce composite uniqueness directly, so we store a derived key.
func makeUniqueKey(environment: String, albertId: String) -> String {
    "\(environment.lowercased())|\(albertId)"
}

// MARK: - Nodes

@Model
final class ParameterGroupEntity {
    @Attribute(.unique) var uniqueKey: String

    /// Raw Albert ID, e.g. "PRG4" (export converts PRG → PG).
    var albertId: String
    var name: String

    /// Environment label, e.g. "sandbox", "dev", "production".
    var environment: String

    /// Persisted tags as a single string for compatibility and simple export.
    /// Store as comma-separated values (CSV). Example: "MIGRATE_WAVE1,CLIENT_KENVUE".
    var tagsCSV: String

    // Tracker fields
    var shouldMigrate: Bool
    var migrationCompletedAt: Date?
    var notes: String

    var migrationComplete: Bool { migrationCompletedAt != nil }

    // Sync metadata
    var lastSeenAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        albertId: String,
        name: String,
        environment: String,
        tags: [String] = [],
        shouldMigrate: Bool = false,
        migrationCompletedAt: Date? = nil,
        notes: String = "",
        lastSeenAt: Date = Date()
    ) {
        self.albertId = albertId
        self.name = name
        self.environment = environment
        self.uniqueKey = makeUniqueKey(environment: environment, albertId: albertId)

        self.tagsCSV = tags.joined(separator: ",")

        self.shouldMigrate = shouldMigrate
        self.migrationCompletedAt = migrationCompletedAt
        self.notes = notes

        self.lastSeenAt = lastSeenAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Convenience: tags as a normalized array.
    var tags: [String] {
        get {
            tagsCSV
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsCSV = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }
    }
}

@Model
final class DataTemplateEntity {
    @Attribute(.unique) var uniqueKey: String

    /// Raw Albert ID, e.g. "DAT123" (export converts DAT → DT).
    var albertId: String
    var name: String

    /// Environment label, e.g. "sandbox", "dev", "production".
    var environment: String

    /// Persisted tags as comma-separated string.
    var tagsCSV: String

    // Tracker fields
    var shouldMigrate: Bool
    var migrationCompletedAt: Date?
    var notes: String

    var migrationComplete: Bool { migrationCompletedAt != nil }

    // Sync metadata
    var lastSeenAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        albertId: String,
        name: String,
        environment: String,
        tags: [String] = [],
        shouldMigrate: Bool = false,
        migrationCompletedAt: Date? = nil,
        notes: String = "",
        lastSeenAt: Date = Date()
    ) {
        self.albertId = albertId
        self.name = name
        self.environment = environment
        self.uniqueKey = makeUniqueKey(environment: environment, albertId: albertId)

        self.tagsCSV = tags.joined(separator: ",")

        self.shouldMigrate = shouldMigrate
        self.migrationCompletedAt = migrationCompletedAt
        self.notes = notes

        self.lastSeenAt = lastSeenAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var tags: [String] {
        get {
            tagsCSV
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsCSV = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }
    }
}

@Model
final class CustomTemplateEntity {
    @Attribute(.unique) var uniqueKey: String

    /// Raw Albert ID, e.g. "CTP789".
    var albertId: String
    var name: String

    /// Environment label, e.g. "sandbox", "dev", "production".
    var environment: String

    /// Category label used for grouping into export sheets.
    /// Examples: "Property Task", "Batch Task", "General Task", "Sheet", "Notebook".
    var templateKind: String

    /// Persisted tags as comma-separated string.
    var tagsCSV: String

    // Tracker fields
    var shouldMigrate: Bool
    var migrationCompletedAt: Date?
    var notes: String

    var migrationComplete: Bool { migrationCompletedAt != nil }

    // Sync metadata
    var lastSeenAt: Date
    var createdAt: Date
    var updatedAt: Date

    // Relationships (many-to-many via link models)
    var parameterGroupLinks: [TemplateParameterGroupLinkEntity]
    var dataTemplateLinks: [TemplateDataTemplateLinkEntity]

    init(
        albertId: String,
        name: String,
        environment: String,
        templateKind: String,
        tags: [String] = [],
        shouldMigrate: Bool = false,
        migrationCompletedAt: Date? = nil,
        notes: String = "",
        lastSeenAt: Date = Date()
    ) {
        self.albertId = albertId
        self.name = name
        self.environment = environment
        self.templateKind = templateKind
        self.uniqueKey = makeUniqueKey(environment: environment, albertId: albertId)

        self.tagsCSV = tags.joined(separator: ",")

        self.shouldMigrate = shouldMigrate
        self.migrationCompletedAt = migrationCompletedAt
        self.notes = notes

        self.lastSeenAt = lastSeenAt
        self.createdAt = Date()
        self.updatedAt = Date()

        self.parameterGroupLinks = []
        self.dataTemplateLinks = []
    }

    var tags: [String] {
        get {
            tagsCSV
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsCSV = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }
    }

    /// Convenience counts for the UI.
    var parameterGroupCount: Int { parameterGroupLinks.count }
    var dataTemplateCount: Int { dataTemplateLinks.count }
}

// MARK: - Edges (join/link models)

@Model
final class TemplateParameterGroupLinkEntity {
    /// Optional stable identifier for debugging/export.
    var id: UUID

    @Relationship(deleteRule: .cascade, inverse: \CustomTemplateEntity.parameterGroupLinks)
    var template: CustomTemplateEntity

    var parameterGroup: ParameterGroupEntity

    /// Optional: keep a copy of IDs for export without deep traversal.
    var templateAlbertId: String
    var parameterGroupAlbertId: String

    init(template: CustomTemplateEntity, parameterGroup: ParameterGroupEntity) {
        self.id = UUID()
        self.template = template
        self.parameterGroup = parameterGroup
        self.templateAlbertId = template.albertId
        self.parameterGroupAlbertId = parameterGroup.albertId
    }
}

@Model
final class TemplateDataTemplateLinkEntity {
    /// Optional stable identifier for debugging/export.
    var id: UUID

    @Relationship(deleteRule: .cascade, inverse: \CustomTemplateEntity.dataTemplateLinks)
    var template: CustomTemplateEntity

    var dataTemplate: DataTemplateEntity

    /// Optional: keep a copy of IDs for export without deep traversal.
    var templateAlbertId: String
    var dataTemplateAlbertId: String

    init(template: CustomTemplateEntity, dataTemplate: DataTemplateEntity) {
        self.id = UUID()
        self.template = template
        self.dataTemplate = dataTemplate
        self.templateAlbertId = template.albertId
        self.dataTemplateAlbertId = dataTemplate.albertId
    }
}

