//
//  Albert_Script_RunnerApp.swift
//  Albert Script Runner
//
//  Created by Gerardo on 1/7/26.
//

import SwiftUI
import SwiftData

@main
struct Albert_Script_RunnerApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for:
                    ParameterGroupEntity.self,
                    DataTemplateEntity.self,
                    CustomTemplateEntity.self,
                    TemplateParameterGroupLinkEntity.self,
                    TemplateDataTemplateLinkEntity.self
            )
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
