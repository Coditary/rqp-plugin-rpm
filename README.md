# reqpack-plugin-rpm

ReqPack wrapper for `rpm` with optional `dnf` or `yum` fallback for repository-backed operations.

## Behavior

- `rpm` is required.
- `dnf` is preferred optional helper for repo install, search, info, and outdated checks.
- `yum` is used when `dnf` is not available.
- local `.rpm` artifacts use `rpm -Uvh` directly.
- removals use `rpm -e` directly.
- read operations emit structured ReqPack package info and transaction progress.

## Supported Paths

- `install`: repo package names through `dnf` or `yum`
- `installLocal`: local `.rpm` files through `rpm`
- `remove`: installed packages through `rpm`
- `update`: repo-backed updates through `dnf` or `yum`
- `list`: installed packages through `rpm -qa`
- `search`: repo search through `dnf` or `yum`
- `info`: installed package info via `rpm -qi`, fallback to `dnf info` or `yum info`
- `outdated`: repo update check through `dnf check-update` or `yum check-update`

If no repo helper exists, `search()` and `outdated()` return empty results, while named-package `install()` and `update()` fail explicitly.

## Files

- `run.lua`: main wrapper logic
- `metadata.json`: bundle metadata
- `reqpack.lua`: ReqPack manifest
- `.reqpack-test/core/*.lua`: hermetic conformance cases

## Testing

Run core plugin tests from repository root:

```bash
rqp test-plugin --plugin . --preset core
```

Run one case directly:

```bash
rqp test-plugin --plugin . --case ./.reqpack-test/core/info.lua
```

## Notes

- wrapper stays thin and defers real package work to system tools
- parser is conservative and skips malformed lines instead of crashing whole read action
- returned package info keeps ReqPack-friendly fields such as `packageId`, `status`, `installed`, and `packageType`
