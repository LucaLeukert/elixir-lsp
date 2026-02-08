defmodule ElixirLsp.RequestLifecycleTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.{HandlerContext, Message, Protocol, Server}

  defmodule SlowHandler do
    @behaviour Server.Handler

    @impl true
    def init(_), do: {:ok, %{}}

    @impl true
    def handle_request(method, params, id, state) do
      handle_request(method, params, id, %HandlerContext{server: self()}, state)
    end

    @impl true
    def handle_request(:initialize, _params, _id, ctx, state) do
      Process.sleep(100)

      if HandlerContext.canceled?(ctx) do
        {:error, -32800, "Canceled in handler", nil, state}
      else
        {:reply, %{"ok" => true}, state}
      end
    end

    @impl true
    def handle_request(_method, _params, _id, _ctx, state), do: {:reply, %{}, state}
  end

  test "cancel request emits canceled response" do
    parent = self()

    {:ok, server} =
      Server.start_link(
        handler: SlowHandler,
        request_timeout: 1000,
        send: fn payload -> send(parent, {:outbound, IO.iodata_to_binary(payload)}) end
      )

    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :shutdown) end)

    req = Protocol.request(1, :initialize, %{}) |> Protocol.encode() |> IO.iodata_to_binary()

    cancel =
      Protocol.notification(:cancel_request, %{"id" => 1})
      |> Protocol.encode()
      |> IO.iodata_to_binary()

    Server.feed(server, req)
    Server.feed(server, cancel)

    assert_receive {:outbound, payload}, 500
    assert {:ok, [message], _} = Protocol.decode(payload, Protocol.new_state())

    assert %Message.ErrorResponse{error: %Message.Error{code: -32800}} = message
  end

  test "request timeout emits cancellation error" do
    parent = self()

    {:ok, server} =
      Server.start_link(
        handler: SlowHandler,
        request_timeout: 10,
        send: fn payload -> send(parent, {:outbound, IO.iodata_to_binary(payload)}) end
      )

    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :shutdown) end)

    req = Protocol.request(2, :initialize, %{}) |> Protocol.encode() |> IO.iodata_to_binary()
    Server.feed(server, req)

    assert_receive {:outbound, payload}, 500

    assert {:ok, [%Message.ErrorResponse{error: %Message.Error{code: -32800}}], _} =
             Protocol.decode(payload, Protocol.new_state())
  end
end
