## Summary

This PR adds a system event when the advisories ingestion run completes but finds no advisories for a given gem/version. It also adds a unit test that verifies this behavior.

### Changes
- Log `SystemEvent` of kind `advisory_ingest` and status `ok` when no advisories are found for a bundled gem entry.
- Add spec `spec/services/evaluation/bundled_gems_vulnerability_evaluator_spec.rb` to assert the event is created and contains expected payload.

### Why
Admins previously could not see evidence in `System Events` when advisory ingestion ran and returned zero results. This event makes the run visible in the admin UI without changing error semantics.

### Tests
The new RSpec test covers the empty-advisory case and asserts the `SystemEvent` fields.

### Follow-ups
- Optionally group or aggregate "no advisories found" events to reduce noise.
- Add admin UI filters or badges for these events if desired.
