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
    :telemetry.span(
      [:elixir_lsp, :middleware, :execution],
      %{system_time: System.system_time()},
      fn ->
        result = module.call(msg, ctx, next)
        {result, %{count: 1}, %{middleware: module}}
      end
    )
  end

  defp invoke(fun, msg, ctx, next) when is_function(fun, 3) do
    :telemetry.span(
      [:elixir_lsp, :middleware, :execution],
      %{system_time: System.system_time()},
      fn ->
        result = fun.(msg, ctx, next)
        {result, %{count: 1}, %{middleware: :function}}
      end
    )
  end
end
