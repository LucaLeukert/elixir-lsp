defmodule ElixirLsp.Cancellation do
  @moduledoc """
  Cooperative cancellation helpers for long-running handlers.
  """

  alias ElixirLsp.HandlerContext

  defmodule CancelledError do
    defexception message: "Request canceled", code: -32800
  end

  @spec with_cancel(HandlerContext.t(), (-> term())) ::
          term() | {:error, integer(), String.t(), nil}
  def with_cancel(%HandlerContext{} = ctx, fun) when is_function(fun, 0) do
    check_cancel!(ctx)
    result = fun.()
    check_cancel!(ctx)
    result
  rescue
    CancelledError -> {:error, -32800, "Request canceled", nil}
  end

  @spec check_cancel!(HandlerContext.t()) :: :ok | no_return()
  def check_cancel!(%HandlerContext{} = ctx) do
    if HandlerContext.canceled?(ctx), do: raise(CancelledError)
    :ok
  end
end
