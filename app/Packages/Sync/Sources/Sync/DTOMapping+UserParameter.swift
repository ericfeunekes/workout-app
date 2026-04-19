// DTOMapping+UserParameter.swift
//
// UserParameter wire mapping.
//
// Pull: `user_parameters` is append-only on the server; the pull returns
// every row and the cache upserts by PK, so the decode is strictly a
// validate-and-shape step.
//
// Push: the app posts `POST /api/user-parameters` with the subset shape
// `UserParameterIn` — `{id, key, value, source, updated_at?}`. The client
// owns the id end-to-end (same pattern as `SetLog`): a deterministic UUID
// derived from `(userID, key, observedAt)` keeps the push idempotent so a
// replay after a crash-between-commit-and-queue-remove upserts in place
// rather than inserting a second row. The server resolves `user_id` from
// the bearer token, so the local `userID` never rides the wire.
// See `server/workoutdb_server/api/user_parameters.py` for the server-
// side upsert contract.

import Foundation
import CoreDomain
import WorkoutCoreFoundation
import WorkoutDBSchema

/// Wire shape for `POST /api/user-parameters`. Matches the server's
/// `UserParameterIn` Pydantic model exactly (snake_case keys). Kept
/// inline — there is no generated Swift DTO for the POST-in shape
/// because the schema package only models the pull/read entities.
struct UserParameterInDTO: Encodable {
    let id: String
    let key: String
    let value: String
    let source: String
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case value
        case source
        case updatedAt = "updated_at"
    }
}

extension DTOMapping {

    public static func mapUserParameter(
        _ dto: WorkoutDBSchema.UserParameter
    ) -> Result<CoreDomain.UserParameter, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("UserParameter.id is not a UUID: \(dto.id)"))
        }
        guard let userID = UUID(uuidString: dto.userId) else {
            return .failure(.decode("UserParameter.user_id is not a UUID: \(dto.userId)"))
        }
        guard let source = CoreDomain.UserParameterSource(rawValue: dto.source.rawValue) else {
            return .failure(.decode("UserParameter.source unknown: \(dto.source.rawValue)"))
        }
        return .success(CoreDomain.UserParameter(
            id: id,
            userID: userID,
            key: dto.key,
            value: dto.value,
            updatedAt: dto.updatedAt,
            source: source
        ))
    }

    /// Map a Domain `UserParameter` to the push wire shape.
    static func toInDTO(_ param: CoreDomain.UserParameter) -> UserParameterInDTO {
        UserParameterInDTO(
            id: param.id.wireID,
            key: param.key,
            value: param.value,
            source: param.source.rawValue,
            updatedAt: param.updatedAt
        )
    }
}
