for module <- [
      ElixirLsp.Message.Request,
      ElixirLsp.Message.Notification,
      ElixirLsp.Message.Response,
      ElixirLsp.Message.ErrorResponse,
      ElixirLsp.Message.Error,
      ElixirLsp.Types.Position,
      ElixirLsp.Types.Range,
      ElixirLsp.Types.Diagnostic,
      ElixirLsp.Types.TextEdit,
      ElixirLsp.Types.WorkspaceEdit,
      ElixirLsp.Types.CodeAction
    ] do
  defimpl Inspect, for: module do
    import Inspect.Algebra
    @impl_module module

    def inspect(struct, opts) do
      concat([
        "#",
        to_doc(@impl_module, opts),
        "<",
        to_doc(Map.from_struct(struct), opts),
        ">"
      ])
    end
  end

  defimpl String.Chars, for: module do
    def to_string(struct), do: inspect(struct)
  end
end
