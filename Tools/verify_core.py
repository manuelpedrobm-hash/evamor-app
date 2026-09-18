#!/usr/bin/env python3
"""Runs the same core scenarios without XCTest when only Command Line Tools exist."""
import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
test = (root / "Tests/CoreTests/SessionTests.swift").read_text()
methods = re.findall(r"func (test\w+)\(", test)
support = '''
import Foundation
class XCTestCase {}
var checks = 0
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    checks += 1; precondition(a == b, "Expected \\(a) == \\(b)", file: file, line: line)
}
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    checks += 1; precondition(abs(a - b) <= accuracy, "Expected \\(a) ≈ \\(b)", file: file, line: line)
}
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    checks += 1; precondition(a != b, file: file, line: line)
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    checks += 1; precondition(value, file: file, line: line)
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    checks += 1; precondition(!value, file: file, line: line)
}
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    checks += 1; precondition(a <= b, "Expected \(a) <= \(b)", file: file, line: line)
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    checks += 1; precondition(value == nil, file: file, line: line)
}
'''
with tempfile.TemporaryDirectory(prefix="meditation-core-") as temporary:
    folder = pathlib.Path(temporary)
    source = support + test.replace("import XCTest", "").replace("@testable import MeditationCore", "")
    source += "\nlet suite = SessionTests()\n"
    for method in methods:
        signature = re.search(r"func " + method + r"\(\)([^\{]*)", test).group(1)
        source += ('try ' if 'throws' in signature else '') + 'suite.' + method + '()\nprint("PASS ' + method + '")\n'
    source += 'print("Passed \\(checks) assertions")\n'
    (folder / "main.swift").write_text(source)
    subprocess.run(["swiftc", "-module-cache-path", str(folder / "cache"),
                    str(root / "Core/Session.swift"), str(folder / "main.swift"),
                    "-o", str(folder / "verify")], check=True)
    subprocess.run([str(folder / "verify")], check=True)
