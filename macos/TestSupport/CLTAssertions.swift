// Minimal adapter for the assertions used by CoreTests.swift on CLT-only Macs.
// Full Xcode and Linux continue to use the real XCTest framework.
import Foundation

class XCTestCase {}
private var failures = 0
private var tests = 0

private func check(_ condition: Bool, _ message: String, file: StaticString, line: UInt) {
    if !condition {
        failures += 1
        print("\(file):\(line): failure: \(message)")
    }
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    check(actual == expected, "\(actual) != \(expected)", file: file, line: line)
}
func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    check(abs(actual - expected) <= accuracy, "\(actual) != \(expected) +/- \(accuracy)", file: file, line: line)
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(value, "Expected true", file: file, line: line)
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    check(!value, "Expected false", file: file, line: line)
}
func XCTAssertGreaterThanOrEqual<T: Comparable>(_ actual: T, _ limit: T, file: StaticString = #filePath, line: UInt = #line) {
    check(actual >= limit, "\(actual) < \(limit)", file: file, line: line)
}
func XCTAssertLessThanOrEqual<T: Comparable>(_ actual: T, _ limit: T, file: StaticString = #filePath, line: UInt = #line) {
    check(actual <= limit, "\(actual) > \(limit)", file: file, line: line)
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
        check(false, "Expected a thrown error", file: file, line: line)
    } catch {}
}
func runTest(_ name: String, _ body: () throws -> Void) {
    tests += 1
    let before = failures
    do { try body() } catch { failures += 1; print("\(name): unexpected error: \(error)") }
    print("\(failures == before ? "PASS" : "FAIL") \(name)")
}
func finishTests() {
    print("CLT core tests: \(tests) tests, \(failures) failures")
    exit(failures == 0 ? 0 : 1)
}
