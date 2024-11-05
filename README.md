# TelemetryMetricsMnesia

[![CI Tests pass](https://github.com/t0ha/telemetry_metrics_mnesia/actions/workflows/push.yml/badge.svg)](https://github.com/t0ha/telemetry_metrics_mnesia/actions/workflows/push.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/telemetry_metrics_mnesia)](https://hex.pm/packages/telemetry_metrics_mnesia)

`Telemetry.Metrics` reporter and metrics backend based on Mnesia DB. 

## Features
- Full compatibility with `Telemetry.Metrics` specification.
- Supports distribution between BEAM nodes.
- In-memory and persistant data storage modes.
- Custom metric aggregaaion support.
- Has no external non-beam dependences.

## Installation

Just add the reporter to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:telemetry_metrics_mnesia, "~> 0.1.0"}
  ]
end
```

## Configuration

You can configure optional cleanup process. Add the following to your `config.exs`:

```elixir
import Config

config :telemetry_metrics_mnesia,
    # Timeout between cleanup process invocations in seconds, default 10.
    cleanup_timeout: 10,

    # Max telemetry events age to store in seconds (0 means infinity), default 0.
    max_storage_time: 5
```

When `max_storage_time` is zero cleanup process doesn't start.


## Usage

To use it, start the reporter with the `start_link/1` function, providing it a list of
`Telemetry.Metrics` metric definitions:

```elixir
import Telemetry.Metrics

alias Telemetry.Metrics.Counter
alias Telemetry.Metrics.Distribution
alias Telemetry.Metrics.LastValue
alias Telemetry.Metrics.Sum
alias Telemetry.Metrics.Summary

TelemetryMetricsMnesia.start_link(
  metrics: [
    counter("http.request.count"),
    sum("http.request.payload_size"),
    last_value("vm.memory.total")
  ]
)
```

or put it under a supervisor:

```elixir
import Telemetry.Metrics

children = [
  {TelemetryMetricsMnesia, [
    metrics: [
      counter("http.request.count"),
      sum("http.request.payload_size"),
      last_value("vm.memory.total")
    ]
  ]}
]

Supervisor.start_link(children, ...)
```

By default the reporter uses in-memory storage without distribution.

### Getting metrics values
There is a unified API for retrieving metrics data.
Use `TelemetryMetricsMnesia.fetch(metric_name, opts)` to do it:

```elixir
alias TelemetryMetricsMnesia, as: Metrics

# Simple metrics
%{Counter => request_count} = Metrics.fetch([:http, :request, :count])
%{Counter => request_count_per_minute} = Metrics.fetch([:http, :request, :count], granularity: [minites: 1])

%{Sum => total_requests_size} = Metrics.fetch([:http, :request, :payload_size])
%{Sum => request_size_per_second} = Metrics.fetch([:http, :request, :count], granularity: [:seconds, 1])


%{LastValue => total_memory} = Metrics.fetch([:vm, :memory, :total])

# Complex metrics

%{
    Distribution => %{
        median: median,
        p75: p7_5,
        p90: p9_0,
        p95: p9_5,
        p99: p99
    }
} = TelemetryMetricsMnesia.fetch([:http, :request, :duration])

%{
    Summary => %{
        mean: avg,
        variance: var,
        standard_deviation: sd,
        median: median,
        count: count
    }
} = TelemetryMetricsMnesia.fetch([:http, :request, :duration])

# Multiple metrics with the same name

%{
    Distribution => %{
        median: median,
        p75: p7_5,
        p90: p9_0,
        p95: p9_5,
        p99: p99
    },
    Summary => %{
        mean: avg,
        variance: var,
        standard_deviation: sd,
        median: median,
        count: count
    }
} = TelemetryMetricsMnesia.fetch([:http, :request, :duration])

# Metric with tags
# Strated as `counter("http.request.count", tags: [:endpoint, :code])`

%{
    Counter => %{
        %{endpoint: "/", code: 200} => app_requests_success,
        %{endpoint: "/", code: 500} => app_requests_server_fail,
        %{endpoint: "/api", code: 200} => api_requests_success
    }
} = TelemetryMetricsMnesia.fetch([:http, :request, :counter])
```


## Copyright and License

TelemetryMetricsMnesia is copyright (c) 2023 Anton Shvein.

TelemetryMetricsMnesia source code is released under MIT license.

See [LICENSE](LICENSE) for more information.
