import XCTest
@testable import VibeVoiceMobile

/// `HostChannel.sample` is not covered here on purpose: it needs a live
/// `UITextDocumentProxy`, and a fake one would only prove that a switch
/// statement maps enums, while the real risk in that function — which traits a
/// given host actually publishes — cannot be reproduced without the host. What
/// is tested is everything a wrong answer would be blamed on.
final class DiagnosticsTests: XCTestCase {
    // MARK: - Redaction

    /// The whole diagnostics layer rests on this: if user text can reach a log
    /// line, the log cannot be pulled off a device or pasted into an issue.
    func testFingerprintDoesNotContainTheText() {
        let secret = "今天下午三点开会"
        let printed = MobileLog.fingerprint(secret)
        XCTAssertFalse(printed.contains(secret))
        for character in secret {
            XCTAssertFalse(printed.contains(character), "leaked \(character)")
        }
        XCTAssertTrue(printed.hasPrefix("len=8 "))
    }

    func testFingerprintMatchesForEqualTextAndDiffersOtherwise() {
        XCTAssertEqual(MobileLog.fingerprint("你好"), MobileLog.fingerprint("你好"))
        XCTAssertNotEqual(MobileLog.fingerprint("你好"), MobileLog.fingerprint("您好"))
        XCTAssertEqual(MobileLog.fingerprint(""), "len=0")
    }

    /// Length is counted in characters, not UTF-8 bytes, so it lines up with
    /// what the keyboard thinks it inserted.
    func testFingerprintLengthCountsCharacters() {
        XCTAssertTrue(MobileLog.fingerprint("中文").hasPrefix("len=2 "))
        XCTAssertTrue(MobileLog.fingerprint("ab").hasPrefix("len=2 "))
    }

    // MARK: - Insertion probe

    func testInsertionLandedWhenTheDocumentEndsWithTheText() {
        XCTAssertEqual(
            InsertionProbe.evaluate(expected: "好", before: "你", after: "你好"),
            .landed
        )
    }

    /// The context is a window onto the document, so a host is free to drop
    /// characters off the front as it grows. Only the tail may be compared.
    func testInsertionLandedWhenTheHostTruncatedTheContextWindow() {
        XCTAssertEqual(
            InsertionProbe.evaluate(
                expected: "好",
                before: "aaaaaaaaaa",
                after: "aaaaaaaaa好"
            ),
            .landed
        )
    }

    func testInsertionMissingWhenNothingChanged() {
        XCTAssertEqual(
            InsertionProbe.evaluate(expected: "好", before: "你", after: "你"),
            .missing
        )
    }

    /// A host running its own input pipeline can accept the edit and then
    /// rewrite it. That is neither success nor a dropped insertion.
    func testInsertionDivergedWhenTheHostRewroteTheEdit() {
        XCTAssertEqual(
            InsertionProbe.evaluate(expected: "好", before: "你", after: "你号"),
            .diverged
        )
    }

    func testInsertionUnverifiableWithoutContext() {
        XCTAssertEqual(
            InsertionProbe.evaluate(expected: "好", before: nil, after: nil),
            .unverifiable
        )
        XCTAssertEqual(
            InsertionProbe.evaluate(expected: "好", before: "你", after: nil),
            .unverifiable
        )
        XCTAssertEqual(
            InsertionProbe.evaluate(expected: "", before: "你", after: "你"),
            .unverifiable
        )
    }

    // MARK: - Channel identity

    func testChannelIDIsStableForTheSameFieldShape() {
        XCTAssertEqual(Self.channel().id, Self.channel().id)
    }

    /// Every trait has to participate, otherwise two hosts that differ only in
    /// the ignored one are filed under a single channel and their bugs merge.
    func testChannelIDRespondsToEveryTrait() {
        let baseline = Self.channel().id
        var seen: Set<String> = [baseline]
        let variants = [
            Self.channel(keyboardType: "email"),
            Self.channel(returnKey: "send"),
            Self.channel(autocapitalisation: "words"),
            Self.channel(autocorrection: "no"),
            Self.channel(spellChecking: "no"),
            Self.channel(appearance: "dark"),
            Self.channel(documentLanguage: "en-US"),
            Self.channel(hasFullAccess: false),
            Self.channel(readsContextBefore: false),
            Self.channel(readsContextAfter: false),
        ]
        for variant in variants {
            XCTAssertTrue(seen.insert(variant.id).inserted, "collision on \(variant.fields)")
        }
    }

