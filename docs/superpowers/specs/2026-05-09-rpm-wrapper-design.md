# RPM Wrapper Design

## Goal

Build ReqPack wrapper for RPM-based systems that stays as standalone as possible.
`rpm` is hard dependency.
`dnf` or `yum` are optional fallbacks only for repo-driven features that `rpm` cannot provide well enough on its own.
Wrapper must also emit ReqPack-friendly structured results and progress signals so display/output layers can show action and parse progress correctly.

## Scope

- Replace template metadata and runtime placeholders with real RPM wrapper behavior.
- Support installed-package queries through `rpm`.
- Support local RPM artifact installs through `installLocal()`.
- Support package removal through `rpm`.
- Support repo-backed package install, search, info, and outdated checks through `dnf` or `yum` only when needed.
- Keep parsing deterministic and small.
- Report parser progress in ReqPack-compatible way for long-running read operations.

## Non-Goals

- No new hard dependency beyond `rpm`.
- No direct Python dependency check.
- No advanced solver logic inside wrapper.
- No custom repository management.
- No exact version resolution beyond best-effort `name-version` tokens for repo commands.
- No v1 dependency on undocumented rich `context.tx.progress(...)` payload shape; numeric progress is enough unless real plugin examples require more.

## Runtime Capability Model

### Required binary

- `rpm`

### Optional binaries

- `dnf`
- `yum`

### Preference order

1. `dnf`
2. `yum`
3. no repo helper

## Architecture

Wrapper remains thin in `run.lua`.
Implementation uses small local helpers only.

Planned helpers:

- `tx_status(context, value)`
- `tx_progress(context, value)`
- `trim(value)`
- `shell_quote(value)`
- `command_exists(binary)`
- `get_repo_helper()`
- `run(context, command)`
- `is_installed(context, name)`
- `package_token(pkg)`
- `make_package_id(name, architecture)`
- `split_name_arch(token)`
- `update_parse_progress(context, done, total)`
- `parse_rpm_list(stdout)`
- `parse_info_block(stdout)`
- `parse_search_output(stdout)`
- `parse_check_update(stdout)`
- `emit_event(context, name, payload)`
- `begin_step(context, label)`
- `tx_success(context)`
- `tx_failed(context, message)`

`get_repo_helper()` picks `dnf` first, then `yum`, else `nil`.
Helper choice is cached after first probe.

`plugin.init()` checks only `rpm`.
Repo helper is optional and is not required for plugin startup.

`plugin.fileExtensions` should be set to `{ ".rpm" }`.

## ReqPack Display And Output Rules

- Inside action methods, prefer `context.exec.run(...)` over `reqpack.exec.run(...)` so ReqPack can correlate command execution with current action and output.
- `reqpack.exec.run(...)` is still acceptable in `plugin.init()` and `getMissingPackages()` because those methods do not receive `context`.
- Emit domain events once per completed method result, not per parsed line.
- Return same final data shape that event payload carries.
- Use ReqPack `PackageInfo` fields only when value is reliable from source output.
- Keep compatibility field `type = "package"` in returned items.
- Also populate `packageType = "rpm"` where useful for structured output.

### Progress rules

- For mutating actions, emit `context.tx.begin_step(...)` before command execution.
- For long-running read actions (`list`, `search`, `info`, `outdated`), emit `context.tx.begin_step(...)` before running command and use parse progress while converting stdout into `PackageInfo` records.
- Use numeric `context.tx.progress(percent)` in v1.
- Use numeric `context.tx.status(parsedCount)` as simple parsed-item counter.
- When total parseable records are known, call `progress(0)` before parsing, update during parsing, then `progress(100)` after payload is complete.
- When total parseable records are not known up front, call `status(parsedCount)` during parsing and set `progress(100)` only after final payload is built.
- Throttle progress updates so wrapper does not spam ReqPack: update on first item, last item, and whenever percentage changes by at least 5 points or parsed count increases by 25 items.
- Do not emit partial `listed`, `searched`, `informed`, or `outdated` events while parsing. Emit only final payload.

