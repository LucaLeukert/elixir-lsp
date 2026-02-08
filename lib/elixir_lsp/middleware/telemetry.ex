defmodule ElixirLsp.Middleware.Telemetry do
  @moduledoc """
  Emits telemetry events for inbound messages.
  """

  def call(message, ctx, next) do
    :telemetry.execute([:elixir_lsp, :message, :inbound], %{count: 1}, %{message: message})
    next.(message, ctx)
  end
end
