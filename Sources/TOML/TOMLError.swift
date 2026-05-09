// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// Errors thrown by ``TOML/parse(_:)``.
public enum TOMLError: Error, Equatable, Sendable {
    /// Lexer or parser hit a character it didn't expect at this position.
    case unexpectedCharacter(Character, line: Int, column: Int)

    /// A string literal opened but never closed before EOF.
    case unterminatedString(line: Int)

    /// Backslash escape sequence inside a basic string was malformed.
    case invalidEscape(String, line: Int)

    /// Numeric literal could not be parsed as integer or float.
    case invalidNumber(String, line: Int)

    /// Bare-key syntax violated (empty key, illegal characters, etc.).
    case invalidKey(line: Int)

    /// Same key declared twice in the same table.
    case duplicateKey(String, line: Int)

    /// Table header malformed (e.g. unclosed bracket, empty path).
    case invalidTable(String, line: Int)

    /// Value position contained input the parser couldn't classify.
    case invalidValue(line: Int)

    /// Reached end of input while expecting more.
    case unexpectedEOF
}
