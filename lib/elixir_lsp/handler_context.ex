defmodule ElixirLsp.HandlerContext do
  @moduledoc """
  Context passed into handler callbacks.

  Provides convenience helpers for replying, returning errors, and emitting
  notifications without manual server process plumbing.
  """

  defstruct [:server, :request_id, :method, :cancel_token, :meta]

  @type t :: %__MODULE__{
          server: pid(),
          request_id: String.t() | integer() | nil,
          method: atom() | String.t() | nil,
          cancel_token: reference() | nil,
          meta: map()
        }

  @spec canceled?(t()) :: boolean()
  def canceled?(%__MODULE__{cancel_token: nil}), do: false

  def canceled?(%__MODULE__{cancel_token: token, server: server}) do
    ElixirLsp.Server.canceled?(server, token)
  end

  @spec reply(t(), term()) :: {:reply, term()}
  def reply(_ctx, result), do: {:reply, result}

  @spec noreply(t()) :: {:noreply}
  def noreply(_ctx), do: {:noreply}

  @spec error(t(), integer(), String.t(), term()) :: {:error, integer(), String.t(), term()}
  def error(_ctx, code, message, data \\ nil), do: {:error, code, message, data}

  @spec notify(t(), atom() | String.t(), term()) :: :ok
  def notify(%__MODULE__{server: server}, method, params \\ nil) do
    ElixirLsp.Server.send_notification(server, method, params)
  end

  @spec with_cancel(t(), (-> term())) :: term() | {:error, integer(), String.t(), nil}
  def with_cancel(ctx, fun), do: ElixirLsp.Cancellation.with_cancel(ctx, fun)

  @spec check_cancel!(t()) :: :ok | no_return()
  def check_cancel!(ctx), do: ElixirLsp.Cancellation.check_cancel!(ctx)
end
