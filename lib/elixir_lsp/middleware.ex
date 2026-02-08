defmodule ElixirLsp.Middleware do
  @moduledoc """
  Middleware utilities for inbound JSON-RPC/LSP messages.
  """

  @type message :: ElixirLsp.Message.t()
  @type context :: map()
  @type next_fun :: (message(), context() -> {message(), context()})
  @type middleware :: (message(), context(), next_fun() -> {message(), context()})

  @spec run([module() | middleware()], message(), context()) :: {message(), context()}
  def run(middlewares, message, context) do
    chain =
      Enum.reduce(Enum.reverse(middlewares), fn msg, ctx -> {msg, ctx} end, fn mw, acc ->
        fn msg, ctx -> invoke(mw, msg, ctx, acc) end
      end)

    chain.(message, context)
  end

  defp invoke(module, msg, ctx, next) when is_atom(module) do
    module.call(msg, ctx, next)
  end

  defp invoke(fun, msg, ctx, next) when is_function(fun, 3), do: fun.(msg, ctx, next)
end
