defmodule TelemetryMetricsMnesia.MixProject do
  use Mix.Project

  def project do
    [
      app: :telemetry_metrics_mnesia,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia]
    ]
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
