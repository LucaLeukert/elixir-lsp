defmodule ElixirLsp.Keys do
  @moduledoc """
  Outbound key normalization helpers.

  Converts atom/snake_case map keys into LSP wire camelCase string keys.
  """

  @spec normalize_outbound(term()) :: term()
  def normalize_outbound(%module{} = struct) do
    cond do
      function_exported?(module, :to_map, 1) ->
        normalize_outbound(module.to_map(struct))

      true ->
        struct |> Map.from_struct() |> normalize_outbound()
    end
  end

  def normalize_outbound(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      {normalize_key(key), normalize_outbound(value)}
    end)
  end

  def normalize_outbound(list) when is_list(list), do: Enum.map(list, &normalize_outbound/1)
  def normalize_outbound(other), do: other

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> snake_to_camel()

  defp normalize_key(key) when is_binary(key) do
    if String.contains?(key, "_"), do: snake_to_camel(key), else: key
  end

  defp normalize_key(other), do: to_string(other)

  defp snake_to_camel(value) do
    case String.split(value, "_", trim: true) do
      [] ->
        value

      [head | tail] ->
        tail
        |> Enum.map(&Macro.camelize/1)
        |> then(&[String.downcase(head) | &1])
        |> Enum.join()
    end
  end
end
