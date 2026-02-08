defmodule ElixirLsp.Capabilities do
  @moduledoc """
  Declarative builder for LSP server capabilities maps.

  ## Example

      import ElixirLsp.Capabilities

      caps =
        capabilities do
          hover true
          completion resolve: false, trigger_characters: ["."]
        end
  """

  defmacro capabilities(do: block) do
    quote do
      unquote(Macro.escape(ElixirLsp.Capabilities.from_ast(block)))
    end
  end

  @doc false
  def from_ast(block) do
    entries =
      case block do
        {:__block__, _meta, list} -> list
        other -> [other]
      end

    pairs = Enum.map(entries, &entry_to_pair/1)
    build_map(pairs)
  end

  def build_map(pairs) do
    Enum.reduce(pairs, %{}, fn {key, value}, acc ->
      Map.put(acc, wire_key(key), normalize(value))
    end)
  end

  defp entry_to_pair({name, _meta, [value]}) when is_atom(name), do: {name, value}
  defp entry_to_pair({name, _meta, args}) when is_atom(name), do: {name, args_to_value(args)}

  defp args_to_value([kw]) when is_list(kw) do
    Enum.into(kw, %{}, fn {k, v} -> {wire_key(k), v} end)
  end

  defp args_to_value(args), do: args

  defp wire_key(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> Macro.camelize()
    |> lower_first()
  end

  defp lower_first(<<first::utf8, rest::binary>>) do
    String.downcase(<<first::utf8>>) <> rest
  end

  defp normalize(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.into(value, %{}, fn {k, v} -> {wire_key(k), normalize(v)} end)
    else
      value
    end
  end

  defp normalize(value), do: value
end