### Structured result rules

- `list()` items should include at least: `name`, `packageId`, `version`, `installed = true`, `status = "installed"`, `type = "package"`, `packageType = "rpm"`, `architecture`, `summary`.
- `search()` items should include at least: `name`, `packageId`, `status = "available"`, `type = "package"`, `packageType = "rpm"`, optional `architecture`, `summary`.
- `info()` should include best-effort: `name`, `packageId`, `version`, `installed`, `status`, `type = "package"`, `packageType = "rpm"`, `architecture`, `summary`, `description`, `license`, `repository`, `extraFields` for any source-specific leftovers.
- `outdated()` items should include at least: `name`, `packageId`, `installed = true`, `status = "outdated"`, `version` when cheaply known, `latestVersion`, `type = "package"`, `packageType = "rpm"`, optional `architecture`, `repository` or `extraFields.repository`.
- If architecture exists, `packageId` should be `<name>.<arch>`. Otherwise use `name`.

## Method Behavior

### `getName()`, `getVersion()`, `getCategories()`

- Change metadata from template to RPM-specific values.
- Categories should identify wrapper as Linux RPM package manager integration.

### `getRequirements()`

- Return `{}`.
- No ReqPack-side dependency needed for wrapper runtime.

### `getMissingPackages(packages)`

Behavior depends on `pkg.action`.

- `install`: keep packages not currently installed according to `rpm -q --quiet <name>`.
- `remove`: keep packages that are currently installed.
- `update`:
  - if `dnf` or `yum` exists, run repo outdated query once and keep only requested packages that appear in result.
  - if no repo helper exists, keep requested packages that are installed and let `update()` decide support.

This keeps install/remove planning accurate and update planning useful without inventing solver logic.

### `install(context, packages)`

Purpose: install named packages from configured repositories.

Behavior:

- If package list is empty, return `true`.
- Start transaction step.
- Resolve repo helper.
- If no repo helper exists, mark transaction failed and return `false`.
- Call `context.tx.progress(0)` after helper resolution succeeds.
- Build single repo command:
  - `dnf install -y <tokens...>`
  - `yum install -y <tokens...>`
- Run command through `context.exec.run(...)`.
- Call `context.tx.progress(85)` after successful command.
- Emit `installed` event with requested packages on success.
- Call `context.tx.progress(100)` before finishing.
- Call `tx_success()` on success.

Token rules:

- default token is package name
- if `pkg.version` exists, use best-effort `<name>-<version>` token

Reason: repo installs need dependency solving; `rpm` alone does not handle that safely.

### `installLocal(context, path)`

Purpose: install or upgrade local RPM artifact with no repo helper.

Behavior:

- If path is empty, fail.
- Start transaction step.
- Call `context.tx.progress(0)` before command.
- Run `rpm -Uvh <path>`.
- Call `context.tx.progress(90)` after successful command.
- Emit `installed` event with `{ path = path, localTarget = true }` on success.
- Call `context.tx.progress(100)` before finishing.
- Call `tx_success()` on success.

Reason: local RPM handling is native `rpm` responsibility and should not require `dnf` or `yum`.

### `remove(context, packages)`

Behavior:

- If package list is empty, return `true`.
- Start transaction step.
- Call `context.tx.progress(0)` before command.
- Run `rpm -e <names...>`.
- Call `context.tx.progress(90)` after successful command.
- Emit `deleted` event with requested packages on success.
- Call `context.tx.progress(100)` before finishing.
- Call `tx_success()` on success.

### `update(context, packages)`

Purpose: update named installed packages from repositories.

Behavior:

- If package list is empty, return `true`.
- Start transaction step.
- Resolve repo helper.
- If no repo helper exists, mark transaction failed and return `false`.
- Call `context.tx.progress(0)` after helper resolution succeeds.
- Run repo command:
  - `dnf upgrade -y <tokens...>`
  - `yum update -y <tokens...>`
