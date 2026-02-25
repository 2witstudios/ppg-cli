import XCTest
@testable import PPG_CLI

final class ShellUtilsTests: XCTestCase {

    // MARK: - shellEscape

    func testShellEscapeSimpleString() {
        XCTAssertEqual(shellEscape("hello"), "'hello'")
    }

    func testShellEscapeWithSingleQuotes() {
        XCTAssertEqual(shellEscape("it's"), "'it'\\''s'")
    }

    // MARK: - shellProfileScript

    func testZshProfileScript() {
        let script = shellProfileScript(for: "/bin/zsh")
        XCTAssertTrue(script.contains(".zprofile"), "zsh script should source .zprofile")
        XCTAssertTrue(script.contains(".zshrc"), "zsh script should source .zshrc")
        XCTAssertTrue(script.contains("path_helper"), "zsh script should invoke path_helper")
    }

    func testBashProfileScript() {
        let script = shellProfileScript(for: "/bin/bash")
        XCTAssertTrue(script.contains(".bash_profile"), "bash script should source .bash_profile")
        XCTAssertTrue(script.contains(".bashrc"), "bash script should source .bashrc")
        XCTAssertTrue(script.contains("path_helper"), "bash script should invoke path_helper")
    }

    func testFishProfileScriptIsEmpty() {
        let script = shellProfileScript(for: "/usr/local/bin/fish")
        XCTAssertEqual(script, "", "fish should return empty — it auto-sources config")
    }

    func testUnknownShellReturnsEmpty() {
        let script = shellProfileScript(for: "/bin/tcsh")
        XCTAssertEqual(script, "", "unknown shells should return empty to avoid wrong sourcing")
    }

    func testShellPathExtractsBasename() {
        let script = shellProfileScript(for: "/usr/local/bin/zsh")
        XCTAssertTrue(script.contains(".zshrc"), "should match on basename, not full path")
    }
}
