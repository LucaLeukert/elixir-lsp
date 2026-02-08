defmodule ElixirLsp.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/LucaLeukert/elixir-lsp"

  def project do
    [
      app: :elixir_lsp,
      version: @version,
      description: description(),
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "ElixirLsp"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ElixirLsp.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:nimble_options, "~> 1.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Elixir-native, protocol-focused Language Server Protocol toolkit."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "HexDocs" => "https://hexdocs.pm/elixir_lsp"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