- Run command through `context.exec.run(...)`.
- Call `context.tx.progress(85)` after successful command.
- Emit `updated` event with requested packages on success.
- Call `context.tx.progress(100)` before finishing.
- Call `tx_success()` on success.

Local artifact upgrades stay in `installLocal()` through `rpm -Uvh`.

### `list(context)`

Behavior:

- Run `rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{SUMMARY}\n'`.
- Run command through `context.exec.run(...)`.
- Filter empty lines first so total parseable records is known.
- Call `context.tx.progress(0)` before parsing.
- Parse each line into:
  - `name`
  - `packageId`
  - `version`
  - `installed = true`
  - `status = "installed"`
  - `packageType = "rpm"`
  - `architecture`
  - `summary`
  - `type = "package"`
- Update `context.tx.status(parsedCount)` and `context.tx.progress(percent)` while parsing.
- Set `context.tx.progress(100)` after parse completes.
- Emit `listed` event with parsed items.
- Return parsed items.

### `search(context, prompt)`

Behavior:

- If prompt is empty, return empty list.
- Resolve repo helper.
- If no repo helper exists, emit `searched` with empty list and return empty list.
- Run:
  - `dnf search <prompt>`
  - or `yum search <prompt>`
- Run command through `context.exec.run(...)`.
- Ignore non-result lines such as `Loaded plugins:`, `Last metadata expiration check:`, match headers, separator-only lines, and blank lines.
- Count candidate result lines first, then call `context.tx.progress(0)`.
- Parse result lines that look like `name.arch : summary`.
- Return package items with:
  - `name`
  - `packageId`
  - `status = "available"`
  - `packageType = "rpm"`
  - `architecture` when present
  - `summary`
  - `type = "package"`
- Update `context.tx.status(parsedCount)` and `context.tx.progress(percent)` while parsing.
- Set `context.tx.progress(100)` after parse completes.
- Emit `searched` event.

### `info(context, packageName)`

Behavior:

1. Try installed-package info first through `rpm -qi <name>`.
2. If installed query succeeds, parse block fields:
   - `Name`
   - `Version`
   - `Release`
   - `Architecture`
   - `Summary`
   - `License`
   - `Description`
3. If installed query fails, resolve repo helper.
4. If repo helper exists, run:
   - `dnf info <name>`
   - or `yum info <name>`
5. Parse same field family from text block plus `Repo` when present.
6. If nothing usable found, emit `unavailable` for package and return `nil`.
7. Emit `informed` event for successful result.

Version returned from text blocks should combine `Version` and `Release` as `<version>-<release>` when release exists.

Parsing rules:

- Run info commands through `context.exec.run(...)` inside action.
- Call `context.tx.progress(0)` before parsing returned block.
- Support multiline `Description` values by appending subsequent indented lines until next `Key : Value` field begins.
- Map installed `rpm -qi` results to `installed = true`, `status = "installed"`.
- Map repo `dnf info` / `yum info` results to `installed = false`, `status = "available"` unless output explicitly states installed package.
- Include `packageId` from `name` plus `architecture` when both exist.
- Set `context.tx.status(1)` and `context.tx.progress(100)` once block parse finishes.
- If package is not found, emit `context.events.unavailable({ name = packageName, packageType = "rpm" })`.

### `outdated(context)`

Behavior:

- Resolve repo helper.
- If no repo helper exists, emit `outdated` with empty list and return empty list.
- Run `dnf check-update` or `yum check-update`.
- Treat exit code `100` as valid "updates available" result, not failure.
- Run command through `context.exec.run(...)`.
- Ignore non-package lines such as metadata headers, blank lines, and section headers like `Obsoleting Packages`.
- Count candidate package lines first, then call `context.tx.progress(0)`.
- Parse package lines into:
  - `name`
  - `packageId`
  - `installed = true`
  - `status = "outdated"`
  - `version` when cheaply available from extra query output, otherwise omit
  - `architecture`
  - `latestVersion`
  - `packageType = "rpm"`
  - `type = "package"`
