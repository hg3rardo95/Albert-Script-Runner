//
//  MigrationTemplateInputs.swift
//  Albert Script Runner
//

import Foundation

struct MigrationTemplateFilterInputs: Codable, Hashable {
    var prefix: String = ""
    var tagsText: String = ""
    var tags: [String] = []
}

struct MigrationTemplateInputs: Codable, Hashable {
    // Core toggles
    var includeParameterGroups: Bool = false
    var includeDataTemplates: Bool = false

    // Custom templates container + subtypes
    var includeTemplates: Bool = false
    var includeBatchTaskTemplates: Bool = false
    var includePropertyTaskTemplates: Bool = false
    var includeNotebookTemplates: Bool = false
    var includeGeneralTaskTemplates: Bool = false
    var includeSheetTemplates: Bool = false

    // Filters
    var pgFilters = MigrationTemplateFilterInputs()
    var dtFilters = MigrationTemplateFilterInputs()

    var batchFilters = MigrationTemplateFilterInputs()
    var propertyFilters = MigrationTemplateFilterInputs()
    var notebookFilters = MigrationTemplateFilterInputs()
    var generalFilters = MigrationTemplateFilterInputs()
    var sheetFilters = MigrationTemplateFilterInputs()
}
