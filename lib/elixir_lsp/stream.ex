defmodule ElixirLsp.Stream do
  @moduledoc """
  Stateful streaming decoder for framed LSP messages.
  """

  alias ElixirLsp.{Framing, Message}

  defstruct buffer: "", messages: []

  @type t :: %__MODULE__{buffer: binary(), messages: [Message.t()]}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec push(t(), binary()) :: {:ok, [Message.t()], t()} | {:error, term(), t()}
  def push(%__MODULE__{buffer: buffer, messages: acc}, chunk) when is_binary(chunk) do
    case Framing.decode(chunk, buffer) do
      {:ok, decoded_maps, rest} ->
        with {:ok, messages} <- maps_to_messages(decoded_maps) do
          {:ok, messages, %__MODULE__{buffer: rest, messages: acc ++ messages}}
        end

      {:error, reason} ->
        {:error, reason, %__MODULE__{buffer: "", messages: acc}}
    end
  end

  @spec drain(t()) :: {[Message.t()], t()}
  def drain(%__MODULE__{} = stream), do: {stream.messages, %{stream | messages: []}}

  defp maps_to_messages(maps) do
    maps
    |> Enum.reduce_while({:ok, []}, fn map, {:ok, acc} ->
      case Message.from_map(map) do
        {:ok, message} -> {:cont, {:ok, [message | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      {:error, reason} -> {:error, reason}
    end
  end
end
