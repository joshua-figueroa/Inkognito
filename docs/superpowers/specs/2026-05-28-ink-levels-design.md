# Ink Level Indicator — Design Spec
Date: 2026-05-28

## Summary

Add an on-demand ink level button to the printer detail view. Clicking it fetches CMYK supply levels from the local CUPS IPP endpoint and displays them in a popover to the left of the button.

## Data Source

IPP `Get-Printer-Attributes` on `ipp://localhost/printers/<printerName>` with requested attributes:
`marker-colors, marker-levels, marker-names, marker-types`

Filter to entries where `marker-types` value is `ink-cartridge`. Show only Black, Cyan, Magenta, Yellow (the four ink-cartridge markers). Waste ink and any other types are ignored.

`marker-levels` values are integers 0–100 representing percentage remaining.
`marker-colors` values are hex strings (e.g. `#000000`) used directly as the bar color.

## New File: `SupplyReader.swift`

`nonisolated struct SupplyReader` with one static method:

```swift
static func fetchLevels(printerName: String) -> [SupplyLevel]
```

Runs synchronously on the caller's queue (always called from `DispatchQueue.inkognitoNetwork`). Uses `Process` + `/usr/bin/ipptool` identically to the existing `fetchCompletedJobStats` pattern in `AppState`. Parses the flat attribute output, pairs up name/level/color/type by index position, filters to `ink-cartridge` type only, returns the array.

```swift
struct SupplyLevel: Identifiable {
    let id = UUID()
    let name: String       // "Black", "Cyan", "Magenta", "Yellow"
    let percent: Int       // 0–100
    let color: Color       // parsed from hex string
}
```

## AppState Changes

```swift
@Published var supplyLevels: [SupplyLevel] = []
@Published var isLoadingSupply: Bool = false

func refreshSupply() // clears supplyLevels, sets isLoadingSupply=true,
                     // dispatches to network queue, publishes results on main
```

`refreshSupply()` is only callable when `selectedPrinter != nil`. On network error or empty result, sets `supplyLevels = []` and `isLoadingSupply = false`.

## UI: PrinterDetailView Changes

The toggle row becomes an `HStack` with the toggle on the left and a `drop.fill` button on the trailing end:

```
[  Share this Printer  ●  ]    ················    [💧]
```

The button:
- SF Symbol: `drop.fill`
- Button style: `.borderless`
- On tap: calls `appState.refreshSupply()`, sets `showSupply = true`
- Disabled when `!appState.isSharingActive` (can't query a printer that isn't shared/reachable)
- `@State private var showSupply = false`

Popover:
```swift
.popover(isPresented: $showSupply, arrowEdge: .trailing)
```
Arrow on the trailing edge means the popover opens to the left of the button.

Popover content — `SupplyPopover` private struct:
- Fixed width 200pt
- Padding 14pt
- Title: "Ink Levels" in `.headline`
- If `isLoadingSupply`: centered `ProgressView()`
- Else if `supplyLevels.isEmpty`: "Unavailable" in `.secondary`
- Else: `ForEach(appState.supplyLevels)` → one row per ink:
  - Name label (e.g. "Black") `.caption` `.secondary`
  - `ProgressView(value: Double(level.percent), total: 100)` with `.tint(level.color)`
  - Percent label (e.g. "50%") `.caption` `.secondary` trailing-aligned

## Error Handling

If `ipptool` exits non-zero or returns no ink-cartridge markers, `supplyLevels` stays empty and the popover shows "Unavailable". No alert, no retry — the button can be tapped again.

## Out of Scope

- Waste ink / maintenance cartridge display
- Low-ink warnings or badge on the button
- Polling or background refresh
- Persisting supply levels across launches
