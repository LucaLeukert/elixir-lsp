defmodule ElixirLsp.Middleware.Throttle do
  @moduledoc """
  Simple in-process throttling middleware.

  Uses `ctx[:throttle_ms]` to drop rapid repeated messages by method.
  """

  alias ElixirLsp.Message

  def call(message, ctx, next) do
    throttle_ms = Map.get(ctx, :throttle_ms)

    if is_integer(throttle_ms) and throttle_ms > 0 do
      now = System.monotonic_time(:millisecond)
      key = method_key(message)
      last = Process.get({__MODULE__, key})

      if is_integer(last) and now - last < throttle_ms do
        {message, Map.put(ctx, :throttled, true)}
      else
        Process.put({__MODULE__, key}, now)
        next.(message, ctx)
      end
    else
      next.(message, ctx)
    end
  end

  defp method_key(%Message.Request{method: method}), do: {:request, method}
  defp method_key(%Message.Notification{method: method}), do: {:notification, method}
  defp method_key(_), do: :other
end
