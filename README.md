# ElixirLsp

`ElixirLsp` is a protocol-focused, use-case agnostic LSP library for Elixir.

It provides:

- Native typed LSP/JSON-RPC messages
- Framing + stream decode for stdio/socket chunks
- `ElixirLsp.Transport.Stdio` ready-to-run stdio loop
- Router DSL (`use ElixirLsp.Router`) with request/notification handlers
- Request lifecycle features: cancellation (`$/cancelRequest`) and timeouts
- Handler context helpers (`reply`, `error`, `notify`, `canceled?`)
- State toolkit (`ElixirLsp.State`) for text sync/document tracking
- Capability DSL (`capabilities do ... end`)
- LSP helper structs (`Range`, `Diagnostic`, `TextEdit`, `WorkspaceEdit`, `CodeAction`)
- Middleware pipeline and built-in middlewares
- In-memory test harness (`ElixirLsp.TestHarness`)
- OTP embedding via `ElixirLsp.child_spec/1`

## Install

```elixir
{:elixir_lsp, path: "/Users/lucaleukert/src/elixir-lsp"}
```

## Native API

```elixir
request = ElixirLsp.request(1, :initialize, %{"processId" => nil})
wire = request |> ElixirLsp.encode() |> IO.iodata_to_binary()
{:ok, [message], state} = ElixirLsp.recv(wire)
```

## Router DSL

```elixir
defmodule MyHandler do
  use ElixirLsp.Router

  capabilities do
    hover true
    completion resolve_provider: false
  end

  on_request :initialize do
    ElixirLsp.HandlerContext.reply(ctx, %{"capabilities" => __MODULE__.server_capabilities()})
  end

  on_request :text_document_hover do
    {:reply, %{"contents" => "Hello"}, state}
  end

  on_notification :text_document_did_open do
    {:ok, state}
  end
end
```

## Run over stdio

```elixir
ElixirLsp.Transport.Stdio.run(handler: MyHandler, init: %{})
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
