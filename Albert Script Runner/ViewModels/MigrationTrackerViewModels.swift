//
//  MigrationTrackerViewModels.swift
//  Albert Script Runner
//
//  Created by Gerardo on 1/15/26.
//

import Foundation
import Combine
import SwiftData
import SwiftUI

/// ViewModel used by MigrationTemplatesView to query and update the local deployment tracker.
///
/// Note:
/// - This file intentionally contains *no* direct Albert SDK calls.
/// - Refresh/import/export orchestration will be added later via PythonRunner + JSON merge.
@MainActor
final class MigrationTrackerViewModel: ObservableObject {

    // MARK: - UI State

    /// Selected environment label (must match what you store in the SwiftData entities).
    /// Examples: "sandbox", "dev", "production".
    @Published var selectedEnvironment: String = "sandbox"

    /// Optional tag filter (comma-separated input). If empty, no tag filtering is applied.
    @Published var tagFilterCSV: String = ""

    /// Optional prefix filter. If empty, no prefix filtering is applied.
    @Published var prefixFilter: String = ""

    /// Selected template category (matches `CustomTemplateEntity.templateKind`).
    @Published var selectedTemplateKind: TemplateKindFilter = .all

    /// Simple loading/error state for future refresh/export actions.
    @Published var isWorking: Bool = false
    @Published var lastErrorMessage: String? = nil

    // MARK: - Initialization

    init() {}

    // MARK: - Fetch helpers

    func fetchParameterGroups(modelContext: ModelContext) throws -> [ParameterGroupEntity] {
        let env = selectedEnvironment
        let descriptor = FetchDescriptor<ParameterGroupEntity>(
            predicate: #Predicate { $0.environment == env },
            sortBy: [SortDescriptor(\ParameterGroupEntity.albertId, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchDataTemplates(modelContext: ModelContext) throws -> [DataTemplateEntity] {
        let env = selectedEnvironment
        let descriptor = FetchDescriptor<DataTemplateEntity>(
            predicate: #Predicate { $0.environment == env },
            sortBy: [SortDescriptor(\DataTemplateEntity.albertId, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchCustomTemplates(modelContext: ModelContext) throws -> [CustomTemplateEntity] {
        // Capture values in locals; #Predicate cannot access self members directly
        let env = selectedEnvironment
        let kind = selectedTemplateKind.rawValue
        let isAll = (selectedTemplateKind == .all)

        let basePredicate: Predicate<CustomTemplateEntity> = #Predicate { (tpl: CustomTemplateEntity) in
            tpl.environment == env && (isAll || tpl.templateKind == kind)
        }

        let descriptor = FetchDescriptor<CustomTemplateEntity>(
            predicate: basePredicate,
            sortBy: [SortDescriptor(\CustomTemplateEntity.albertId, order: .forward)]
        )

        var results = try modelContext.fetch(descriptor)

        // Apply prefix filtering in-memory (hasPrefix isn't supported in persistent predicate)
        let trimmedPrefix = prefixFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrefix.isEmpty {
            results = results.filter { $0.name.hasPrefix(trimmedPrefix) }
        }

        // Apply tag CSV filtering in-memory
        let tags = normalizeCSV(tagFilterCSV)
        if !tags.isEmpty {
            results = results.filter { tpl in
                // simple contains-based matching on CSV field (first-pass)
                tags.contains { tag in tpl.tagsCSV.contains(tag) }
            }
        }

        return results
    }

    // MARK: - Mutations

    /// Toggle migrate flag.
    func setShouldMigrate(_ value: Bool, for entity: any PersistentModel, modelContext: ModelContext) {
        lastErrorMessage = nil

        if let pg = entity as? ParameterGroupEntity {
            pg.shouldMigrate = value
            pg.updatedAt = Date()
        } else if let dt = entity as? DataTemplateEntity {
            dt.shouldMigrate = value
            dt.updatedAt = Date()
        } else if let ct = entity as? CustomTemplateEntity {
            ct.shouldMigrate = value
            ct.updatedAt = Date()
        }

        do {
            try modelContext.save()
        } catch {
            lastErrorMessage = "Failed to save changes: \(error.localizedDescription)"
        }
    }

    /// Mark complete / incomplete.
    func setMigrationCompleted(_ isCompleted: Bool, for entity: any PersistentModel, modelContext: ModelContext) {
        lastErrorMessage = nil

        let completedAt: Date? = isCompleted ? Date() : nil

        if let pg = entity as? ParameterGroupEntity {
            pg.migrationCompletedAt = completedAt
            pg.updatedAt = Date()
        } else if let dt = entity as? DataTemplateEntity {
            dt.migrationCompletedAt = completedAt
            dt.updatedAt = Date()
        } else if let ct = entity as? CustomTemplateEntity {
            ct.migrationCompletedAt = completedAt
            ct.updatedAt = Date()
        }

        do {
            try modelContext.save()
        } catch {
            lastErrorMessage = "Failed to save changes: \(error.localizedDescription)"
        }
    }

    /// Update notes field.
    func setNotes(_ notes: String, for entity: any PersistentModel, modelContext: ModelContext) {
        lastErrorMessage = nil

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let pg = entity as? ParameterGroupEntity {
            pg.notes = trimmed
            pg.updatedAt = Date()
        } else if let dt = entity as? DataTemplateEntity {
            dt.notes = trimmed
            dt.updatedAt = Date()
        } else if let ct = entity as? CustomTemplateEntity {
            ct.notes = trimmed
            ct.updatedAt = Date()
        }

        do {
            try modelContext.save()
        } catch {
            lastErrorMessage = "Failed to save changes: \(error.localizedDescription)"
        }
    }

    // MARK: - Export helpers (Excel mapping layer lives at export-time)

    /// Convert a raw DT albertId (DAT123) to the Excel-facing ID (DT123).
    func excelDTId(from rawAlbertId: String) -> String {
        rawAlbertId.replacingOccurrences(of: "DAT", with: "DT")
    }

    /// Convert a raw PG albertId (PRG4) to the Excel-facing ID (PG4).
    func excelPGId(from rawAlbertId: String) -> String {
        rawAlbertId.replacingOccurrences(of: "PRG", with: "PG")
    }

    /// Build the same Notes hyperlink formula used by the Python script for DTs.
    func excelDTNotesHyperlink(baseURL: String, rawDTAlbertId: String) -> String {
        let dt = excelDTId(from: rawDTAlbertId)
        return "=HYPERLINK(\"\(baseURL)/#aldt/detail?query=\(dt)\",\"\(dt)\")"
    }

    /// Build the same Notes hyperlink formula used by the Python script for PGs.
    func excelPGNotesHyperlink(baseURL: String, rawPGAlbertId: String) -> String {
        let pg = excelPGId(from: rawPGAlbertId)
        return "=HYPERLINK(\"\(baseURL)/#alpg/detail?query=\(pg)\",\"\(pg)\")"
    }

    // MARK: - Private

    private func normalizeCSV(_ csv: String) -> [String] {
        csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Filters

/// Matches the template categories used by the Python migration tracker script.
enum TemplateKindFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case propertyTask = "Property Task"
    case batchTask = "Batch Task"
    case generalTask = "General Task"
    case sheet = "Sheet"
    case notebook = "Notebook"

    var id: String { rawValue }
}
