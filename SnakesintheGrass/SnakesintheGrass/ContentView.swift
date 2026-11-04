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
        #if DEBUG
        if let debugScene = ContentView.debugLaunchScene() { return debugScene }
        #endif
        let scene = MainMenu()
        scene.scaleMode = .resizeFill
        return scene
    }()

    #if DEBUG
    /// Testing only. Launch arguments:
    ///   -slymeUnlockAll YES|NO   -slymeSkin <id>   -slymeMap <id>
    ///   -slymeStart game|skins|maps|twoplayer|twoplayermatch|online|onlinefinding|onlinedemo   -slymeTwoDemo   -slymeLongSnake   -slymeFreeze
    private static func debugLaunchScene() -> SKScene? {
        let d = UserDefaults.standard // launch args land in the argument domain
        let store = EntitlementStore.shared
        if d.object(forKey: "slymeUnlockAll") != nil { store.debugUnlockAll = d.bool(forKey: "slymeUnlockAll") }
        if let s = SkinCatalog.skin(id: d.string(forKey: "slymeSkin")) { store.selectedSkin = s }
        if let m = MapCatalog.map(id: d.string(forKey: "slymeMap")) { store.selectedMap = m }
        let scene: SKScene
        switch d.string(forKey: "slymeStart") {
        case "game":
            UserDefaults.standard.removeObject(forKey: "savedGameState")
            scene = GameScene(size: .zero)
        case "skins": scene = CustomizeScene(size: .zero, page: .skins)
        case "maps": scene = CustomizeScene(size: .zero, page: .maps)
        case "twoplayer": scene = TwoPlayerSetupScene(size: .zero)
        case "twoplayermatch":
            scene = TwoPlayerScene(size: .zero, p1Skin: store.selectedSkin,
                                   p2Skin: SkinCatalog.skin(id: "ember") ?? store.selectedSkin,
                                   map: store.selectedMap, facing: TwoPlayerConfig.defaultFacing)
        case "online": scene = OnlineLobbyScene(size: .zero)
        case "onlinefinding": scene = OnlineLobbyScene(size: .zero, forcedStatus: .finding)
        case "onlinedemo": scene = OnlineMatchScene.loopbackDemo(size: .zero, autopilot: true)
        default: return nil
        }
        scene.scaleMode = .resizeFill
        return scene
    }
    #endif

    var body: some View {
        SpriteView(scene: scene)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}
