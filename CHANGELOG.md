# Changelog

## 0.2.1 - 2026-02-08

- Added `use ElixirLsp.Server` defaults to reduce custom handler boilerplate.
- Added `defrequest/2` and `defnotification/2` routing macros with pattern-friendly matching.
- Added cooperative cancellation helpers: `with_cancel/2` and `check_cancel!/1`.
- Added first-class `Phoenix.PubSub` integration for diagnostics, progress, and custom event fanout.
- Added `NimbleOptions` validation for server, transport, and harness runtime options.
- Added `Inspect` and `String.Chars` implementations for core LSP structs.
- Added `Enumerable`/`Collectable`-friendly stream pipeline helpers.
- Added richer telemetry around request lifecycle and middleware execution (`start/stop/exception`).
- Added `mix lsp.gen.handler` task for idiomatic handler/test scaffolding.
- Added typed LSP type generation with compile-time required/optional field validation.
- Added Elixir-native response builders for common LSP payloads.
- Added automatic outbound key normalization to LSP wire-format camelCase string keys.

## 0.1.0 - 2026-02-08

- Initial public release.
- Core LSP framing and JSON-RPC message model.
- Native method registry and typed message structs.
- Protocol server with cancellation, timeout, and middleware support.
- Router DSL and capability builder.
- Production-safe stdio transport (`:content_length` default).
- State toolkit for document/workspace lifecycle.
- LSP helper types with map coercion helpers.
- In-memory test harness and OTP child spec helpers.
