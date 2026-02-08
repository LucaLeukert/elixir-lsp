defmodule ElixirLsp.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_lsp,
      version: "0.1.0",
      description: "Protocol-focused LSP building blocks for Elixir",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ElixirLsp.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"}
    ]
  end
end
