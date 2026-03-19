import Foundation

nonisolated enum CharacterModelService {
    static func modelURL(for character: PlayerCharacterType) -> URL? {
        modelURL(named: character.fileName)
    }

    static func modelURL(named fileName: String) -> URL? {
        glbURL(named: fileName) ?? usdzURL(named: fileName)
    }

    static func glbURL(for character: PlayerCharacterType) -> URL? {
        glbURL(named: character.fileName)
    }

    static func glbURL(named fileName: String) -> URL? {
        Bundle.main.url(forResource: fileName, withExtension: "glb", subdirectory: "Resources/Characters")
            ?? Bundle.main.url(forResource: fileName, withExtension: "glb")
    }

    static func usdzURL(for character: PlayerCharacterType) -> URL? {
        usdzURL(named: character.fileName)
    }

    static func usdzURL(named fileName: String) -> URL? {
        Bundle.main.url(forResource: fileName, withExtension: "usdz", subdirectory: "Resources/Characters")
            ?? Bundle.main.url(forResource: fileName, withExtension: "usdz")
    }
}
