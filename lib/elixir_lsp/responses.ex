defmodule ElixirLsp.Responses do
  @moduledoc """
  Elixir-native builders for common LSP response payloads.
  """

  @spec initialize(map(), keyword()) :: map()
  def initialize(capabilities, opts \\ []) when is_map(capabilities) and is_list(opts) do
    %{
      capabilities: capabilities,
      server_info: %{
        name: Keyword.fetch!(opts, :name),
        version: Keyword.get(opts, :version)
      }
    }
    |> maybe_drop_nil_server_info()
  end

  @spec workspace_apply_edit(boolean(), keyword()) :: map()
  def workspace_apply_edit(applied, opts \\ []) when is_boolean(applied) and is_list(opts) do
    %{applied: applied, failure_reason: Keyword.get(opts, :failure_reason)}
    |> maybe_drop_nil(:failure_reason)
  end

  defp maybe_drop_nil_server_info(%{server_info: %{version: nil} = info} = map) do
    %{map | server_info: Map.delete(info, :version)}
  end

  defp maybe_drop_nil_server_info(map), do: map

  defp maybe_drop_nil(map, key) do
    if Map.get(map, key) == nil, do: Map.delete(map, key), else: map
  end
end