    func testChannelFieldsCarryTheIDSoEventsCanBeGrouped() {
        let channel = Self.channel()
        XCTAssertEqual(channel.fields["channel"], channel.id)
        XCTAssertTrue(channel.summary.contains(channel.id))
    }

    func testRestrictedChannelSummaryNamesTheRestriction() {
        XCTAssertTrue(Self.channel(hasFullAccess: false).summary.contains("restricted"))
        XCTAssertTrue(Self.channel(hasFullAccess: true).summary.contains("full access"))
    }

    // MARK: - Event storage

    /// Each process appends to its own file, so nothing guarantees arrival
    /// order matches event order. The reader is what has to impose it.
    func testEventsAreReadBackInTimestampOrder() throws {
        let store = DiagnosticStore(directory: try Self.scratchDirectory())
        let base = Date(timeIntervalSince1970: 1_000)
        store.append(Self.event(name: "second", at: base.addingTimeInterval(1)))
        store.append(Self.event(name: "first", at: base))
        store.append(Self.event(name: "third", at: base.addingTimeInterval(2)))
        XCTAssertEqual(store.allEvents().map(\.name), ["first", "second", "third"])
    }

    func testEventsSurviveEncodingWithTheirFields() throws {
        let store = DiagnosticStore(directory: try Self.scratchDirectory())
        store.append(Self.event(name: "state.changed", fields: ["from": "idle", "to": "ready"]))
        let stored = try XCTUnwrap(store.allEvents().first)
        XCTAssertEqual(stored.fields, ["from": "idle", "to": "ready"])
        XCTAssertEqual(stored.area, .bridge)
        XCTAssertEqual(stored.channel, "WeChat")
        // Sorted keys: a log that reorders its own fields cannot be diffed.
        XCTAssertEqual(stored.fieldSummary, "from=idle to=ready")
        XCTAssertTrue(stored.line.contains("[WeChat] state.changed"))
    }

    func testClearRemovesEverything() throws {
        let store = DiagnosticStore(directory: try Self.scratchDirectory())
        store.append(Self.event(name: "one"))
        XCTAssertFalse(store.allEvents().isEmpty)
        store.clear()
        XCTAssertTrue(store.allEvents().isEmpty)
    }

    /// The file is capped, and the survivors have to stay parseable: trimming
    /// mid-line would make the oldest remaining event silently disappear from
    /// every later read.
    func testTrimmingKeepsTheNewestEventsParseable() throws {
        let store = DiagnosticStore(directory: try Self.scratchDirectory())
        let base = Date(timeIntervalSince1970: 2_000)
        let total = 4_000
        for index in 0 ..< total {
            store.append(Self.event(
                name: "event\(index)",
                at: base.addingTimeInterval(Double(index)),
                fields: ["index": String(index), "padding": String(repeating: "x", count: 64)]
            ))
        }
        let events = store.allEvents()
        XCTAssertLessThan(events.count, total, "the file was never trimmed")
        XCTAssertGreaterThan(events.count, 0, "trimming destroyed the file")
        XCTAssertEqual(events.last?.name, "event\(total - 1)")
        // Contiguous from wherever the cut landed: no half-decoded gap.
        let indices = events.compactMap { $0.fields["index"].flatMap(Int.init) }
        XCTAssertEqual(indices.count, events.count)
        XCTAssertEqual(indices, Array(indices.first! ... indices.last!))
    }

    // MARK: - Fixtures

    private static func channel(
        keyboardType: String = "default",
        returnKey: String = "default",
        autocapitalisation: String = "sentences",
        autocorrection: String = "default",
        spellChecking: String = "default",
        appearance: String = "default",
        documentLanguage: String = "zh-Hans",
        hasFullAccess: Bool = true,
        readsContextBefore: Bool = true,
        readsContextAfter: Bool = true
    ) -> HostChannel {
        HostChannel(
            keyboardType: keyboardType,
            returnKey: returnKey,
            autocapitalisation: autocapitalisation,
            autocorrection: autocorrection,
            spellChecking: spellChecking,
            appearance: appearance,
            documentLanguage: documentLanguage,
            hasFullAccess: hasFullAccess,
            readsContextBefore: readsContextBefore,
            readsContextAfter: readsContextAfter
        )
    }

    private static func event(
        name: String,
        at timestamp: Date = Date(),
        fields: [String: String] = [:]
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            timestamp: timestamp,
            process: .keyboard,
            area: .bridge,
            level: .info,
            name: name,
            channel: "WeChat",
            fields: fields
        )
    }

    private static func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
