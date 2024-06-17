defmodule TelemetryMetricsMnesia.EventHandler do
  @moduledoc false

  use GenServer, 
    restart: :permanent

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
  def handle_event(event, measurements, metadata, metrics) do
    # Logger.debug(
    #   ~c"handle_event(#{inspect(event)}, #{inspect(measurements)}, #{inspect(metadata)}, #{inspect(metrics)})"
    # )

    GenServer.call(__MODULE__, {:event, event, measurements, metadata, metrics})

    :ok
  end

  def start_link(_), do:
    GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_), do: {:ok, true}

  @impl true
  def handle_call({:event, event, measurements, metadata, metrics},_,  _) do
      Db.write_event(event, measurements, metadata, metrics)

    #  for metric <- metrics, do:
    #    Db.calculate(metric)
    {:reply, :ok, true}
  end
end
