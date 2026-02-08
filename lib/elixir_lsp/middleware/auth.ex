defmodule ElixirLsp.Middleware.Auth do
  @moduledoc """
  Example auth middleware.

  Expects `ctx[:authorized?]` to be truthy when enabled by caller.
  """

  def call(message, ctx, next) do
    authorized? = Map.get(ctx, :authorized?, true)
    next.(message, Map.put(ctx, :authorized?, authorized?))
  end
end
