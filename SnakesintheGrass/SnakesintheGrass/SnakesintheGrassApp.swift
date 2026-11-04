//
//  SnakesintheGrassApp.swift
//  SnakesintheGrass
//
//  Created by myle$ on 9/29/24.
//

import SwiftUI

@main
struct SnakesintheGrassApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Save the run whenever the app leaves the foreground. GameScene
            // also listens for UIScene notifications; saving twice is harmless.
            // Resuming does NOT reload from disk: the live scene already holds
            // the state, so there is no double-load.
            if phase != .active {
                GameScene.active?.handleAppBackgrounded()
            }
        }
    }
}
