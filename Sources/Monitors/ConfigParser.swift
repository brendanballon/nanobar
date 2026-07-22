import Foundation

/// Parses flat `key = value` config text into a dictionary.
///
/// - Blank lines and lines starting with `#` are skipped.
/// - Everything before the first `=` is the key, the rest the value (both trimmed).
/// - A trailing comment (whitespace followed by `#`) is stripped from the value —
///   but a value *starting* with `#` (hex colors) is kept intact.
public enum ConfigParser {
    public static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = stripTrailingComment(
                String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            )
            guard !key.isEmpty, !value.isEmpty else { continue }
            values[key] = value
        }
        return values
    }

    private static func stripTrailingComment(_ value: String) -> String {
        var previous: Character = " "
        for index in value.indices {
            let char = value[index]
            // `#` at position 0 (hex color) is part of the value; a `#` preceded
            // by whitespace anywhere later starts a comment.
            if char == "#", index != value.startIndex, previous.isWhitespace {
                return String(value[..<index]).trimmingCharacters(in: .whitespaces)
            }
            previous = char
        }
        return value
    }
}
