import XCTest
@testable import VibeVoiceOSS

final class RoleProfileTests: XCTestCase {
    func testDefaultProfilesCoverEngineeringAndForeignTrade() {
        let profiles = RoleProfile.defaultProfiles
        XCTAssertEqual(profiles.map(\.id), ["preset-software-engineer", "preset-foreign-trade"])
        let engineer = try? XCTUnwrap(profiles.first { $0.id == "preset-software-engineer" })
        XCTAssertTrue(engineer?.contextPrompt.contains("API") == true)
        XCTAssertTrue(engineer?.contextPrompt.contains("不得凭专业常识虚构") == true)

        let trade = try? XCTUnwrap(profiles.first { $0.id == "preset-foreign-trade" })
        XCTAssertTrue(trade?.contextPrompt.contains("Incoterms") == true)
        XCTAssertTrue(trade?.contextPrompt.contains("不得擅自承诺价格") == true)
    }

    func testResolverAcceptsOnlyCandidateID() throws {
        let candidates = RoleProfile.defaultProfiles
        let resolution = try RoleResolver.parse(
            #"{"role_id":"preset-foreign-trade","reason":"报价和交期沟通"}"#,
            candidates: candidates
        )
        XCTAssertEqual(resolution.roleID, "preset-foreign-trade")
        XCTAssertEqual(resolution.reason, "报价和交期沟通")
        XCTAssertThrowsError(try RoleResolver.parse(
            #"{"role_id":"invented-role"}"#, candidates: candidates
        ))
    }

    func testResolverPromptIsStrictAndContainsCandidateCards() {
        let messages = RoleResolver.messages(text: "客户问 FOB 报价", candidates: RoleProfile.defaultProfiles)
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertTrue(messages.first?["content"]?.contains("只输出 JSON") == true)
        XCTAssertTrue(messages.first?["content"]?.contains("preset-software-engineer") == true)
        XCTAssertTrue(messages.first?["content"]?.contains("preset-foreign-trade") == true)
    }

    func testRoleContextIsAppendedAfterCustomPrompt() {
        let role = RoleProfile.softwareEngineer
        let messages = SemanticFormatter.formattingMessages(
            transcript: "把 API 的 timeout 改一下",
            mode: .clean,
            customSystemPrompt: "用短句输出",
            roleContextPrompt: role.contextPrompt
        )
        let system = messages.first?["content"] ?? ""
        XCTAssertTrue(system.contains("用短句输出"))
        XCTAssertTrue(system.contains("当前专业角色背景"))
        XCTAssertLessThan(system.range(of: "用短句输出")!.lowerBound, system.range(of: "当前专业角色背景")!.lowerBound)
    }
}
