import XCTest
@testable import OutreachCore

final class RoleTemplateTests: XCTestCase {
    func testEmployerEmailDomainAllowedButHostedBoardRejected() throws {
        XCTAssertEqual(try OutreachValidation.normalizeCompanyDomain("greenhouse.io"), "greenhouse.io")
        XCTAssertThrowsError(try OutreachValidation.normalizeCompanyDomain("boards.greenhouse.io"))
        XCTAssertThrowsError(try OutreachValidation.normalizeCompanyDomain("job-boards.greenhouse.io"))
    }
    func testSwitchingRolesPreservesEditsAndRoundTrips() throws {
        var settings = OutreachSettings()
        settings.bodyTemplate = "My general message"
        settings.selectTemplate("software")
        XCTAssertTrue(settings.bodyTemplate.contains("reliable software"))
        settings.bodyTemplate = "My software experience"
        settings.selectTemplate("support")
        XCTAssertTrue(settings.bodyTemplate.contains("troubleshooting"))
        settings.selectTemplate("software")
        XCTAssertEqual(settings.bodyTemplate, "My software experience")
        settings.selectTemplate("general")
        XCTAssertEqual(settings.bodyTemplate, "My general message")
        let decoded = try JSONDecoder().decode(OutreachSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }
    func testOldSettingsDecodeWithoutNewFieldsAndStartersValidate() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(OutreachSettings())) as? [String: Any])
        for key in ["autoConfirmCompany", "selectedTemplate", "roleTemplates"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(OutreachSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.autoConfirmCompany)
        for role in RoleTemplate.roles {
            var value = decoded
            value.selectTemplate(role)
            try OutreachValidation.validate(settings: value)
        }
    }
}
