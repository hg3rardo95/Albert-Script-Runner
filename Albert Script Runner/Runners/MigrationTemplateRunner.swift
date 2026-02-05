//
//  MigrationTemplateRunner.swift
//  Albert Script Runner
//

import Foundation

struct MigrationTemplateRunner {
    struct TemplateValidationResult: Codable {
        struct HeaderMismatch: Codable {
            var sheet: String
            var expected: [String]
            var actual: [String]
        }

        var ok: Bool
        var missingSheets: [String]
        var headerMismatches: [HeaderMismatch]
    }

    struct ExportConfig: Codable {
        struct Include: Codable {
            struct CustomTemplates: Codable {
                var anyEnabled: Bool
                var batch: Bool
                var property: Bool
                var notebook: Bool
                var general: Bool
                var sheet: Bool
            }

            var parameterGroups: Bool
            var dataTemplates: Bool
            var customTemplates: CustomTemplates
        }

        struct FilterBlock: Codable {
            var prefix: String
            var tagsText: String
            var tags: [String]

            init(from inputs: MigrationTemplateFilterInputs) {
                self.prefix = inputs.prefix
                self.tagsText = inputs.tagsText
                self.tags = inputs.tags
            }
        }

        struct Filters: Codable {
            struct CustomTemplates: Codable {
                var batch: FilterBlock
                var property: FilterBlock
                var notebook: FilterBlock
                var general: FilterBlock
                var sheet: FilterBlock
            }

            var parameterGroups: FilterBlock
            var dataTemplates: FilterBlock
            var customTemplates: CustomTemplates
        }

        var include: Include
        var filters: Filters
        var outputPath: String
    }

    static func export(
        baseURL: String,
        token: String,
        inputs: MigrationTemplateInputs,
        outputURL: URL
    ) async throws -> String {
        let config = ExportConfig(
            include: .init(
                parameterGroups: inputs.includeParameterGroups,
                dataTemplates: inputs.includeDataTemplates,
                customTemplates: .init(
                    anyEnabled: inputs.includeTemplates,
                    batch: inputs.includeBatchTaskTemplates,
                    property: inputs.includePropertyTaskTemplates,
                    notebook: inputs.includeNotebookTemplates,
                    general: inputs.includeGeneralTaskTemplates,
                    sheet: inputs.includeSheetTemplates
                )
            ),
            filters: .init(
                parameterGroups: ExportConfig.FilterBlock(from: inputs.pgFilters),
                dataTemplates: ExportConfig.FilterBlock(from: inputs.dtFilters),
                customTemplates: .init(
                    batch: ExportConfig.FilterBlock(from: inputs.batchFilters),
                    property: ExportConfig.FilterBlock(from: inputs.propertyFilters),
                    notebook: ExportConfig.FilterBlock(from: inputs.notebookFilters),
                    general: ExportConfig.FilterBlock(from: inputs.generalFilters),
                    sheet: ExportConfig.FilterBlock(from: inputs.sheetFilters)
                )
            ),
            outputPath: outputURL.path
        )

        let tmpDir = FileManager.default.temporaryDirectory
        let configURL = tmpDir.appendingPathComponent("template_tracker_\(UUID().uuidString).json")

        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: [.atomic])

        return try await Task.detached {
            try PythonRunner.run(args: [
                "template-tracker",
                "--token", token,
                "--base-url", baseURL,
                "--config", configURL.path
            ])
        }.value
    }

    static func requiredSheets(for inputs: MigrationTemplateInputs) -> [String] {
        var sheets: [String] = []

        if inputs.includeDataTemplates {
            sheets.append("DTs")
        }
        if inputs.includeParameterGroups {
            sheets.append("PGs")
        }
        if inputs.includeBatchTaskTemplates {
            sheets.append("Batch Task Templates")
        }
        if inputs.includePropertyTaskTemplates {
            sheets.append("Property Task Templates")
        }
        if inputs.includeNotebookTemplates {
            sheets.append("Notebook Templates")
        }
        if inputs.includeGeneralTaskTemplates {
            sheets.append("General Task Templates")
        }
        if inputs.includeSheetTemplates {
            sheets.append("Sheet Templates")
        }

        return sheets
    }

    static func validateTemplate(at url: URL, sheets: [String]) async throws -> TemplateValidationResult {
        var args = [
            "template-tracker-validate",
            "--template", url.path,
        ]
        if !sheets.isEmpty {
            args += ["--sheets", sheets.joined(separator: ",")]
        }

        let output = try await Task.detached {
            try PythonRunner.run(args: args)
        }.value

        guard let data = output.data(using: .utf8) else {
            throw PythonRunnerError.runtimeError("Template validation returned invalid UTF-8.")
        }

        do {
            return try JSONDecoder().decode(TemplateValidationResult.self, from: data)
        } catch {
            throw PythonRunnerError.runtimeError("Unable to parse template validation result: \(error)")
        }
    }

    static func bundledTemplateURL() throws -> URL {
        let name = "03 - Production Migration Template"
        let ext = "xlsx"

        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }

        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources") {
            return url
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let sourceDir = sourceFileURL.deletingLastPathComponent()
        let candidateBases: [URL] = [
            sourceDir,
            sourceDir.deletingLastPathComponent(),
            sourceDir.deletingLastPathComponent().deletingLastPathComponent(),
            sourceDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
        ]

        for base in candidateBases {
            let direct = base.appendingPathComponent("Resources/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }

            let nested = base
                .appendingPathComponent("Albert Script Runner", isDirectory: true)
                .appendingPathComponent("Resources/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: nested.path) {
                return nested
            }
        }

        throw PythonRunnerError.runtimeError(
            "Bundled template not found. Expected a resource named:\n  \(name).\(ext)\n\n" +
            "Fix: add the template to the app resources, or place it at:\n" +
            "  Albert Script Runner/Resources/\(name).\(ext)"
        )
    }

    static func copyBundledTemplate(to destinationURL: URL) throws {
        let templateURL = try bundledTemplateURL()
        let folder = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.copyItem(at: templateURL, to: destinationURL)
    }

    static func replaceWithBundledTemplate(at destinationURL: URL) throws -> URL {
        let folder = destinationURL.deletingLastPathComponent()
        let basename = destinationURL.deletingPathExtension().lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        let backupURL = folder.appendingPathComponent("\(basename).backup-\(stamp).xlsx")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.moveItem(at: destinationURL, to: backupURL)
        }

        try copyBundledTemplate(to: destinationURL)
        return backupURL
    }

    static func formatValidationMessage(_ result: TemplateValidationResult) -> String {
        var lines: [String] = []

        if !result.missingSheets.isEmpty {
            let sep = ", "
            lines.append("Missing sheets: \(result.missingSheets.joined(separator: sep))")
        }

        if !result.headerMismatches.isEmpty {
            lines.append("Header mismatches:")
            for mismatch in result.headerMismatches {
                let expected = mismatch.expected.joined(separator: ", ")
                let actual = mismatch.actual.joined(separator: ", ")
                lines.append("- \(mismatch.sheet)")
                lines.append("  Expected: \(expected)")
                lines.append("  Found: \(actual)")
            }
        }

        if lines.isEmpty {
            return "The template format did not match the expected structure."
        }

        return lines.joined(separator: "\n")
    }
}
