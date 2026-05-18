# Next Release

Status: temporary release working doc. Remove this file after the next release
ships unless there are new release-specific steps to track.

Purpose: keep the next release's extra release work visible without changing the
normal deployment contract. The durable server deploy flow stays in
`docs/infrastructure/home-server.md`; this file exists only when the next release
has steps outside the norm.

## Standard Release Checklist

- Pick the release candidate commit or tag.
- Confirm the working tree contains only intended release changes.
- Run the required local gates for the release scope.
- Confirm independent review is complete for non-trivial changes.
- Push the release candidate to the remote branch/tag.
- Deploy the server with the normal home-server flow:
  `make deploy HOST=robie-imac TAG=<tag>`.
- Confirm the deploy-created SQLite backup exists under
  `/opt/workoutdb/shared/backups/`.
- Confirm the server health check passes.
- Install the matching app build on the phone.
- Run the release smoke test that matches the changed behavior.
- Record any release bugs in the owning docs or bug tracker.
- Remove or rewrite this file after release.

## Custom Steps For This Release

### Primitive Contract Cutover

This release is a one-time destructive cutover from the legacy timing/workout
tree to the primitive Block > Set > Slot contract.

Release gates:

- Primitive trunk gaps selected for this release are closed or explicitly ruled
  out of the cutover.
- `make pre-qa` passes on the release candidate.
- Server and app schema versions match the primitive contract.
- Old timing-mode authoring/result payloads are rejected at write boundaries.
- App can pull, execute, persist, and push a primitive workout against a real
  local HTTP server.
- UI QA covers the release-critical phone flow: first pull, Today entry, active
  execution, rest/transition behavior, save-and-done, and History/readback
  surfaces affected by primitives.

Destructive data decision:

- This release resets existing server workout execution data.
- Preserve the remote SQLite backup before the reset migration runs.
- Use app reset/reinstall as the local-data rollback route.
- Do not build a V6 primitive result preservation migration unless this decision
  changes before release.

Server cutover:

1. Confirm the target commit or tag.
2. Run `make deploy HOST=robie-imac TAG=<tag>`.
3. Confirm the deploy-created SQLite backup exists.
4. Confirm the service health check passes.
5. Confirm the primitive reset migration applied.
6. Confirm old workout-tree rows are absent and catalog/profile/config rows still
   exist.

App cutover:

1. Install the matching app build on the phone.
2. If local state is incompatible or stale, reset/reinstall the app rather than
   preserving old workout/result data.
3. Connect to the server with the current URL/token.
4. Confirm first pull succeeds and the local store is on the current SwiftData
   schema.

Re-seed and smoke:

1. Push one real primitive workout through the server API.
2. Pull it on the phone.
3. Execute a short representative session.
4. Save and done.
5. Confirm primitive set logs and workout completion are visible from the server
   readback path.
6. Confirm the app shows the completed result in the intended History/review
   surface.

Rollback limits:

- Server rollback can flip back to the previous release and restore the
  pre-cutover SQLite backup.
- App rollback is not clean once the phone has opened/migrated/reset local data;
  treat it as reinstall/reset plus reconnect.
- Do not rely on mixed old-app/new-server or new-app/old-server operation.
