//
//  ContentView.swift
//  SnakesintheGrass
//
//  Created by myle$ on 9/29/24.
//
import SwiftUI
import SpriteKit

struct ContentView: View {

    // Held in @State so SwiftUI re-rendering (e.g. on scenePhase changes)
    // never swaps in a fresh MainMenu and throws away a running game.
    @State private var scene: SKScene = {
        let scene = MainMenu()
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}
