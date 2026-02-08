defmodule ElixirLsp.TelemetryTest do
  use ExUnit.Case, async: false

  alias ElixirLsp.{Message, Protocol, Server}

  defmodule TelemetryHandler do
    use ElixirLsp.Server

    defrequest :initialize do
      {:reply, %{ok: true}, state}
    end

    defrequest "boom" do
      raise "boom"
    end
  end

  setup do
    parent = self()

    req_ref = make_ref()
    mw_ref = make_ref()

    :telemetry.attach_many(
      req_ref,
      [
        [:elixir_lsp, :request, :start],
        [:elixir_lsp, :request, :stop],
        [:elixir_lsp, :request, :exception]
      ],
      fn event, measurements, metadata, _ ->
        send(parent, {:request_telemetry, event, measurements, metadata})
      end,
      nil
    )

    :telemetry.attach_many(
      mw_ref,
      [
        [:elixir_lsp, :middleware, :execution, :start],
        [:elixir_lsp, :middleware, :execution, :stop],
        [:elixir_lsp, :middleware, :execution, :exception]
      ],
      fn event, measurements, metadata, _ ->
        send(parent, {:middleware_telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(req_ref)
      :telemetry.detach(mw_ref)
    end)

    :ok
  end

  test "emits request lifecycle start/stop telemetry" do
    parent = self()

    {:ok, server} =
      Server.start_link(
        handler: TelemetryHandler,
        middlewares: [ElixirLsp.Middleware.Telemetry],
        send: fn payload -> send(parent, {:outbound, IO.iodata_to_binary(payload)}) end
      )

    req = Protocol.request(1, :initialize, %{}) |> Protocol.encode() |> IO.iodata_to_binary()
    Server.feed(server, req)

    assert_receive {:outbound, payload}, 500
    assert {:ok, [%Message.Response{}], _} = Protocol.decode(payload, Protocol.new_state())

    assert_receive {:request_telemetry, [:elixir_lsp, :request, :start], _,
                    %{method: :initialize}},
                   500

    assert_receive {:request_telemetry, [:elixir_lsp, :request, :stop], %{duration: _},
                    %{method: :initialize}},
                   500

    assert_receive {:middleware_telemetry, [:elixir_lsp, :middleware, :execution, :start], _, _},
                   500

    assert_receive {:middleware_telemetry, [:elixir_lsp, :middleware, :execution, :stop], _, _},
                   500
  end

  test "emits request exception telemetry for handler crash" do
    parent = self()

    {:ok, server} =
      Server.start_link(
        handler: TelemetryHandler,
        send: fn payload -> send(parent, {:outbound, IO.iodata_to_binary(payload)}) end
      )

    req = Protocol.request(2, "boom", %{}) |> Protocol.encode() |> IO.iodata_to_binary()
    Server.feed(server, req)

    assert_receive {:outbound, _}, 500

    assert_receive {:request_telemetry, [:elixir_lsp, :request, :exception], %{duration: _},
                    %{method: "boom"}},
                   500
  end
end
