# ContainerStack UI/UX redesign — design

Date: 2026-08-21
Status: approved, not yet implemented
Target: `guanchzhou/ContainerStack` fork first; a defined subset is upstreamable.

## Why

The app's own sidebar labels the landing screen **"Activity Monitor"** (`AppChrome.swift:90`) while it renders a static grid of count tiles that restate numbers already shown in the sidebar badges. `DashboardView.swift:29` defaults selection to `.containers`, so in practice nobody lands on it. Meanwhile the product's single structural differentiator — **one micro-VM per container, with its own CPU and memory allocation** — is not visible anywhere in the GUI, even though the `container` CLI prints it in `container list`.

Guiding principle (standing product decision, 2026-08-21): *do not copy Docker or Rancher; use their ideas on Apple's substrate.* A shared-VM tool shows one global resource slider because it has one VM. This runtime has one VM per container, so the meaningful unit is per-container — and no competitor can match it.

## Goals

1. The landing screen earns its name and its space.
2. Every fact is stated exactly once.
3. Absent data, failed data and zero are visually distinct.
4. Framework behaviour replaces hand-rolled equivalents; net LOC goes down.

## Non-goals

Kubernetes (roadmap M8). Settings / editable per-container limits — a natural follow-on once stats exist, but its own design. Event history: `/events` returns 200 with an empty body, so there is nothing to build on. Compose changes. Any redesign of the inspector's logs or ports tabs.

## Verified API facts

All measured against socktainer on Apple `container` 1.2.2 via `~/.socktainer/container.sock`, 2026-08-21. These constrain the design and several contradict `docs/ROADMAP.md`.

| Endpoint | Result | Consequence |
|---|---|---|
| `GET /containers/{id}/stats?stream=false` | **200, real data** | Activity Monitor is buildable today. ROADMAP lists stats under M2-missing; it works. |
| `GET /containers/{id}/json` | 200, by ID | `HostConfig.Memory` and `HostConfig.NanoCpus` give the per-container allocation over the socket — no need to shell out to `container`. |
| `GET /system/df` | **500** `{"message":"Something went wrong."}` | Disk-usage tiles cannot be populated. Must render as a failure, not an em dash. |
| `GET /events` | 200, empty body | No event feed. Rules out history/triage-feed designs. |
| `GET /containers/{id}/top` | 501 | No process list. |
| `GET /images/{ref}/json` | 200 **by tag only**; 404 by ID | Image arch/OS enrichment must use a RepoTag. |
| `GET /images/{id}/history` | 404 | No layer history. |

Sample `/stats` payload shape actually returned:

```
cpu_stats.cpu_usage.total_usage   13680921000    (ns)
cpu_stats.online_cpus             10             (HOST cpus, not the container's)
memory_stats.usage / .limit       2830721024 / 6442450944
networks.eth0.rx_bytes/.tx_bytes  2153626 / 2468445052
blkio_stats.io_service_bytes_recursive  read 98676736, write 4096
pids_stats.current                58
```

## Section 1 — Information architecture

| Surface | Job | Owns |
|---|---|---|
| Menu bar (`MenuBarExtra`) | "is my stuff up?" | Runtime state, per-container state, start/stop |
| **Activity Monitor** | "what is it costing / what is wrong?" | Live per-container resources. Landing screen. |
| Containers / Images / Volumes / Networks | control, housekeeping | Native `Table`s, keyboard-driven |
| Inspector | detail on one item | Logs, ports, configuration |

Runtime status is stated **once**, in the window toolbar. Removed: the `RuntimeHero` card (`DashboardView.swift:210-259`), the "Engine" grid that repeats API version + arch + socket path (`:335-373`), and the multi-line sidebar-footer tooltip (`SidebarRuntimePanel.swift:75-89`). The sidebar footer keeps a one-line state summary.

