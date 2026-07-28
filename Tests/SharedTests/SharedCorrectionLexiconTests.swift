import Foundation
import Testing
@testable import VibeVoiceShared

struct SharedCorrectionLexiconTests {
    @Test func parsesSourceColumn() {
        let text = """
        # canonical\tpinyin_code\taliases\tkind\tweight\tsource
        魔法棒\tmofabang\t魔法帮|魔发棒\tphrase\t12000\tuser
        Core ML\tcoreml\t扣肉ML\tproper\t100\tproject
        """
        let entries = SharedCorrectionLexicon.parse(text: text)
        #expect(entries.count == 2)
        let wand = entries.first { $0.pinyinCode == "mofabang" }
        #expect(wand?.canonical == "魔法棒")
        #expect(wand?.aliases == ["魔法帮", "魔发棒"])
        #expect(wand?.source == .user)
        let ml = entries.first { $0.pinyinCode == "coreml" }
        #expect(ml?.source == .project)
        #expect(ml?.kind == .proper)
    }

    @Test func serializesRoundTripKeepsSource() {
        let entries = [
            SharedCorrectionEntry(
                canonical: "魔法棒",
                pinyinCode: "mofabang",
                aliases: ["魔法帮"],
                kind: .phrase,
                weight: 12000,
                source: .user
            ),
        ]
        let text = SharedCorrectionLexicon.serialize(entries)
        #expect(text.contains("\tuser\n") || text.hasSuffix("\tuser\n"))
        let parsed = SharedCorrectionLexicon.parse(text: text)
        #expect(parsed.first?.source == .user)
        #expect(parsed.first?.aliases == ["魔法帮"])
    }

    @Test func migratesLegacyProjectTSVWithMigratedSource() {
        let legacy = """
        # code\tdisplay\tkind
        coreml\tCore ML\tproject
        vibevoiceoss\tVibeVoiceOSS\tproject
        """
        let entries = SharedCorrectionLexicon.entriesFromLegacyProjectTSV(legacy)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.source == .migrated })
        #expect(entries.contains { $0.canonical == "Core ML" && $0.pinyinCode == "coreml" })
    }

    @Test func correctionPromptIncludesSourceLabelAndAliases() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedCorrection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let lexicon = SharedCorrectionLexicon(directory: dir)
        #expect(lexicon.replaceAll([
            SharedCorrectionEntry(
                canonical: "魔法棒",
                pinyinCode: "mofabang",
                aliases: ["魔法帮"],
                kind: .phrase,
                weight: 12000,
                source: .user
            ),
        ]))
        let block = lexicon.correctionPromptBlock()
        #expect(block.contains("魔法帮 → 魔法棒"))
        #expect(block.contains("来源：用户"))
    }

    @Test func mergingASRPromptAppendsAndCaps() {
        let merged = SharedCorrectionLexicon.mergingASRPrompt(
            "Alice",
            terms: ["Core ML", "魔法棒", "Alice"],
            maxChars: 40
        )
        #expect(merged.contains("Alice"))
        #expect(merged.contains("Core ML"))
        #expect(merged.count <= 40)
    }

    @Test func diskLoadMigratesLegacyWhenSharedMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedCorrection-mig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacy = dir.appendingPathComponent("project.tsv")
        try "coreml\tCore ML\tproject\n".write(to: legacy, atomically: true, encoding: .utf8)

        let lexicon = SharedCorrectionLexicon(directory: dir)
        let entries = lexicon.allEntries()
        #expect(entries.count == 1)
        #expect(entries[0].source == .migrated)
        #expect(FileManager.default.fileExists(atPath: lexicon.storageURL.path))
        let saved = try String(contentsOf: lexicon.storageURL, encoding: .utf8)
        #expect(saved.contains("\tmigrated"))
    }
}
