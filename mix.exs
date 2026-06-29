defmodule DSL.MixProject do
  use Mix.Project

  def project do
    [
      app: :dsl,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      docs: docs(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:ex_unit]],
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [ci: :test]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.14"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.0", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Composable building blocks for Elixir-native DSLs."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/elixir-vibe/dsl"},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE SKILL.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/elixir-vibe/dsl",
      extras: ["README.md", "CHANGELOG.md", "SKILL.md"],
      groups_for_extras: [Guides: ["SKILL.md"]]
    ]
  end

  defp aliases() do
    [
      ci: [
        "format",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test",
        "credo --strict",
        "dialyzer",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells"
      ]
    ]
  end
end