- Parse repository column when present and store as `repository` or `extraFields.repository`.
- Update `context.tx.status(parsedCount)` and `context.tx.progress(percent)` while parsing.
- Set `context.tx.progress(100)` after parse completes.
- Emit `outdated` event and return parsed items.

Current installed version is optional and does not need extra per-package lookup in v1.

### `init()`

- Return `true` only when `rpm` exists.
- Do not fail startup merely because `dnf` and `yum` are missing.

### `shutdown()`

- Return `true`.

## Error Handling

- Action methods use `context.tx.begin_step(...)` before shell call.
- On command failure, call `context.tx.failed(<message>)` when available and return `false`.
- `search()` and `outdated()` degrade to empty results when repo helper is unavailable.
- `info()` degrades to installed-only mode when repo helper is unavailable.
- `install()` and `update()` fail when repo helper is required but unavailable.
- `unavailable` event is emitted for `info()` misses and may be emitted for unsupported named package operations.
- Parse errors should skip malformed lines instead of failing whole read action unless no usable records remain and command itself failed.
- When command succeeds but zero parseable records are found, return empty list or `nil` according to method contract and still emit final domain event.

## Parsing Rules

- Use tab-delimited `rpm --queryformat` for list output.
- Use key-value block parsing for `rpm -qi`, `dnf info`, and `yum info`.
- Ignore heading lines, separators, and blank lines in `search` and `check-update` output.
- Keep parsers conservative: only convert lines that match expected structure.
- Split `name.arch` on last `.` only when suffix looks like real architecture token such as `x86_64`, `aarch64`, `noarch`, `i686`, `ppc64le`, `s390x`.
- Preserve source `release`, `repo`, or other extra values under `extraFields` when not mapped to top-level fields.
- Multiline descriptions should join lines with `\n` and trim trailing whitespace.

## Files To Change

- `metadata.json`
- `README.md`
- `run.lua`
- `.reqpack-test/core/install.lua`
- `.reqpack-test/core/install-local.lua`
- `.reqpack-test/core/remove.lua`
- `.reqpack-test/core/update.lua`
- `.reqpack-test/core/list.lua`
- `.reqpack-test/core/search.lua`
- `.reqpack-test/core/info.lua`
- `.reqpack-test/core/outdated.lua`

`reqpack.lua` and hook scripts can remain minimal unless implementation proves otherwise.

## Test Plan

Update hermetic core tests to cover real RPM behavior.

Required cases:

1. `init()` succeeds when `rpm` exists.
2. `installLocal()` uses `rpm -Uvh`.
3. `remove()` uses `rpm -e`.
4. `list()` parses `rpm -qa --queryformat` output into ReqPack-friendly `PackageInfo` fields including `installed`, `status`, `packageId`, and `packageType`.
5. `search()` uses `dnf` when available.
6. `search()` falls back to `yum` when `dnf` missing.
7. `search()` ignores non-result header lines and returns empty list with no repo helper.
8. `info()` reads installed package via `rpm -qi` including multiline description parsing.
9. `info()` falls back to `dnf` or `yum` for non-installed package and maps `Repo` / `License` when present.
10. `outdated()` accepts exit code `100`, ignores header noise, and parses updates plus repository column.
11. `install()` fails cleanly when no repo helper exists.
12. `update()` fails cleanly when no repo helper exists.
13. At least one failure case exists for mutating command execution.
14. At least one malformed-line parse case exists for `list`, `search`, or `outdated` to confirm parser skips bad lines instead of crashing.

Tests should fake binary discovery commands used by `init()` and repo helper detection.
Hermetic tests likely will not assert `context.tx.status(...)` or `context.tx.progress(...)` yet, but implementation should still emit them for real ReqPack UX and smoke-test validation.

## Implementation Notes

- Keep wrapper thin.
- Prefer one command per action path.
- Avoid extra abstraction beyond small parsing helpers.
- Do not add version-resolution logic beyond best-effort token composition.
- Keep unsupported paths explicit instead of silently pretending success.
