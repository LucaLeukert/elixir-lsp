defmodule ElixirLsp.Types do
  @moduledoc """
  Common LSP structures with validation and map conversion.
  """

  @spec to_map(term()) :: map()
  def to_map(%module{} = struct) do
    module.to_map(struct)
  end

  @spec from_map(module(), map()) :: {:ok, struct()} | {:error, term()}
  def from_map(module, map) when is_atom(module) and is_map(map) do
    module.from_map(map)
  end

  defmodule Position do
    defstruct [:line, :character]

    def new(line, character)

    def new(line, character)
        when is_integer(line) and line >= 0 and is_integer(character) and character >= 0,
        do: {:ok, %__MODULE__{line: line, character: character}}

    def new(_, _), do: {:error, :invalid_position}

    def from_map(%{"line" => line, "character" => character}), do: new(line, character)
    def from_map(_), do: {:error, :invalid_position}

    def to_map(%__MODULE__{line: line, character: character}),
      do: %{"line" => line, "character" => character}
  end

  defmodule Range do
    defstruct [:start, :end]

    def new(%Position{} = start_pos, %Position{} = end_pos),
      do: {:ok, %__MODULE__{start: start_pos, end: end_pos}}

    def new(_, _), do: {:error, :invalid_range}

    def from_map(%{"start" => start_pos, "end" => end_pos}) do
      with {:ok, start_pos} <- Position.from_map(start_pos),
           {:ok, end_pos} <- Position.from_map(end_pos) do
        new(start_pos, end_pos)
      end
    end

    def from_map(_), do: {:error, :invalid_range}

    def to_map(%__MODULE__{start: s, end: e}),
      do: %{"start" => Position.to_map(s), "end" => Position.to_map(e)}
  end

  defmodule Diagnostic do
    defstruct [:range, :message, :severity, :code, :source]

    def new(range, message, opts \\ [])

    def new(%Range{} = range, message, opts) when is_binary(message) do
      {:ok,
       %__MODULE__{
         range: range,
         message: message,
         severity: Keyword.get(opts, :severity),
         code: Keyword.get(opts, :code),
         source: Keyword.get(opts, :source)
       }}
    end

    def new(_, _, _), do: {:error, :invalid_diagnostic}

    def from_map(%{"range" => range, "message" => message} = map) do
      with {:ok, range} <- Range.from_map(range) do
        new(range, message,
          severity: Map.get(map, "severity"),
          code: Map.get(map, "code"),
          source: Map.get(map, "source")
        )
      end
    end

    def from_map(_), do: {:error, :invalid_diagnostic}

    def to_map(%__MODULE__{} = d) do
      %{"range" => Range.to_map(d.range), "message" => d.message}
      |> maybe_put("severity", d.severity)
      |> maybe_put("code", d.code)
      |> maybe_put("source", d.source)
    end

    defp maybe_put(map, _k, nil), do: map
    defp maybe_put(map, k, v), do: Map.put(map, k, v)
  end

  defmodule TextEdit do
    defstruct [:range, :new_text]

    def new(%Range{} = range, new_text) when is_binary(new_text),
      do: {:ok, %__MODULE__{range: range, new_text: new_text}}

    def new(_, _), do: {:error, :invalid_text_edit}

    def from_map(%{"range" => range, "newText" => new_text}) do
      with {:ok, range} <- Range.from_map(range) do
        new(range, new_text)
      end
    end

    def from_map(_), do: {:error, :invalid_text_edit}

    def to_map(%__MODULE__{range: r, new_text: t}),
      do: %{"range" => Range.to_map(r), "newText" => t}
  end

  defmodule WorkspaceEdit do
    defstruct changes: %{}

    def new(changes \\ %{}) when is_map(changes), do: {:ok, %__MODULE__{changes: changes}}

    def from_map(%{"changes" => changes}) when is_map(changes) do
      with {:ok, normalized} <- normalize_changes(changes) do
        new(normalized)
      end
    end

    def from_map(_), do: {:error, :invalid_workspace_edit}

    def to_map(%__MODULE__{changes: changes}) do
      normalized =
        Enum.into(changes, %{}, fn {uri, edits} ->
          {uri, Enum.map(edits, &TextEdit.to_map/1)}
        end)

      %{"changes" => normalized}
    end

    defp normalize_changes(changes) do
      Enum.reduce_while(changes, {:ok, %{}}, fn {uri, edits}, {:ok, acc} ->
        with true <- is_list(edits),
             {:ok, parsed_edits} <- parse_edits(edits) do
          {:cont, {:ok, Map.put(acc, uri, parsed_edits)}}
        else
          _ -> {:halt, {:error, :invalid_workspace_edit}}
        end
      end)
    end

    defp parse_edits(edits) do
      Enum.reduce_while(edits, {:ok, []}, fn edit, {:ok, acc} ->
        case TextEdit.from_map(edit) do
          {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
          {:error, _} -> {:halt, {:error, :invalid_workspace_edit}}
        end
      end)
      |> case do
        {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
        err -> err
      end
    end
  end

  defmodule CodeAction do
    defstruct [:title, :kind, :diagnostics, :edit, :command]

    def new(title, opts \\ [])

    def new(title, opts) when is_binary(title) do
      {:ok,
       %__MODULE__{
         title: title,
         kind: Keyword.get(opts, :kind),
         diagnostics: Keyword.get(opts, :diagnostics),
         edit: Keyword.get(opts, :edit),
         command: Keyword.get(opts, :command)
       }}
    end

    def new(_, _), do: {:error, :invalid_code_action}

    def from_map(%{"title" => title} = map) when is_binary(title) do
      with {:ok, diagnostics} <- parse_diagnostics(Map.get(map, "diagnostics")),
           {:ok, edit} <- parse_workspace_edit(Map.get(map, "edit")) do
        new(title,
          kind: Map.get(map, "kind"),
          diagnostics: diagnostics,
          edit: edit,
          command: Map.get(map, "command")
        )
      end
    end

    def from_map(_), do: {:error, :invalid_code_action}

    def to_map(%__MODULE__{} = action) do
      %{"title" => action.title}
      |> maybe_put("kind", action.kind)
      |> maybe_put(
        "diagnostics",
        if(is_list(action.diagnostics),
          do: Enum.map(action.diagnostics, &Diagnostic.to_map/1),
          else: nil
        )
      )
      |> maybe_put("edit", if(action.edit, do: WorkspaceEdit.to_map(action.edit), else: nil))
      |> maybe_put("command", action.command)
    end

    defp parse_diagnostics(nil), do: {:ok, nil}

    defp parse_diagnostics(list) when is_list(list) do
      Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
        case Diagnostic.from_map(item) do
          {:ok, diagnostic} -> {:cont, {:ok, [diagnostic | acc]}}
          {:error, _} -> {:halt, {:error, :invalid_code_action}}
        end
      end)
      |> case do
        {:ok, diagnostics} -> {:ok, Enum.reverse(diagnostics)}
        err -> err
      end
    end

    defp parse_diagnostics(_), do: {:error, :invalid_code_action}

    defp parse_workspace_edit(nil), do: {:ok, nil}

    defp parse_workspace_edit(edit_map) when is_map(edit_map) do
      case WorkspaceEdit.from_map(edit_map) do
        {:ok, edit} -> {:ok, edit}
        {:error, _} -> {:error, :invalid_code_action}
      end
    end

    defp parse_workspace_edit(_), do: {:error, :invalid_code_action}

    defp maybe_put(map, _k, nil), do: map
    defp maybe_put(map, k, v), do: Map.put(map, k, v)
  end
end
