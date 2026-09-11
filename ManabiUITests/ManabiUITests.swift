import XCTest

@MainActor
final class ManabiUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRealPracticeAndResume() async throws {
        let app = XCUIApplication()
        app.launchEnvironment["MANABI_UI_TESTING"] = "1"
        app.launch()
        try await loginIfNeeded(app)
        let category = app.buttons["category_vocabulary"]
        XCTAssertTrue(category.waitForExistence(timeout: 30))
        let ready = NSPredicate(format: "enabled == true")
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: ready, object: category)], timeout: 30)
        category.tap()
        let type = app.buttons["type_kanji_reading"]
        XCTAssertTrue(type.waitForExistence(timeout: 10))
        type.tap()
        app.segmentedControls["questionCount"].buttons["5 题"].tap()
        if !app.buttons["startPractice"].isHittable { app.swipeUp() }
        app.buttons["startPractice"].tap()
        let option = app.descendants(matching: .any).matching(identifier: "option_0").firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 20))
        option.tap()
        app.buttons["answerAction"].tap()
        let next = app.buttons["answerAction"]
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "下一题"), object: next)], timeout: 20)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Manabi-answer-feedback"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["exitPractice"].tap()
        assertCenteredAlert(in: app, title: "退出本次练习？")
        attach(app, name: "Manabi-practice-exit-alert")
        app.alerts.buttons.matching(identifier: "cancelPracticeExit").firstMatch.tap()
        XCTAssertTrue(app.buttons["answerAction"].exists)
        app.buttons["exitPractice"].tap()
        app.alerts.buttons.matching(identifier: "confirmPracticeExit").firstMatch.tap()
        XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        let resume = app.buttons["continuePractice"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30))
        resume.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "option_0").firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["2 / 5"].exists)
        for number in 2...5 {
            let choice = app.descendants(matching: .any).matching(identifier: "option_0").firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 10))
            if !choice.isHittable { app.swipeUp() }
            choice.tap()
            app.buttons["answerAction"].tap()
            let expected = number == 5 ? "查看练习结果" : "下一题"
            await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: app.buttons["answerAction"])], timeout: 15)
            app.buttons["answerAction"].tap()
        }
        XCTAssertTrue(app.staticTexts["又积累了一点。"].waitForExistence(timeout: 10))
        attach(app, name: "Manabi-result")
        app.buttons["finishPractice"].tap()
    }

    func testReadingMaterialAndListeningPlayback() async throws {
        let app = XCUIApplication()
        app.launchEnvironment["MANABI_UI_TESTING"] = "1"
        app.launch()
        try await loginIfNeeded(app)
        openCategory("reading", in: app)
        app.buttons["type_short_reading"].tap()
        start(in: app)
        let material = app.descendants(matching: .any).matching(identifier: "readingMaterial").firstMatch
        XCTAssertTrue(material.waitForExistence(timeout: 20))
        attach(app, name: "Manabi-reading")
        app.terminate()
        app.launch()
        openCategory("listening", in: app)
        app.buttons["type_listening_task"].tap()
        start(in: app)
        let play = app.buttons["audioPlay"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        play.tap()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "暂停音频"), object: play)], timeout: 20)
        attach(app, name: "Manabi-listening")
        play.tap()
    }

    func testLoginRequiredAndLogout() async throws {
        let app = XCUIApplication()
        app.launchEnvironment["MANABI_UI_TESTING"] = "1"
        app.launch()
        try await loginIfNeeded(app)
        app.tabBars.buttons["我的"].tap()
        let logout = app.buttons["退出登录"]
        if !logout.isHittable { app.swipeUp() }
        logout.tap()
        assertCenteredAlert(in: app, title: "退出当前账号？")
        let confirm = app.alerts.buttons.matching(identifier: "confirmLogout").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.textFields["username"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.buttons["练习"].exists)
        XCTAssertFalse(app.buttons["开始新的游客练习"].exists)
        XCTAssertFalse(app.buttons["创建账号"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["username"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.buttons["练习"].exists)
        try await loginIfNeeded(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["category_vocabulary"].waitForExistence(timeout: 30))
    }

    private func assertCenteredAlert(in app: XCUIApplication, title: String) {
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(alert.frame.midX, app.frame.midX, accuracy: app.frame.width * 0.10)
        XCTAssertEqual(alert.frame.midY, app.frame.midY, accuracy: app.frame.height * 0.15)
    }

    private func loginIfNeeded(_ app: XCUIApplication) async throws {
        dismissPasswordPrompt(app)
        if app.buttons["category_vocabulary"].waitForExistence(timeout: 5) { return }
        XCTAssertTrue(app.textFields["username"].waitForExistence(timeout: 20))
        let username = "uitest_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let password = UUID().uuidString
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8001/api/v1/auth/register")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 201)
        app.textFields["username"].tap()
        app.textFields["username"].typeText(username)
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText(password)
        app.swipeUp()
        app.buttons["登录"].tap()
        dismissPasswordPrompt(app)
        XCTAssertTrue(app.buttons["category_vocabulary"].waitForExistence(timeout: 30))
    }

    private func dismissPasswordPrompt(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
    }

    private func openCategory(_ name: String, in app: XCUIApplication) {
        let element = app.buttons["category_\(name)"]
        XCTAssertTrue(element.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
        waitForExpectations(timeout: 30)
        if !element.isHittable { app.swipeUp() }
        element.tap()
    }

    private func start(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
        if !app.buttons["startPractice"].isHittable { app.swipeUp() }
        app.buttons["startPractice"].tap()
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
