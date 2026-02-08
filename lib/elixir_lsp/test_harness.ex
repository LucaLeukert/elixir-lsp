defmodule ElixirLsp.TestHarness do
  @moduledoc """
  In-memory client/server harness for deterministic LSP tests.
  """

  use GenServer

  alias ElixirLsp.{Protocol, Server}

  @pubsub_schema [
    name: [type: :atom, default: ElixirLsp.PubSub],
    topic_prefix: [type: :string, default: "elixir_lsp"]
  ]
  @options_schema [
    handler: [type: :atom, required: true],
    init: [type: :any, required: false],
    middlewares: [type: {:list, :any}, default: []],
    request_timeout: [type: :non_neg_integer, default: 30_000],
    pubsub: [type: :keyword_list, required: false]
  ]

  defstruct [:server, outbound: [], stream: ElixirLsp.Protocol.new_state()]

  @type t :: pid()

  def start_link(opts) do
    validated = NimbleOptions.validate!(opts, @options_schema)

    validated =
      if validated[:pubsub],
        do:
          Keyword.put(
            validated,
            :pubsub,
            NimbleOptions.validate!(validated[:pubsub], @pubsub_schema)
          ),
        else: validated

    GenServer.start_link(__MODULE__, validated)
  end

  def request(pid, id, method, params \\ nil) do
    GenServer.call(pid, {:request, id, method, params})
  end

  def notify(pid, method, params \\ nil) do
    GenServer.call(pid, {:notify, method, params})
  end

  def drain_outbound(pid) do
    GenServer.call(pid, :drain_outbound)
  end

  @impl true
  def init(opts) do
    parent = self()

    {:ok, server} =
      Server.start_link(
        handler: Keyword.fetch!(opts, :handler),
        handler_arg: Keyword.get(opts, :init),
        middlewares: Keyword.get(opts, :middlewares, []),
        request_timeout: Keyword.get(opts, :request_timeout, 30_000),
        pubsub: Keyword.get(opts, :pubsub),
        send: fn framed -> send(parent, {:outbound, IO.iodata_to_binary(framed)}) end
      )

    {:ok, %__MODULE__{server: server}}
  end

  @impl true
  def handle_call({:request, id, method, params}, _from, state) do
    feed(state.server, Protocol.request(id, method, params))
    {:reply, :ok, collect_outbound(state, 500)}
  end

  def handle_call({:notify, method, params}, _from, state) do
    feed(state.server, Protocol.notification(method, params))
    {:reply, :ok, collect_outbound(state, 500)}
  end

  def handle_call(:drain_outbound, _from, state) do
    {messages, stream} = decode_all(state.outbound, state.stream, [])
    {:reply, messages, %{state | stream: stream, outbound: []}}
  end

  @impl true
  def handle_info({:outbound, framed}, state) do
    {:noreply, %{state | outbound: [framed | state.outbound]}}
  end

  defp collect_outbound(state, timeout_ms) do
    receive do
      {:outbound, framed} ->
        collect_outbound(%{state | outbound: [framed | state.outbound]}, 0)
    after
      timeout_ms -> state
    end
  end

  defp feed(server, message) do
    message |> Protocol.encode() |> IO.iodata_to_binary() |> then(&Server.feed(server, &1))
  end

  defp decode_all([], stream, acc), do: {Enum.reverse(acc), stream}

  defp decode_all([payload | rest], stream, acc) do
    case Protocol.decode(payload, stream) do
      {:ok, messages, next_stream} -> decode_all(rest, next_stream, Enum.reverse(messages) ++ acc)
      {:error, _, next_stream} -> decode_all(rest, next_stream, acc)
    end
  end
end
