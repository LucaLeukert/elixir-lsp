defmodule ElixirLsp do
  @moduledoc """
  Elixir-native protocol building blocks for Language Server Protocol (LSP).

  This library is protocol-only and use-case agnostic.
  """

  alias ElixirLsp.{Message, Protocol, Server, Stream, Transport.Stdio}

  @spec request(String.t() | integer(), atom() | String.t(), term()) :: Message.Request.t()
  defdelegate request(id, method, params \\ nil), to: Protocol

  @spec notification(atom() | String.t(), term()) :: Message.Notification.t()
  defdelegate notification(method, params \\ nil), to: Protocol

  @spec response(String.t() | integer() | nil, term()) :: Message.Response.t()
  defdelegate response(id, result), to: Protocol

  @spec error_response(String.t() | integer() | nil, integer(), String.t(), term()) ::
          Message.ErrorResponse.t()
  defdelegate error_response(id, code, message, data \\ nil), to: Protocol

  @spec encode(Message.t()) :: iodata()
  defdelegate encode(message), to: Protocol

  @spec new_state() :: Stream.t()
  defdelegate new_state(), to: Protocol

  @spec recv(binary(), Stream.t() | nil) ::
          {:ok, [Message.t()], Stream.t()} | {:error, term(), Stream.t()}
  def recv(chunk, state \\ nil), do: Protocol.decode(chunk, state || Protocol.new_state())

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  defdelegate child_spec(opts), to: Server

  @spec run_stdio(keyword()) :: no_return()
  defdelegate run_stdio(opts), to: Stdio, as: :run
end
