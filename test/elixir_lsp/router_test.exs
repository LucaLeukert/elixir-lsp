defmodule ElixirLsp.RouterTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.{Message, Protocol, Server}

  defmodule RoutedHandler do
    use ElixirLsp.Router

    capabilities do
      hover(true)
      completion(resolve_provider: false)
    end

    on_request :initialize do
      ElixirLsp.HandlerContext.reply(ctx, %{"capabilities" => __MODULE__.server_capabilities()})
    end

    on_request :text_document_hover do
      {:reply, %{"contents" => "hover"}, _state}
    end

    on_notification :text_document_did_open do
      {:ok, state ++ [:opened]}
    end
  end

  test "router dispatches and default method-not-found" do
    parent = self()

    {:ok, server} =
      Server.start_link(
        handler: RoutedHandler,
        handler_arg: [],
        send: fn payload -> send(parent, {:outbound, IO.iodata_to_binary(payload)}) end
      )

    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :shutdown) end)

    init = Protocol.request(1, :initialize, %{}) |> Protocol.encode() |> IO.iodata_to_binary()
    Server.feed(server, init)

    assert_receive {:outbound, payload}, 500

    assert {:ok, [%Message.Response{result: %{"capabilities" => caps}}], _} =
             Protocol.decode(payload, Protocol.new_state())

    assert caps["hover"] == true
    assert caps["completion"]["resolveProvider"] == false

    unknown =
      Protocol.request(2, "custom/unknown", %{}) |> Protocol.encode() |> IO.iodata_to_binary()

    Server.feed(server, unknown)

    assert_receive {:outbound, payload2}, 500

    assert {:ok, [%Message.ErrorResponse{error: %Message.Error{code: -32601}}], _} =
             Protocol.decode(payload2, Protocol.new_state())
  end
end
