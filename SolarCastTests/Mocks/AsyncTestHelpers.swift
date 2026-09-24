import XCTest

/// Async-safe replacement for XCTAssertThrowsError.
/// Usage: await assertThrowsError(try await someAsyncFunc()) { error in ... }
func assertThrowsError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    errorHandler: ((Error) -> Void)? = nil
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error but none was thrown. \(message)", file: file, line: line)
    } catch {
        errorHandler?(error)
    }
}

/// Asserts an async expression does NOT throw.
func assertNoThrow<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
    } catch {
        XCTFail("Unexpected error thrown: \(error). \(message)", file: file, line: line)
    }
}
