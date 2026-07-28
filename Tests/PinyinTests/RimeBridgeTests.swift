import Foundation
import Testing
@testable import VibeVoiceRime

struct RimeBridgeTests {
    @Test func librimeLoadsBundledSimplifiedPinyinSchema() throws {
        // librime owns a process-global runtime and starts a maintenance
        // thread. The regular XCTest process also loads MLX/AVFoundation, so
        // the destructive runtime smoke is opt-in; CI still validates the C
        // ABI through vv_rime_available(), while build-app runs the isolated
        // IMK process smoke.
        guard ProcessInfo.processInfo.environment["VIBE_VOICE_RUN_RIME_SMOKE"] == "1",
              vv_rime_available() != 0 else { return }
        let shared = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/InputMethod/RimeData", isDirectory: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vibevoice-rime-\(UUID().uuidString)")
        let user = root.appendingPathComponent("User", isDirectory: true)
        let staging = root.appendingPathComponent("Build", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let handle = shared.path.withCString { sharedPath in
            user.path.withCString { userPath in
                staging.path.withCString { stagingPath in
                    "vibe_pinyin".withCString { schema in
                        vv_rime_create(sharedPath, userPath, stagingPath, schema)
                    }
                }
            }
        }
        let rimeHandle = try #require(handle)
        defer { vv_rime_destroy(rimeHandle) }
        var preedit = Array(repeating: CChar(0), count: 4096)
        var candidates = Array(repeating: CChar(0), count: 4096)
        var highlighted: Int32 = 0
        var pageNumber: Int32 = 0
        var isLastPage: Int32 = 1
        for key in "nihao".utf8 {
            _ = vv_rime_process(rimeHandle, Int32(key), 0, nil, 0)
        }
        #expect(vv_rime_snapshot(
            rimeHandle,
            &preedit, preedit.count,
            &candidates, candidates.count,
            &highlighted, &pageNumber, &isLastPage
        ) != 0)
        #expect(String(cString: preedit).isEmpty == false)
        // Each record is text + 0x1e + comment, so the separator must survive
        // the round trip even when librime supplies no comment.
        #expect(String(cString: candidates).contains("\u{1e}"))
    }

    @Test func shiftTogglesAsciiMode() throws {
        guard ProcessInfo.processInfo.environment["VIBE_VOICE_RUN_RIME_SMOKE"] == "1",
              vv_rime_available() != 0 else { return }
        let shared = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/InputMethod/RimeData", isDirectory: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vibevoice-rime-shift-\(UUID().uuidString)")
        let user = root.appendingPathComponent("User", isDirectory: true)
        let staging = root.appendingPathComponent("Build", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let handle = shared.path.withCString { sharedPath in
            user.path.withCString { userPath in
                staging.path.withCString { stagingPath in
                    "vibe_pinyin".withCString { schema in
                        vv_rime_create(sharedPath, userPath, stagingPath, schema)
                    }
                }
            }
        }
        let rimeHandle = try #require(handle)
        defer { vv_rime_destroy(rimeHandle) }
        let shiftL: Int32 = 0xffe1
        let shiftMask: Int32 = 1 << 0
        let releaseMask: Int32 = 1 << 30
        func ascii() -> Bool { "ascii_mode".withCString { vv_rime_get_option(rimeHandle, $0) != 0 } }
        #expect(ascii() == false)
        _ = vv_rime_process(rimeHandle, shiftL, shiftMask, nil, 0)
        _ = vv_rime_process(rimeHandle, shiftL, releaseMask, nil, 0)
        #expect(ascii() == true)
        _ = vv_rime_process(rimeHandle, shiftL, shiftMask, nil, 0)
        _ = vv_rime_process(rimeHandle, shiftL, releaseMask, nil, 0)
        #expect(ascii() == false)
    }
}
