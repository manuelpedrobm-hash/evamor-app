import XCTest

final class DhammaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeConfigurationAndMeditationFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-grantOldStudentAccess", "-resetOnboarding", "-resetUITestSession"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Tu práctica, primero"].waitForExistence(timeout: 5))
        app.buttons["onboardingNext"].tap()
        XCTAssertTrue(app.staticTexts["Privacidad clara"].waitForExistence(timeout: 3))
        app.buttons["onboardingNext"].tap()
        XCTAssertTrue(app.staticTexts["Amigos, si quieres"].waitForExistence(timeout: 3))
        app.buttons["onboardingStart"].tap()

        XCTAssertTrue(app.staticTexts["Un momento de quietud"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Ecuanimidad"].exists)

        for (minutes, label) in [(5, "5 minutos"), (15, "15 minutos"), (30, "30 minutos"), (60, "1 hora"), (5, "5 minutos")] {
            app.buttons["quickDuration\(minutes)"].tap()
            XCTAssertEqual(app.staticTexts["selectedDuration"].label, label)
            XCTAssertEqual(app.buttons["quickDuration\(minutes)"].value as? String, "Seleccionado")
        }
        app.terminate()
        app.launchArguments = ["-grantOldStudentAccess", "-resetUITestSession"]
        app.launch()
        XCTAssertTrue(app.staticTexts["selectedDuration"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["selectedDuration"].label, "5 minutos")
        app.buttons["configureSessionButton"].tap()
        XCTAssertTrue(app.switches["Metta extendido"].waitForExistence(timeout: 3))
        for title in ["Introducción", "Metta extendido"] {
            let toggle = app.switches[title]
            if toggle.value as? String == "0" {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertEqual(toggle.value as? String, "1", app.debugDescription)
        }
        if !app.switches["Crear timelapse"].exists { app.swipeUp() }
        XCTAssertTrue(app.switches["Crear timelapse"].waitForExistence(timeout: 3))
        if app.switches["Crear timelapse"].value as? String == "1" { app.switches["Crear timelapse"].tap() }
        app.buttons["Guardar"].tap()
        app.buttons["quickDuration15"].tap()
        app.buttons["quickDuration5"].tap()
        XCTAssertTrue(app.staticTexts["+ 1 min 13 s de metta al final"].exists)

        app.buttons["meditateButton"].tap()
        XCTAssertTrue(app.buttons["Pausar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Introducción"].exists)
        app.buttons["Pausar"].tap()
        XCTAssertTrue(app.buttons["Reanudar"].waitForExistence(timeout: 3))
        app.buttons["Reanudar"].tap()
        XCTAssertTrue(app.buttons["Pausar"].waitForExistence(timeout: 3))
        app.buttons["Terminar antes"].tap()
        XCTAssertTrue(app.buttons["Guardar práctica parcial"].waitForExistence(timeout: 3))
        app.buttons["Guardar práctica parcial"].tap()
        XCTAssertTrue(app.staticTexts["Práctica guardada"].waitForExistence(timeout: 5))
    }

    func testOldStudentGateRejectsAndAcceptsCredentials() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetOldStudentAccess", "-resetOnboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Acceso para antiguos alumnos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recordar acceso en este iPhone"].exists)
        app.textFields["oldStudentUsername"].tap()
        app.textFields["oldStudentUsername"].typeText("oldstudent")
        app.secureTextFields["oldStudentPassword"].tap()
        app.secureTextFields["oldStudentPassword"].typeText("incorrecta")
        app.buttons["oldStudentLogin"].tap()
        XCTAssertTrue(app.staticTexts["Usuario o contraseña incorrectos."].waitForExistence(timeout: 3))

        app.secureTextFields["oldStudentPassword"].tap()
        app.secureTextFields["oldStudentPassword"].typeText("behappy")
        app.buttons["oldStudentLogin"].tap()
        XCTAssertTrue(app.staticTexts["Tu práctica, primero"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-resetOnboarding"]
        app.launch()
        XCTAssertFalse(app.staticTexts["Acceso para antiguos alumnos"].exists)
        XCTAssertTrue(app.staticTexts["Tu práctica, primero"].waitForExistence(timeout: 5))
    }
}
