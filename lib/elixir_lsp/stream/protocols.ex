defimpl Enumerable, for: ElixirLsp.Stream do
  def reduce(stream, acc, fun), do: Enumerable.List.reduce(stream.messages, acc, fun)
  def member?(stream, value), do: {:ok, Enum.member?(stream.messages, value)}
  def count(stream), do: {:ok, length(stream.messages)}
  def slice(_stream), do: {:error, __MODULE__}
end

defimpl Collectable, for: ElixirLsp.Stream do
  def into(original) do
    collector = fn
      stream, {:cont, chunk} ->
        case ElixirLsp.Stream.push(stream, chunk) do
          {:ok, _messages, next_stream} -> next_stream
          {:error, _reason, next_stream} -> next_stream
        end

      stream, :done ->
        stream

      _stream, :halt ->
        :ok
    end

    {original, collector}
  end
end
