defmodule TelemetryMetricsMnesia.MixProject do
  use Mix.Project

  @version (case File.read("VERSION") do
    {:ok, version} -> String.trim(version)
    {:error, _} -> "0.0.0-development"
  end)

  def project do
    [
      app: :telemetry_metrics_mnesia,
      version: @version,
      description: description(),
      package: package(),
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: "https://github.com/T0ha/telemetry_metrics_mnesia"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia]
    ]
  end

  defp description() do
    """
    `Telemetry.Metrics` reporter and metrics backend based on Mnesia DB. 
    """
  end

  defp package() do
    %{
      licenses: ["GPL-3.0-only"],
      files: ["lib", "README.md", "mix.exs", "VERSION"],
      links: %{
        "GitHub" => "https://github.com/T0ha/telemetry_metrics_mnesia"
      }
    }
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry_metrics, "~> 0.6"},
      {:explorer, "~> 0.7"},

      # Code quality and docs
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.8", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false}
    ]
  end
end
