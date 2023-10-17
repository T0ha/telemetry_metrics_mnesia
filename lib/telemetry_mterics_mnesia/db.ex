defmodule TelemetryMetricsMnesia.Db do
  @moduledoc false

  require Logger
  require Record

  alias :mnesia, as: Mnesia

  Record.defrecord(:telemetry_events, key: {[], nil}, measurements: %{}, metadata: %{})

  @type t() :: record(:telemetry_events, key: {Telemetry.event_name(), non_neg_integer()}, measurements:
  Telemetry.event_measurements(), metadata: Telemetry.event_metadata())

  def write_event(event, measurements, metadata) do
    transaction = fn() ->
      timestamp = System.os_time(:microsecond)
      Mnesia.write(telemetry_events(key: {timestamp, event}, measurements: measurements, metadata: metadata))
    end

    case Mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        :ok
      {:aborted, reason} ->
        Logger.warning("Event #{inspect event} was not written to DB with reason: #{reason}")
        {:error, reason}
    end
  end

  def init() do
    Mnesia.create_table(:telemetry_events, attributes: [:event, :measurements, :metadata], type:
      :ordered_set)
  end

  def fetch(%Telemetry.Metrics.Counter{event_name: event_name}) do
    telemetry_events(key: {:_, event_name})
    |> Mnesia.dirty_match_object()
    |> length()
  end

  def fetch(%Telemetry.Metrics.Sum{event_name: event_name} = metric) do
    fn ->
      Mnesia.match_object(:telemetry_events, telemetry_events(key: {:_, event_name}), :read)
    end
    |> Mnesia.transaction()
    |> elem(1)
    |> Enum.reduce(0, fn event, acc ->
      event
      |> telemetry_events(:measurements)
      |> extract_measurement(metric)
      |> Kernel.+(acc)
    end)
  end

  def fetch(%Telemetry.Metrics.LastValue{event_name: event_name}) do
    :notimpl
  end


  def fetch(_), do: :notimpl

  defp extract_measurement(measurements, metric) do
    case metric.measurement do
      fun when is_function(fun, 1) -> fun.(measurements)
      key -> measurements[key]
    end
  end
end
