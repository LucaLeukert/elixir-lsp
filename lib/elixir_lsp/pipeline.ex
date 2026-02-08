defmodule ElixirLsp.Pipeline do
  @moduledoc """
  Enumerable/Collectable-friendly stream and message pipeline helpers.
  """

  alias ElixirLsp.Stream

  @spec decode_chunks(Enumerable.t(), Stream.t()) :: Stream.t()
  def decode_chunks(chunks, stream \\ Stream.new()) do
    Enum.into(chunks, stream)
  end

  @spec messages(Stream.t()) :: Enumerable.t()
  def messages(%Stream{} = stream), do: stream
end
