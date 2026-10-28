import Foundation

/// A byte-for-byte port of the web app's `csvRows()` (`index.html:496`).
///
/// It is not a general RFC 4180 parser and is not meant to be: quoted fields,
/// doubled quotes, embedded commas and embedded newlines behave exactly as the
/// web app's own reader behaves, so a delivery file that parses in the browser
/// parses here and produces the same fields.
enum CSVRows {

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false

        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r" {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                field = ""
                if row.count > 1 || !row[0].isEmpty {
                    rows.append(row)
                }
                row = []
            } else {
                field.append(character)
            }

            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}
