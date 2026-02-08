defmodule ElixirLsp.PubSub do
  @moduledoc """
  PubSub integration helpers for diagnostics/progress/event fanout.
  """

  @default_name ElixirLsp.PubSub

  @options_schema [
    name: [
      type: :atom,
      default: @default_name,
      doc: "PubSub process name."
    ],
    adapter_name: [
      type: :atom,
      default: Phoenix.PubSub.PG2,
      doc: "Phoenix.PubSub adapter."
    ]
  ]

  @type topic :: String.t()

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @options_schema)
    Phoenix.PubSub.Supervisor.start_link(name: opts[:name], adapter: opts[:adapter_name])
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    opts = NimbleOptions.validate!(opts, @options_schema)
    Phoenix.PubSub.child_spec(name: opts[:name], adapter: opts[:adapter_name])
  end

  @spec subscribe(atom(), topic()) :: :ok | {:error, term()}
  def subscribe(name \\ @default_name, topic) when is_atom(name) and is_binary(topic) do
    Phoenix.PubSub.subscribe(name, topic)
  end

  @spec unsubscribe(atom(), topic()) :: :ok
  def unsubscribe(name \\ @default_name, topic) when is_atom(name) and is_binary(topic) do
    Phoenix.PubSub.unsubscribe(name, topic)
  end

  @spec broadcast(atom(), topic(), term()) :: :ok | {:error, term()}
  def broadcast(name \\ @default_name, topic, message)
      when is_atom(name) and is_binary(topic) do
    Phoenix.PubSub.broadcast(name, topic, message)
  end
end
