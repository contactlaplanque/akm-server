# akm-server

Realtime spatial audio server for the akM toolchain, built with SuperCollider.

## Architecture

`akm-server` is now booted through a modular entrypoint:

- `bootstrap.scd` (entrypoint)
- `lib/00_config.scd` (JSON loading + validation)
- `lib/01_server_options.scd` (SC server options from config)
- `lib/02_buses.scd` (all control/audio buses)
- `lib/03_synthdefs.scd` (DSP graph definitions)
- `lib/04_groups.scd` (execution order)
- `lib/05_synths.scd` (instance creation)
- `lib/06_osc.scd` (OSC API v3: setters + heartbeat + perf + meters + 20 Hz change-driven `/state/*` + `/event/*`)
- `lib/07_util.scd` (helpers)

> **v3 migration note** — the group EQ went from 5 bands to 3 parametric peaks (no shelves; the per-role group filter handles broad shaping). Any `lowShelf` / `highShelf` blocks in `packages/akm-config/venues/main/server.json` are ignored on load and stripped on the next save. If you relied on shelves, fold their effect into the group filter or the peaks before upgrading. See `packages/akm-config/docs/osc.md` for the v3 OSC API.

The legacy monolithic script `akM_spatServer.scd` is kept as historical reference only.

## Configuration

Config is externalized in JSON and shared from `packages/akm-config`:

- `packages/akm-config/venues/main/layout.json`
- `packages/akm-config/venues/main/server.json`

Launch command from repository root:

```bash
sclang "akm-server/bootstrap.scd" -- "packages/akm-config/venues/main/layout.json" "packages/akm-config/venues/main/server.json"
```

## Local OSC smoke test

From repository root:

```bash
pnpm run test:osc-smoke
```

What it checks:

- server reaches `AKM SERVER READY`
- ACK round-trips for core OSC endpoints
- at least one heartbeat + source state packet is received
- `/akm/server/quit` returns ACK and exits cleanly

Troubleshooting:

- Ensure SuperCollider is installed and `sclang` is available at `/Applications/SuperCollider.app/Contents/MacOS/sclang` or override with `AKM_SCLANG_BIN`.
- If ports are in use, set `AKM_SERVER_CONFIG_PATH` to a config with free OSC listen/reply ports.
- Use `AKM_SMOKE_VERBOSE=1` to print all OSC send/receive traffic during the test.

## Speaker model (default venue)

- 36 satellites (`satellite`)
- 4 low-medium subs (`sub_mid`)
- 2 low-frequency subs (`sub_lf`)
- 42 output channels with explicit `outputChannel` mapping

## DSP pipeline summary

Per source:

1. `\spatPannerSource` computes gains + delays for three independent pools:
   - satellites
   - sub_mid
   - sub_lf
2. `\inputAudioProcessor` reads `SoundIn`, applies distance attenuation and squared delay law, writes dry/wet buses.

Global:

1. `\satReverbFX` and `\subMidReverbFX`
2. Group filter + EQ synths:
   - `\groupSatFilterEq`
   - `\groupSubMidFilterEq`
   - `\groupSubLfFilterEq`
3. `\outputRouter` applies per-speaker gains + system gain and routes to hardware outputs.

## OSC API v2

All paths start with `/akm/`.

See full contract in:

- `packages/akm-config/docs/osc.md`

Core paths:

- `/akm/source/{sourceId}/params`
- `/akm/speaker/{speakerId}/gain`
- `/akm/group/{role}/eq`
- `/akm/group/{role}/filter`
- `/akm/system/reverb`
- `/akm/system/gain`
- `/akm/server/quit`

Outbound:

- `/akm/server/ack/...`
- `/akm/server/heartbeat`
- `/akm/server/meters`
- `/akm/server/state/source/{sourceId}`

## Runtime prerequisites

- SuperCollider 3.12+
- SC3 plugins
- JSONlib quark (`Quarks.install("JSONlib")`) — config loading uses `JSONlib.parseFile`

## CPU profiling checklist (M4/M5)

Use this after booting the 42-channel config:

1. In Activity Monitor, observe `scsynth` and `sclang` CPU while sources are moving.
2. Trigger simultaneous source updates (32 sources) and watch sustained CPU for 5+ minutes.
3. Confirm no XRuns/dropouts at target sample rate.
4. Tune `telemetry.stateBroadcastHz` and `telemetry.metersHz` in `server.json` if needed.

## License

GNU GPLv3.
