# ElixirLsp

`ElixirLsp` is an Elixir-native, protocol-focused Language Server Protocol (LSP) toolkit.

It is use-case agnostic and focuses on robust protocol handling, transport, and ergonomic server building blocks.

## Features

- Typed JSON-RPC/LSP message structs (`Request`, `Notification`, `Response`, `ErrorResponse`)
- LSP framing and streaming decode (`Content-Length` aware)
- Production-safe stdio transport (`:content_length` mode by default)
- Router DSL (`use ElixirLsp.Router`) with request/notification/catch-all handlers
- Request lifecycle support: cancellation (`$/cancelRequest`) and timeouts
- Handler context helpers: `reply/2`, `error/4`, `notify/3`, `canceled?/1`
- State toolkit for open docs/workspace + text sync (`didOpen`/`didChange`/`didClose`)
- Strict/lenient lifecycle modes for out-of-order client events
- Capability builder DSL
- LSP helper types with coercion (`from_map`/`to_map`)
- Middleware pipeline + built-ins
- In-memory test harness
- OTP `child_spec/1` helpers

## Install

```elixir
{:elixir_lsp, "~> 0.1.0"}
```

## Quick start

```elixir
request = ElixirLsp.request(1, :initialize, %{"processId" => nil})
wire = request |> ElixirLsp.encode() |> IO.iodata_to_binary()
{:ok, [message], _state} = ElixirLsp.recv(wire)
```

## Router DSL

Route blocks expose `params`, `ctx`, `state`.
Aliases `_params`, `_ctx`, `_state` are also available when values are intentionally unused.

```elixir
defmodule MyHandler do
  use ElixirLsp.Router

  capabilities do
    hover true
    completion resolve_provider: false
  end

  on_request :initialize do
    ElixirLsp.HandlerContext.reply(ctx, %{
      "capabilities" => __MODULE__.server_capabilities()
    })
  end

  on_request :text_document_hover do
    {:reply, %{"contents" => "Hello"}, _state}
  end

  on_notification :text_document_did_open do
    {:ok, state}
  end
end
```

## Transport

Recommended production path:

```elixir
ElixirLsp.run_stdio(handler: MyHandler, init: %{})
```

Explicit modes:

```elixir
ElixirLsp.Transport.Stdio.run(handler: MyHandler, init: %{}, mode: :content_length)
ElixirLsp.Transport.Stdio.run(handler: MyHandler, init: %{}, mode: :chunk)
```

## State lifecycle mode

```elixir
lenient = ElixirLsp.State.new(mode: :lenient) # default
strict = ElixirLsp.State.new(mode: :strict)
```

- `:lenient`: ignores out-of-order events (for example `didChange` without `didOpen`)
- `:strict`: raises on lifecycle mismatches

## Typed map interop

```elixir
{:ok, action} = ElixirLsp.Types.from_map(ElixirLsp.Types.CodeAction, incoming_map)
outgoing_map = ElixirLsp.Types.to_map(action)
```

## Supervision

```elixir
children = [
  ElixirLsp.child_spec(
    name: MyServer,
    handler: MyHandler,
    handler_arg: %{},
    send: fn framed -> IO.binwrite(:stdio, framed) end
  )
]
```

## Test harness

```elixir
{:ok, harness} = ElixirLsp.TestHarness.start_link(handler: MyHandler)
:ok = ElixirLsp.TestHarness.request(harness, 1, :shutdown, %{})
outbound_messages = ElixirLsp.TestHarness.drain_outbound(harness)
```

## CI / Release automation

GitHub Actions are configured with two workflows:

- `CI` (`.github/workflows/ci.yml`): runs on every push to any branch
  - `mix test`
  - `mix docs`
  - `mix hex.build`
  - uploads built `*.tar` package as workflow artifact
- `Release to Hex` (`.github/workflows/release.yml`): runs when a GitHub release is published
  - runs test/docs/build
  - uploads built `*.tar` artifact
  - publishes to Hex with `HEX_API_KEY`

Required GitHub secret for release publishing:

- `HEX_API_KEY`
