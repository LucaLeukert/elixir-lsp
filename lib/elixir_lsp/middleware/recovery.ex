defmodule ElixirLsp.Middleware.Recovery do
  @moduledoc """
  Panic recovery middleware.
  """

  def call(message, ctx, next) do
    try do
      next.(message, ctx)
    rescue
      exception ->
        ctx = Map.put(ctx, :middleware_exception, {exception, __STACKTRACE__})
        {message, ctx}
    end
  end
end
