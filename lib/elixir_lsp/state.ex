defmodule ElixirLsp.State do
  @moduledoc """
  Server context toolkit for common LSP state.

  Includes open document tracking, URI/path conversion, workspace folders,
  and text synchronization helpers for didOpen/didChange/didClose.

  Lifecycle mode:

  - `:lenient` (default): ignore out-of-order lifecycle events such as
    `didChange` for unopened documents.
  - `:strict`: raise on out-of-order lifecycle events.
  """

  @type mode :: :lenient | :strict

  defstruct documents: %{}, workspace_folders: [], mode: :lenient

  @type document :: %{
          text: String.t(),
          version: integer() | nil,
          language_id: String.t() | nil
        }

  @type t :: %__MODULE__{
          documents: %{optional(String.t()) => document()},
          workspace_folders: [map()],
          mode: mode()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    mode = Keyword.get(opts, :mode, :lenient)

    if mode in [:lenient, :strict] do
      %__MODULE__{mode: mode}
    else
      raise ArgumentError, "invalid mode #{inspect(mode)}. expected :lenient or :strict"
    end
  end

  @spec open_document(t(), String.t(), String.t(), integer() | nil, String.t() | nil) :: t()
  def open_document(%__MODULE__{} = state, uri, text, version, language_id) do
    doc = %{text: text, version: version, language_id: language_id}
    put_in(state.documents[uri], doc)
  end

  @spec close_document(t(), String.t()) :: t()
  def close_document(%__MODULE__{} = state, uri),
    do: update_in(state.documents, &Map.delete(&1, uri))

  @spec get_document(t(), String.t()) :: document() | nil
  def get_document(%__MODULE__{} = state, uri), do: Map.get(state.documents, uri)

  @spec set_workspace_folders(t(), [map()]) :: t()
  def set_workspace_folders(%__MODULE__{} = state, folders) when is_list(folders),
    do: %{state | workspace_folders: folders}

  @spec uri_to_path(String.t()) :: String.t() | nil
  def uri_to_path("file://" <> rest), do: URI.decode(rest)
  def uri_to_path(_), do: nil

  @spec path_to_uri(String.t()) :: String.t()
  def path_to_uri(path), do: "file://" <> URI.encode(path)

  @spec apply_notification(t(), atom() | String.t(), map() | nil) :: t()
  def apply_notification(%__MODULE__{} = state, method, params) do
    state
    |> apply_text_sync(method, params)
    |> apply_workspace_sync(method, params)
  end

  @spec apply_text_sync(t(), atom() | String.t(), map() | nil) :: t()
  def apply_text_sync(%__MODULE__{} = state, :text_document_did_open, %{
        "textDocument" => %{"uri" => uri, "text" => text} = doc
      }) do
    open_document(state, uri, text, Map.get(doc, "version"), Map.get(doc, "languageId"))
  end

  def apply_text_sync(%__MODULE__{} = state, :text_document_did_change, %{
        "textDocument" => %{"uri" => uri} = text_document,
        "contentChanges" => changes
      })
      when is_list(changes) do
    case get_document(state, uri) do
      nil ->
        lifecycle_mismatch(state, :did_change_without_open, %{uri: uri})

      doc ->
        next_text = Enum.reduce(changes, doc.text, &apply_change/2)
        version = Map.get(text_document, "version", doc.version)
        put_in(state.documents[uri], %{doc | text: next_text, version: version})
    end
  end

  def apply_text_sync(%__MODULE__{} = state, :text_document_did_close, %{
        "textDocument" => %{"uri" => uri}
      }) do
    if get_document(state, uri) do
      close_document(state, uri)
    else
      lifecycle_mismatch(state, :did_close_without_open, %{uri: uri})
    end
  end

  def apply_text_sync(%__MODULE__{} = state, _method, _params), do: state

  defp apply_workspace_sync(%__MODULE__{} = state, :workspace_did_change_workspace_folders, %{
         "event" => event
       }) do
    added = Map.get(event, "added", [])
    removed = Map.get(event, "removed", [])

    removed_uris = MapSet.new(Enum.map(removed, & &1["uri"]))

    kept =
      Enum.reject(state.workspace_folders, fn folder ->
        MapSet.member?(removed_uris, folder["uri"])
      end)

    %{state | workspace_folders: kept ++ added}
  end

  defp apply_workspace_sync(%__MODULE__{} = state, _method, _params), do: state

  defp lifecycle_mismatch(%__MODULE__{mode: :lenient} = state, _reason, _meta), do: state

  defp lifecycle_mismatch(%__MODULE__{mode: :strict}, reason, meta) do
    raise ArgumentError,
          "LSP lifecycle mismatch #{inspect(reason)}: #{inspect(meta)}"
  end

  defp apply_change(%{"text" => text} = change, original) do
    case Map.get(change, "range") do
      nil ->
        text

      %{"start" => s, "end" => e} ->
        {start_idx, end_idx} = {position_to_index(original, s), position_to_index(original, e)}
        prefix = String.slice(original, 0, start_idx)
        suffix = String.slice(original, end_idx, String.length(original) - end_idx)
        prefix <> text <> suffix
    end
  end

  defp position_to_index(text, %{"line" => line, "character" => character}) do
    lines = String.split(text, "\n", trim: false)

    prefix_len =
      lines
      |> Enum.take(line)
      |> Enum.map(&(String.length(&1) + 1))
      |> Enum.sum()

    line_text = Enum.at(lines, line, "")
    prefix_len + min(character, String.length(line_text))
  end
end
