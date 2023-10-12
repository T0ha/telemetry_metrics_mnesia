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
      {:telemetry_metrics, "~> 0.6"}
    ]
  end
end
