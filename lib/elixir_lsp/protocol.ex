defmodule ElixirLsp.Protocol do
  @moduledoc """
  Elixir-native API for constructing and receiving LSP protocol messages.
  """

  alias ElixirLsp.{Framing, Message, Stream}

  @type decode_state :: Stream.t()

  @spec new_state() :: decode_state()
  def new_state, do: Stream.new()

  @spec request(String.t() | integer(), atom() | String.t(), term()) :: Message.Request.t()
  def request(id, method, params \\ nil), do: Message.request(id, method, params)

  @spec notification(atom() | String.t(), term()) :: Message.Notification.t()
  def notification(method, params \\ nil), do: Message.notification(method, params)

  @spec response(String.t() | integer() | nil, term()) :: Message.Response.t()
  def response(id, result), do: Message.response(id, result)

  @spec error_response(String.t() | integer() | nil, integer(), String.t(), term()) ::
          Message.ErrorResponse.t()
  def error_response(id, code, message, data \\ nil),
    do: Message.error_response(id, code, message, data)

  @spec encode(Message.t()) :: iodata()
  def encode(message), do: message |> Message.to_map() |> Framing.encode()

  @spec decode(binary(), decode_state()) ::
          {:ok, [Message.t()], decode_state()} | {:error, term(), decode_state()}
  def decode(chunk, %Stream{} = state), do: Stream.push(state, chunk)
  def decode(chunk, nil), do: decode(chunk, new_state())
end
