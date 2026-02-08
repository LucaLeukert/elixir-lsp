defmodule ElixirLsp.Middleware.Logging do
  @moduledoc """
  Simple logging middleware for inbound messages.
  """

  require Logger

  def call(message, ctx, next) do
    Logger.debug("elixir_lsp inbound #{inspect(message)}")
    next.(message, ctx)
  end
end
