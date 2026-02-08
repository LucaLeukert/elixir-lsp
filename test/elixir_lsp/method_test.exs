defmodule ElixirLsp.MethodTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.Method

  test "converts known native method atoms to wire strings" do
    assert Method.to_wire(:initialize) == "initialize"
    assert Method.to_wire(:text_document_completion) == "textDocument/completion"
    assert Method.to_wire(:workspace_diagnostic_refresh) == "workspace/diagnostic/refresh"
  end

  test "converts known wire strings to native atoms" do
    assert Method.to_native("initialize") == :initialize
    assert Method.to_native("textDocument/didOpen") == :text_document_did_open
  end

  test "passes through unknown wire methods" do
    assert Method.to_native("custom/serverMethod") == "custom/serverMethod"
  end
end
