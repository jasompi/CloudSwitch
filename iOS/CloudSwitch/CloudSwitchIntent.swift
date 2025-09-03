//
//  OpenCloudSwitchIntent.swift
//  CloudSwitch
//
//  Created by Jasom Pi on 11/24/24.
//

import Foundation
import AppIntents
import os

extension AppDelegate: @unchecked Sendable {
}
extension CloudSwitchModel: @unchecked Sendable {
}

struct CloudSwitchEntity: AppEntity, Identifiable {
    nonisolated(unsafe) static var typeDisplayRepresentation: TypeDisplayRepresentation = "Cloud Switch"

    nonisolated(unsafe) static var defaultQuery = CloudSwitchQuery()

    var id: String
    
    @Property(title: "name")
    var name: String;

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)"
        )
    }
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

struct CloudSwitchQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CloudSwitchEntity] {
        let cloudSwitchModel = await AppDelegate.shared.cloudSwitchModel
        return identifiers.compactMap { Int( $0 ) }.map { CloudSwitchEntity(id: String($0), name: cloudSwitchModel.switchNames[$0])
        }
    }
    func suggestedEntities() async throws -> [CloudSwitchEntity] {
        let cloudSwitchModel = await AppDelegate.shared.cloudSwitchModel
        return (0..<Int(cloudSwitchModel.numberOfSwitches)).map { CloudSwitchEntity(id: String($0), name: cloudSwitchModel.switchNames[$0]) }
    }
}

struct ToggleCloudSwitchIntent : AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Toggle Cloud Switch"

    nonisolated(unsafe) static var description = IntentDescription("Toggle the Cloud Switch")
    
    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Name")
    var cloudSwitch: CloudSwitchEntity
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let cloudSwitchModel = AppDelegate.shared.cloudSwitchModel
        try await cloudSwitchModel.toggleSwitch(UInt(cloudSwitch.id) ?? UInt(0))
        return .result()
    }
    
    static var parameterSummary: any ParameterSummary {
        Summary("Toggle \(\.$cloudSwitch)")
    }
    
    init() {}
    
    init(cloudSwitch: CloudSwitchEntity) {
        self.cloudSwitch = cloudSwitch
    }
}

struct CloudSwitchIntent : AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Open Cloud Switch"

    nonisolated(unsafe) static var description = IntentDescription("Open the Cloud Switch")
    
    @MainActor
    func perform() async throws -> some IntentResult {
        return .result()
    }
      
    nonisolated(unsafe) static var openAppWhenRun: Bool = true
}
