// PushQueuePayloadCoding+UserParameter.swift
//
// The `CodableUserParameter` envelope mirror, split out of
// `PushQueuePayloadCoding.swift` so the parent enum's body stays under
// SwiftLint's `type_body_length` cap. Same convention as the SetLog and
// Event mirrors living in the parent file — kept here only because the
// parent file is already near the line-count ceiling.

import Foundation
import CoreDomain

extension PushQueuePayloadCoding {

    /// Mirror of `CoreDomain.UserParameter` with `Codable`. Used to park
    /// a single user_parameter row in the push queue until the next flush
    /// tick routes it to `POST /api/user-parameters`.
    struct CodableUserParameter: Codable {
        let id: UUID
        let userID: UUID
        let key: String
        let value: String
        let updatedAt: Date
        let source: String

        init(_ param: UserParameter) {
            id = param.id
            userID = param.userID
            key = param.key
            value = param.value
            updatedAt = param.updatedAt
            source = param.source.rawValue
        }

        func toDomain() -> UserParameter {
            UserParameter(
                id: id,
                userID: userID,
                key: key,
                value: value,
                updatedAt: updatedAt,
                source: UserParameterSource(rawValue: source) ?? .appLog
            )
        }
    }
}
