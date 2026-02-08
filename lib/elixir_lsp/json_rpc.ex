defmodule ElixirLsp.JsonRpc do
  @moduledoc """
  Backward-compatible JSON-RPC map helpers.

  Prefer `ElixirLsp.Protocol` and `ElixirLsp.Message` for native struct usage.
  """

  alias ElixirLsp.Message

  @spec request(String.t() | integer(), atom() | String.t(), term()) :: map()
  def request(id, method, params \\ nil),
    do: id |> Message.request(method, params) |> Message.to_map()

  @spec notification(atom() | String.t(), term()) :: map()
  def notification(method, params \\ nil),
    do: method |> Message.notification(params) |> Message.to_map()

  @spec response(String.t() | integer() | nil, term()) :: map()
  def response(id, result), do: id |> Message.response(result) |> Message.to_map()

  @spec error_response(String.t() | integer() | nil, integer(), String.t(), term() | nil) :: map()
  def error_response(id, code, message, data \\ nil),
    do: id |> Message.error_response(code, message, data) |> Message.to_map()

  @spec message_type(map()) :: :request | :notification | :response | :error_response | :invalid
  def message_type(message) when is_map(message) do
    case Message.from_map(message) do
      {:ok, %Message.Request{}} -> :request
      {:ok, %Message.Notification{}} -> :notification
      {:ok, %Message.Response{}} -> :response
      {:ok, %Message.ErrorResponse{}} -> :error_response
      {:error, _} -> :invalid
    end
  end
end
