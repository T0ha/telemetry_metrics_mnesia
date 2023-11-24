defmodule TelemetryMetricsMnesia.Cleaner do
  @moduledoc false

  use GenServer

  require Logger

  alias TelemetryMetricsMnesia.Db

  @cleanup_timeout Application.compile_env(:telemetry_metrics_mnesia, :cleanup_timeout, 10) * 1000
  @max_storage_time Application.compile_env(:telemetry_metrics_mnesia, :max_storage_time, 0)

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    case @max_storage_time do
      0 ->
        :ignore

      _ ->
        Logger.info("Strting DB cleanup with @max_storage_time = #{@max_storage_time} sec")
        {:ok, %{}, @cleanup_timeout}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.debug("Strting DB cleanup")

    timestamp =
      System.os_time(:microsecond) - @max_storage_time * 1_000_000

    Db.clean(timestamp)
    {:noreply, state, @cleanup_timeout}
  end

  def handle_info(_, state), do: {:noreply, state, @cleanup_timeout}
end
