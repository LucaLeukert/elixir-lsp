defmodule ElixirLsp.Types do
  @moduledoc """
  Common LSP structures with validation and map conversion.
  """

  defmodule Position do
    defstruct [:line, :character]

    def new(line, character)

    def new(line, character)
        when is_integer(line) and line >= 0 and is_integer(character) and character >= 0,
        do: {:ok, %__MODULE__{line: line, character: character}}

    def new(_, _), do: {:error, :invalid_position}

    def to_map(%__MODULE__{line: line, character: character}),
      do: %{"line" => line, "character" => character}
  end

  defmodule Range do
    defstruct [:start, :end]

    def new(%Position{} = start_pos, %Position{} = end_pos),
      do: {:ok, %__MODULE__{start: start_pos, end: end_pos}}

    def new(_, _), do: {:error, :invalid_range}

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

    def to_map(%__MODULE__{range: r, new_text: t}),
      do: %{"range" => Range.to_map(r), "newText" => t}
  end

  defmodule WorkspaceEdit do
    defstruct changes: %{}

    def new(changes \\ %{}) when is_map(changes), do: {:ok, %__MODULE__{changes: changes}}

    def to_map(%__MODULE__{changes: changes}) do
      normalized =
        Enum.into(changes, %{}, fn {uri, edits} ->
          {uri, Enum.map(edits, &TextEdit.to_map/1)}
        end)

      %{"changes" => normalized}
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

    defp maybe_put(map, _k, nil), do: map
    defp maybe_put(map, k, v), do: Map.put(map, k, v)
  end
end
