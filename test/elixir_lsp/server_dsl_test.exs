defmodule ElixirLsp.ServerDslTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.{HandlerContext, Message, Protocol, Server}

  defmodule DslHandler do
    use ElixirLsp.Server

    defrequest :initialize do
      with_cancel(ctx, fn ->
        ElixirLsp.HandlerContext.reply(
          ctx,
          ElixirLsp.Responses.initialize(%{hover_provider: true}, name: "dsl")
        )
      end)
    end

    defnotification :text_document_did_open do
      check_cancel!(ctx)
      {:ok, Map.put(state, :opened, params)}
    end
  end

  test "defrequest routes and builds initialize response" do
    parent = self()

    {:ok, server} =
      Server.start_link(
        handler: DslHandler,
        send: fn payload -> send(parent, {:outbound, IO.iodata_to_binary(payload)}) end
      )

    req = Protocol.request(10, :initialize, %{}) |> Protocol.encode() |> IO.iodata_to_binary()
    Server.feed(server, req)

    assert_receive {:outbound, payload}, 500

    assert {:ok, [%Message.Response{result: result}], _} =
             Protocol.decode(payload, Protocol.new_state())

    assert result["capabilities"]["hoverProvider"] == true
    assert result["serverInfo"]["name"] == "dsl"
  end

  test "with_cancel maps cancellation exception into protocol tuple" do
    ctx = %HandlerContext{server: self(), cancel_token: nil}

    assert {:error, -32800, "Request canceled", nil} =
             HandlerContext.with_cancel(ctx, fn ->
               raise ElixirLsp.Cancellation.CancelledError
             end)
  end

  test "pubsub broadcasts diagnostics/progress and custom events" do
    parent = self()
    topic_prefix = "elixir_lsp_test_#{System.unique_integer([:positive])}"

    ElixirLsp.PubSub.subscribe(ElixirLsp.PubSub, "#{topic_prefix}:diagnostics")
    ElixirLsp.PubSub.subscribe(ElixirLsp.PubSub, "#{topic_prefix}:progress")
    ElixirLsp.PubSub.subscribe(ElixirLsp.PubSub, "#{topic_prefix}:event:build")

    {:ok, server} =
      Server.start_link(
        handler: DslHandler,
        send: fn payload -> send(parent, {:outbound, IO.iodata_to_binary(payload)}) end,
        pubsub: [name: ElixirLsp.PubSub, topic_prefix: topic_prefix]
      )

    Server.send_notification(server, :text_document_publish_diagnostics, %{
      uri: "file:///a.ex",
      diagnostics: []
    })

    Server.send_notification(server, :progress, %{token: "1", value: %{kind: "report"}})
    Server.emit_event(server, :build, %{status: :ok})

    assert_receive {:elixir_lsp, "diagnostics", %{"uri" => "file:///a.ex", "diagnostics" => []}},
                   500

    assert_receive {:elixir_lsp, "progress", %{"token" => "1", "value" => %{"kind" => "report"}}},
                   500

    assert_receive {:elixir_lsp, "event:build", %{"status" => :ok}}, 500
  end
end
