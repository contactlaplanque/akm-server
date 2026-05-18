# akm-server config paths

`akm-server` now expects explicit config file paths at launch.

Recommended invocation from the akM root:

```bash
sclang "akm-server/bootstrap.scd" -- "packages/akm-config/venues/main/layout.json" "packages/akm-config/venues/main/server.json"
```

The canonical config source of truth is `packages/akm-config`.
