defmodule TelemetryMetricsMnesia.Supervisor do
  @moduledoc false
  use Supervisor

  def init(options) do
    children = [
      TelemetryMetricsMnesia.EventHandler,
      {TelemetryMetricsMnesia.Worker, options},
      TelemetryMetricsMnesia.Cleaner
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
