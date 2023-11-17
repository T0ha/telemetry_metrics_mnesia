defmodule TelemetryMetricsMnesia.EventHandler do
  @moduledoc false

  require Logger
  require Record

  alias TelemetryMetricsMnesia.Db

  @type metrics() :: [Telemetry.Metrics.t()]

  @spec attach(metrics) :: [:telemetry.handler_id()]
  def attach(metrics) do
    # Logger.info("metrics: #{inspect(metrics)}")

    for {event, metrics} <- Enum.group_by(metrics, & &1.event_name) do
      id = {__MODULE__, event, self()}
      :telemetry.attach(id, event, &__MODULE__.handle_event/4, metrics)
      id
    end
  end

  @spec detach([:telemetry.handler_id()]) :: :ok
  def detach(handler_ids) do
    for handler_id <- handler_ids do
      :telemetry.detach(handler_id)
    end

    :ok
  end

  @spec handle_event(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          metrics()
        ) :: :ok | {:error, any()}
  def handle_event(event, measurements, metadata, _metrics) do
    # Logger.debug(
    #   ~c"handle_event(#{inspect(event)}, #{inspect(measurements)}, #{inspect(metadata)}, _)"
    # )

    Db.write_event(event, measurements, metadata)
  end
end
