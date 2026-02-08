defmodule ElixirLsp.Middleware.Tracing do
  @moduledoc """
  Adds a trace id to middleware context.
  """

  def call(message, ctx, next) do
    trace_id = System.unique_integer([:positive, :monotonic])
    next.(message, Map.put(ctx, :trace_id, trace_id))
  end
end
