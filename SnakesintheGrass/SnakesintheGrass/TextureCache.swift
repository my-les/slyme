//
//  TextureCache.swift
//  slyme
//
//  Centralized texture cache to avoid repeated SKTexture allocations.
//  Textures are loaded once and reused across scenes and frames.
//

import SpriteKit

@MainActor
final class TextureCache {
    static let shared = TextureCache()
    
    private var cache: [String: SKTexture] = [:]
    
    private init() {
        // Preload commonly used textures at launch
        Task { await preloadCommonTextures() }
    }
    
    /// Get a cached texture or load it if not present.
    func texture(named name: String) -> SKTexture {
        if let cached = cache[name] {
            return cached
        }
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        cache[name] = texture
        return texture
    }
    
    /// Preload all skin textures for better first-paint performance.
    func preloadSkinTextures(for skin: Skin) async {
        let pieces = SkinCatalog.pieces
        await withTaskGroup(of: Void.self) { group in
            for piece in pieces {
                group.addTask { [weak self] in
                    let name = skin.textureName(for: piece)
                    await MainActor.run {
                        _ = self?.texture(named: name)
                    }
                }
            }
        }
    }
    
    /// Preload common textures at app launch (apple, og skin pieces).
    private func preloadCommonTextures() async {
        // Preload apple (food)
        _ = texture(named: "apple")
        
        // Preload og (default) skin
        if let ogSkin = SkinCatalog.skin(id: SkinCatalog.defaultID) {
            await preloadSkinTextures(for: ogSkin)
        }
    }
    
    /// Clear unused textures to free memory (called on memory warning).
    func clearCache() {
        cache.removeAll()
    }
}
