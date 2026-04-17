// JSON coder factories pre-configured to match the server's wire format.
//
// Use these when talking to the WorkoutDB API. They set:
//   • ISO-8601 date handling (matches Pydantic's default datetime serialization;
//     accepts both with and without fractional seconds).
//   • No key-case auto-conversion — CodingKeys on each DTO make snake_case explicit.

import Foundation

extension JSONDecoder {
    public static func workoutDB() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            // Try fractional seconds first, then fall back to plain. Both must be
            // constructed per-call because ISO8601DateFormatter isn't Sendable.
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: string) {
                return date
            }

            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable date: \(string)"
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    public static func workoutDB() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
