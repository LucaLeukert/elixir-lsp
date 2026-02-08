defmodule ElixirLsp.Method do
  @moduledoc """
  LSP method registry and conversion helpers.

  Native Elixir code can use snake_case atoms, while wire format uses official
  LSP method strings.
  """

  @methods [
    initialize: "initialize",
    initialized: "initialized",
    shutdown: "shutdown",
    exit: "exit",
    cancel_request: "$/cancelRequest",
    progress: "$/progress",
    set_trace: "$/setTrace",
    log_trace: "$/logTrace",
    telemetry_event: "telemetry/event",
    window_show_message: "window/showMessage",
    window_show_message_request: "window/showMessageRequest",
    window_show_document: "window/showDocument",
    window_log_message: "window/logMessage",
    window_work_done_progress_create: "window/workDoneProgress/create",
    window_work_done_progress_cancel: "window/workDoneProgress/cancel",
    client_register_capability: "client/registerCapability",
    client_unregister_capability: "client/unregisterCapability",
    workspace_workspace_folders: "workspace/workspaceFolders",
    workspace_did_change_workspace_folders: "workspace/didChangeWorkspaceFolders",
    workspace_did_change_configuration: "workspace/didChangeConfiguration",
    workspace_did_change_watched_files: "workspace/didChangeWatchedFiles",
    workspace_symbol: "workspace/symbol",
    workspace_symbol_resolve: "workspaceSymbol/resolve",
    workspace_execute_command: "workspace/executeCommand",
    workspace_apply_edit: "workspace/applyEdit",
    workspace_configuration: "workspace/configuration",
    workspace_code_lens_refresh: "workspace/codeLens/refresh",
    workspace_semantic_tokens_refresh: "workspace/semanticTokens/refresh",
    workspace_inlay_hint_refresh: "workspace/inlayHint/refresh",
    workspace_inline_value_refresh: "workspace/inlineValue/refresh",
    workspace_diagnostic: "workspace/diagnostic",
    workspace_diagnostic_refresh: "workspace/diagnostic/refresh",
    workspace_will_create_files: "workspace/willCreateFiles",
    workspace_did_create_files: "workspace/didCreateFiles",
    workspace_will_rename_files: "workspace/willRenameFiles",
    workspace_did_rename_files: "workspace/didRenameFiles",
    workspace_will_delete_files: "workspace/willDeleteFiles",
    workspace_did_delete_files: "workspace/didDeleteFiles",
    text_document_publish_diagnostics: "textDocument/publishDiagnostics",
    text_document_did_open: "textDocument/didOpen",
    text_document_did_change: "textDocument/didChange",
    text_document_will_save: "textDocument/willSave",
    text_document_will_save_wait_until: "textDocument/willSaveWaitUntil",
    text_document_did_save: "textDocument/didSave",
    text_document_did_close: "textDocument/didClose",
    text_document_completion: "textDocument/completion",
    completion_item_resolve: "completionItem/resolve",
    text_document_hover: "textDocument/hover",
    text_document_signature_help: "textDocument/signatureHelp",
    text_document_declaration: "textDocument/declaration",
    text_document_definition: "textDocument/definition",
    text_document_type_definition: "textDocument/typeDefinition",
    text_document_implementation: "textDocument/implementation",
    text_document_references: "textDocument/references",
    text_document_document_highlight: "textDocument/documentHighlight",
    text_document_document_symbol: "textDocument/documentSymbol",
    text_document_code_action: "textDocument/codeAction",
    code_action_resolve: "codeAction/resolve",
    text_document_code_lens: "textDocument/codeLens",
    code_lens_resolve: "codeLens/resolve",
    text_document_document_link: "textDocument/documentLink",
    document_link_resolve: "documentLink/resolve",
    text_document_document_color: "textDocument/documentColor",
    text_document_color_presentation: "textDocument/colorPresentation",
    text_document_formatting: "textDocument/formatting",
    text_document_range_formatting: "textDocument/rangeFormatting",
    text_document_ranges_formatting: "textDocument/rangesFormatting",
    text_document_on_type_formatting: "textDocument/onTypeFormatting",
    text_document_rename: "textDocument/rename",
    text_document_prepare_rename: "textDocument/prepareRename",
    text_document_folding_range: "textDocument/foldingRange",
    text_document_selection_range: "textDocument/selectionRange",
    text_document_prepare_call_hierarchy: "textDocument/prepareCallHierarchy",
    call_hierarchy_incoming_calls: "callHierarchy/incomingCalls",
    call_hierarchy_outgoing_calls: "callHierarchy/outgoingCalls",
    text_document_semantic_tokens_full: "textDocument/semanticTokens/full",
    text_document_semantic_tokens_full_delta: "textDocument/semanticTokens/full/delta",
    text_document_semantic_tokens_range: "textDocument/semanticTokens/range",
    text_document_linked_editing_range: "textDocument/linkedEditingRange",
    text_document_moniker: "textDocument/moniker",
    text_document_prepare_type_hierarchy: "textDocument/prepareTypeHierarchy",
    type_hierarchy_supertypes: "typeHierarchy/supertypes",
    type_hierarchy_subtypes: "typeHierarchy/subtypes",
    text_document_inline_value: "textDocument/inlineValue",
    text_document_inlay_hint: "textDocument/inlayHint",
    inlay_hint_resolve: "inlayHint/resolve",
    text_document_diagnostic: "textDocument/diagnostic",
    notebook_document_did_open: "notebookDocument/didOpen",
    notebook_document_did_change: "notebookDocument/didChange",
    notebook_document_did_save: "notebookDocument/didSave",
    notebook_document_did_close: "notebookDocument/didClose"
  ]

  @native_to_wire Map.new(@methods)
  @wire_to_native Map.new(@methods, fn {native, wire} -> {wire, native} end)

  @type native_method :: atom()
  @type method :: native_method() | String.t()

  @spec all_native() :: [native_method()]
  def all_native, do: Keyword.keys(@methods)

  @spec all_wire() :: [String.t()]
  def all_wire, do: Keyword.values(@methods)

  @spec known?(method()) :: boolean()
  def known?(method) when is_atom(method), do: Map.has_key?(@native_to_wire, method)
  def known?(method) when is_binary(method), do: Map.has_key?(@wire_to_native, method)

  @spec to_wire(method()) :: String.t()
  def to_wire(method) when is_atom(method) do
    Map.fetch!(@native_to_wire, method)
  end

  def to_wire(method) when is_binary(method), do: method

  @spec to_native(String.t()) :: native_method() | String.t()
  def to_native(method) when is_binary(method) do
    Map.get(@wire_to_native, method, method)
  end
end