The LaunchAgent call-to-action stops being instruction text inside a tooltip: `launchAgentStatus` (`RuntimeViewModel.swift:121-136`) currently embeds "use 'Enable at Login'" as a string while the real button hides behind an unlabelled ellipsis menu (`SidebarRuntimePanel.swift:117`, `:123-133`). The button moves inline, next to the state it fixes.

## Section 2 — Activity Monitor

### Data

New in `ContainerStackCore`:

- `DockerAPIClient.containerStats(id:)` → `GET /containers/{id}/stats?stream=false`
- `ContainerStatsSample` — decoded payload, `Sendable`
- `ContainerAllocation` — `memoryBytes`, `nanoCpus`, decoded from `HostConfig` on container inspect
- `ContainerResourceRow` — the derived, sortable view model: name, cpuPercent, memoryUsed, memoryLimit, netRx, netTx, blkRead, blkWrite, pids

### CPU percent — deliberately not Docker's formula

Docker computes `cpuDelta / systemDelta * online_cpus`. That is wrong on this runtime, twice:

1. `system_cpu_usage` was `10.68s` against a container `total_usage` of `13.68s` on a 10-CPU host. If it meant host jiffies it would be far larger, so its semantics are not Docker's and must not be trusted as a denominator.
2. `online_cpus` is 10 (the host), but the container is allocated `NanoCpus = 4000000000`, i.e. **4**. Dividing by 10 understates usage by 2.5x.

So:

```
cpuPercent = (Δtotal_usage_ns / Δwall_clock_ns) / allocatedCpus * 100
allocatedCpus = HostConfig.NanoCpus / 1e9, falling back to online_cpus when 0
```

Two consecutive samples over wall-clock elapsed time. Robust regardless of what socktainer means by `system_cpu_usage`, and it needs no undocumented semantics. This is a pure function and is the primary unit-test target.

### Presentation

Native `Table` with `sortOrder: Binding<[KeyPathComparator<ContainerResourceRow>]>`. Columns: Name, CPU %, Memory (`used / limit` plus a `Gauge`), Net I/O, Disk I/O, PIDs. Memory column is the differentiator — the limit shown is *this container's own VM's* limit.

