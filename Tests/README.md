# Test layout

See [`docs/testing.md`](../docs/testing.md) for the pyramid, merge gate, manual matrix, and provisioned runner.

| Directory | Tier |
|-----------|------|
| `DomainTests`, `ConfigTests`, `SafetyTests`, `ObservabilityTests` | Pure logic |
| `EngineTests` | State machine + SimulationExecutor components + recovery |
| `AdapterTests` | Adapter selection + mutation-guard |
| `AppTests` | View-model logic |
| `AppControlTests`, `PermissionsTests`, `AccessibilityTests`, `InputSynthesisTests` | Pure / injectable platform logic (no live TCC in CI) |
| `UITests` | Optional XCUITest — **not** in `scripts/ci.sh` merge gate |
