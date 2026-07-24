import Testing

/// The cross-suite serialization domain for every suite that takes
/// `PersistenceOperationGate` — folder sync, backup restore, migration, and the
/// expiry sweep. The gate is process-global (exactly one instance matters in
/// the real app), so two such suites running in parallel contend spuriously:
/// one suite's in-flight sync makes another suite's `syncNow` throw
/// `.operationInProgress`, or its `sweepExpired` silently return 0.
/// `@Suite(.serialized)` on each individual suite only orders tests *within*
/// that suite; the `.serialized` trait here is recursive, so every suite
/// nested under this umbrella runs one test at a time relative to all the
/// others, while unrelated suites keep running in parallel.
@Suite(.serialized)
enum PersistenceGateSuites {}