`Table` does **not** sort its own data; re-sort in `.onChange(of: sortOrder)`. (Confirmed against Apple's `Table` documentation; sortable `Table` is macOS 12+, target is 26.)

Below the table, a compact footer for the three non-per-container facts: image count and total size, volume count, network count — each rendered through `ResourceValue` (Section 4), so the `/system/df` 500 shows as a failure with a Retry affordance rather than an em dash.

### Polling

2s interval, only while the view is visible, cancelled on disappear — reusing the existing `.task` / `.onDisappear { model.stopMonitoring() }` pairing (`DashboardView.swift:105-114`). One request per **running** container; stopped containers are not polled. Requests issue concurrently with a small bound, and a sample that fails leaves the previous row values in place marked stale rather than clearing the table.

## Section 3 — Native migration

| Replace | With | Gain |
|---|---|---|
| Hand-rolled `LazyVStack` rows in all five resource lists | `Table` + `TableColumn` | Column sorting, resizing, keyboard navigation, VoiceOver, and the pane actually fills — this is what kills the dead space |
| `Lucide.swift` + bundled SVG assets | SF Symbols | Deletes the loader, its silent blank-icon fallback (`Lucide.swift:82-84`), and the asset-staging risk |
| `AppTheme` hex palette | Semantic colors + system materials | Correct light/dark and contrast for free |
| `.font(.system(size:))` throughout | Semantic text styles | Dynamic Type works |
| No keyboard support | A `Commands` scene | Cmd-R refresh, Delete (through confirmation), Cmd-1..5 tab switching |
| `ContainerInspector` duplicate components | Existing `ResourceListComponents` equivalents | `ContainerInspector.swift:52-93,125-164,221-245` reimplements `ResourceListComponents.swift:70-175` near-verbatim |

Also: the inspector's "Stats" tab currently shows metadata (status, ID, image, command, stack, network) and no statistics — nothing in the codebase calls `/stats` today. It is renamed to "Info", and real stats live in the Activity Monitor.

Net effect is deletion, though the honest figure is smaller than a naive count suggests. Measured candidates: `Lucide.swift` 113 LOC plus 30 bundled SVG assets (fully removable); `ContainerInspector` duplicated sections ~104 LOC (fully removable); `ContainersView` hand-rolled row and button builders 127 LOC and `ResourceViews` rows and inspectors 159 LOC (**partly** removable — `Table` still needs cell views, so these shrink rather than vanish); `ResourceListComponents` 258 LOC of which the row shell goes and the inspector blocks stay. Expect roughly 250-300 LOC deleted outright and another ~250 reduced, not a clean 700.

## Section 4 — Honest states

One representation replaces three ad-hoc conventions:

```swift
enum ResourceValue<T> {
    case value(T)
    case notReported     // the source genuinely has no value
    case failed(Error)   // the source errored; offer a retry
}
```

Fixes, all currently rendering missing-or-broken data as data:

- `/system/df` 500 → "Image storage unavailable — engine error [Retry]", instead of `—`. Today `refreshDiskUsage()` swallows it with `try?` and no error property (`RuntimeViewModel+Resources.swift:62-64`).
- `ByteSize.formatted` collapses nil, negative and zero into one glyph (`ByteSize.swift:6-9`).
- `Created: 0` rendered as a real relative date; fixed separately upstream, folded into this type here.
- `Architecture: nil` rendered as the assertion `unknown/unknown` (`ImagesView.swift:162`).

Message severity gets a real enum so success stops rendering grey: `containerMessage` / `resourceMessage` are bare `String?` today and `MessageCard` hardcodes `tint: .secondary` (`DashboardView.swift:190-196`). Severity also lets the per-kind message split fix the cross-resource bleed (one shared `busyResource` currently disables Volumes' controls while an image pulls).

## Testing

Pure functions, tested with the suite already in use (swift-testing in Core, XCTest in App — note `swift build` does not compile test targets):

- `ContainerStatsSample` decoding, from the real captured payload above as a fixture
- `cpuPercent` math: two-sample delta; zero elapsed time; `NanoCpus == 0` falling back to `online_cpus`; counter reset (negative delta) yielding 0 rather than a negative percentage
- `ContainerAllocation` decoding from `HostConfig`, including absent fields
- `ResourceValue` rendering: `.value`, `.notReported`, `.failed` each produce distinct output
- `ByteSize` boundaries: nil, negative, zero, and a real value

Not automatable here: the `Table`, the dialogs and the Commands scene have no UI test target. Verified by staging and launching the bundle.

## Sequencing and delivery

Fork-first, four independent steps:

1. **Honest states** (Section 4) — smallest, unblocks the others' correctness. Upstreamable.
2. **Activity Monitor** (Section 2) — the value. Fork; propose upstream with screenshots.
3. **Commands scene** + `ContainerInspector` de-duplication — upstreamable.
4. **Native migration** (Section 3) — largest and most visual. Fork.

Steps 1 and 3 are plausible small PRs to `bshk-app/ContainerStack`. Steps 2 and 4 are large enough that dropping them on a maintainer unannounced would be rude; they get an issue with screenshots first.

## Risks

- **`/stats` is undocumented on this runtime.** It works today and is not in the ROADMAP's supported set, so a socktainer bump could change or remove it. Mitigation: the client treats a stats failure as `.failed`, the table degrades to the columns available from container inspect, and the screen never becomes unusable.
- **Per-container polling scales with container count.** Bounded concurrency plus visible-only polling; if it becomes a problem the interval is the knob.
- **Native migration is a large visual diff** and will conflict with upstream work on the same files. Accepted as the cost of the fork-first choice.
- **`Table` restyling is limited** compared to hand-rolled rows. Accepted deliberately: the keyboard, sorting and accessibility behaviour is worth more than pixel control.
