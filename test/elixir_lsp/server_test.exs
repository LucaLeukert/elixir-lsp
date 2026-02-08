defmodule ElixirLsp.ServerTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.{Message, Protocol, Server}

  defmodule EchoHandler do
    @behaviour Server.Handler

    @impl true
    def init(_), do: {:ok, %{responses: []}}

    @impl true
    def handle_request(:initialize, params, _id, state),
      do: {:reply, %{"capabilities" => params}, state}

    @impl true
    def handle_request(_method, _params, _id, state),
      do: {:error, -32601, "Method not found", nil, state}

    @impl true
    def handle_response(message, state) do
      {:ok, %{state | responses: [message | state.responses]}}
    end
  end

  test "routes typed request and emits framed response" do
    parent = self()

    {:ok, pid} =
      Server.start_link(
        handler: EchoHandler,
        send: fn framed -> send(parent, {:outbound, IO.iodata_to_binary(framed)}) end
      )

    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :shutdown) end)

    request =
      Protocol.request(1, :initialize, %{"workspaceFolders" => []})
      |> Protocol.encode()
      |> IO.iodata_to_binary()

    Server.feed(pid, request)

    assert_receive {:outbound, outbound}, 500

    assert {:ok, [%Message.Response{} = response], _} =
             Protocol.decode(outbound, Protocol.new_state())

    assert response.id == 1
    assert response.result == %{"capabilities" => %{"workspaceFolders" => []}}
  end

  test "send_notification emits protocol-framed message" do
    parent = self()

    {:ok, pid} =
      Server.start_link(
        handler: EchoHandler,
        send: fn framed -> send(parent, {:outbound, IO.iodata_to_binary(framed)}) end
      )

    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :shutdown) end)

    Server.send_notification(pid, :window_log_message, %{"type" => 3, "message" => "hello"})

    assert_receive {:outbound, outbound}, 500

    assert {:ok, [%Message.Notification{} = notification], _} =
             Protocol.decode(outbound, Protocol.new_state())

    assert notification.method == :window_log_message
    assert notification.params["message"] == "hello"
  end
end
