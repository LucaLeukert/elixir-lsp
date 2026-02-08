# ElixirLsp

`ElixirLsp` is an Elixir-native, protocol-focused Language Server Protocol (LSP) toolkit.

It is use-case agnostic and focuses on robust protocol handling, transport, and ergonomic server building blocks.

## Features

- Typed JSON-RPC/LSP message structs (`Request`, `Notification`, `Response`, `ErrorResponse`)
- LSP framing and streaming decode (`Content-Length` aware)
- Production-safe stdio transport (`:content_length` mode by default)
- Handler DSL (`use ElixirLsp.Server`) with `defrequest/2` and `defnotification/2`
- Router DSL (`use ElixirLsp.Router`) with request/notification/catch-all handlers
- Request lifecycle support: cancellation (`$/cancelRequest`), timeouts, and telemetry spans
- Cooperative cancellation helpers: `with_cancel/2` and `check_cancel!/1`
- Handler context helpers: `reply/2`, `error/4`, `notify/3`, `canceled?/1`, `with_cancel/2`, `check_cancel!/1`
- State toolkit for open docs/workspace + text sync (`didOpen`/`didChange`/`didClose`)
- Strict/lenient lifecycle modes for out-of-order client events
- Capability builder DSL
- LSP helper types with coercion (`from_map`/`to_map`)
- Typed type generation macro (`ElixirLsp.Types.deflsp_type/2`)
- Elixir-native response builders (`ElixirLsp.Responses`)
- Automatic outbound key normalization (`snake_case` to wire `camelCase`)
- Middleware pipeline + built-ins
- `Enumerable`/`Collectable` stream pipeline helpers
- First-class `Phoenix.PubSub` fanout for diagnostics/progress/events
- In-memory test harness
- Option validation with `NimbleOptions`
- `Inspect`/`String.Chars` implementations for core structs
- `mix lsp.gen.handler` scaffold task
- OTP `child_spec/1` helpers

## Install

```elixir
{:elixir_lsp, "~> 0.2.0"}
```

## Quick start

```elixir
request = ElixirLsp.request(1, :initialize, %{"processId" => nil})
wire = request |> ElixirLsp.encode() |> IO.iodata_to_binary()
{:ok, [message], _state} = ElixirLsp.recv(wire)
```

## Handler DSL

```elixir
defmodule MyHandler do
  use ElixirLsp.Server

  defrequest :initialize do
    with_cancel(ctx, fn ->
      ElixirLsp.HandlerContext.reply(
        ctx,
        ElixirLsp.Responses.initialize(%{hover_provider: true}, name: "my-lsp", version: "0.2.0")
      )
    end)
  end

  defnotification {:text_document_did_open, %{"textDocument" => doc}} do
    check_cancel!(ctx)
    {:ok, Map.put(state, :last_opened_uri, doc["uri"])}
  end
end
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

## PubSub fanout

```elixir
{:ok, _} = ElixirLsp.PubSub.start_link(name: ElixirLsp.PubSub)
:ok = ElixirLsp.PubSub.subscribe(ElixirLsp.PubSub, "elixir_lsp:diagnostics")

{:ok, _server} =
  ElixirLsp.Server.start_link(
    handler: MyHandler,
    pubsub: [name: ElixirLsp.PubSub, topic_prefix: "elixir_lsp"],
    send: fn framed -> IO.binwrite(:stdio, framed) end
  )
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

Type generation:

```elixir
defmodule MyTypes do
  require ElixirLsp.Types
  ElixirLsp.Types.deflsp_type PublishDiagnostics, required: [:uri], optional: [:version, :diagnostics]
end
```

## Stream pipeline

```elixir
stream =
  ElixirLsp.decode_chunks(chunks)

messages = Enum.to_list(ElixirLsp.pipeline_messages(stream))
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

## Scaffolding

```bash
mix lsp.gen.handler Hover
```
