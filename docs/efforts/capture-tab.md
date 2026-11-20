# Effort — The Capture tab

**Status:** Dispatched · **Summary:** Rounds becomes **Capture**: the browser is the tab, the list of sources due is a
panel beside it, and **Next** steps through a round without leaving the browser. Every other way into the browser
switches to this tab. No schema change.

**Implements:** [ADR-0005 Amendment 2](../decisions/0005-rounds-and-browser-capture.md#amendment-2--the-capture-tab-2026-11-20).
**Builds on:** M1 S5 (PR #16): `RoundsProjection`, `BrowserModel`, `BrowserScreen`, `RoundsView`, and the
`SourcesView` fix in 53e94bd.

## The work

1. **`AppScreen.rounds` becomes `.capture`**, titled "Capture", with the symbol `safari`. It keeps the badge on the tab
   and the count in the sidebar. A saved selection of `rounds` falls back to the default screen, which is fine.
2. **An `@Observable AppRouter` in the environment** holds the app's selection, as Galavant's does
   (`Galavant/Navigation/AppRouter.swift`). `AppContainer`'s tab view and sidebar bind to it, and the `@SceneStorage`
   restore moves with it. It has two ways into the browser:
   - `capture(_ source: Source)`: selects `.capture`, makes `source` the current Rounds source, and loads its
     `listingURL`.
   - `capture(_ url: URL)`: selects `.capture`, clears the current Rounds source, and loads the URL.

   Both go through `BrowserModel.open`, so the one `WebPage` stays the only page.
3. **`CaptureScreen` replaces `BrowserScreen` and `RoundsView` as screens.** It is the Capture tab's root: the
   `WebBrowserView` over `BrowserModel.page`, with S5's accessory, chip, passive capture and source picker unchanged.
   - **It never loads a page on appear.** Today `BrowserScreen` calls `model.open` in `onAppear`, which would reload
     the page on every tab switch. Only the explicit actions here load a page: a row in the list, **Next**, and the
     router's two calls. `WebBrowserView` already leaves a loaded page alone on first appearance.
   - **No other screen shows the browser.** Remove the `NavigationLink`s to `BrowserScreen` in `RoundsView`,
     `SourcesView`'s **Open in browser**, and `ListingDetailView`'s **Tickets**. The last two become buttons that call
     the router.
4. **The list of sources (`RoundsList`)** is `RoundsView`'s list made into a component. It keeps the same three groups,
   rows and **Mark as checked** swipe action. Tapping a row loads that source, and the row for the current source is
   marked. It appears in two places:
   - **The panel:** SwiftUI's `inspector(isPresented:)` on `CaptureScreen`, which is a trailing column in regular width
     and a sheet in compact. A toolbar button shows and hides it. It starts shown in regular width and hidden in
     compact. On iPhone, tapping a row also dismisses the sheet.
   - **The browser's empty page:** `WebBrowserView`'s `home` slot shows `RoundsList`, so a fresh Capture tab opens on
     the list.
5. **Next.** Add a pure `RoundsProjection.next(after: Source.ID?) -> Source?` in `BrightLightsChecking`. It returns
   the first source in Due, then Not reading automatically, that isn't the current one, or `nil` if there's none.
   Because a captured or marked source leaves Due, "next after the current one" is simply the top of the list without
   it. The accessory gets a **Next** button that loads that source as the current Rounds source. With no next source,
   it's disabled and reads "Round done".

## Tests (package)

`RoundsProjection.next(after:)`:
- It skips the current source.
- It moves from Due to Not reading automatically when Due has nothing else.
- It returns the first source once the current one has left Due.
- It returns `nil` when both groups are empty, or hold only the current source.

The S5 projection tests pass unchanged.

## Not in this effort

- Capture helpers (ADR-0005 Amendment 1).
- Notifications for Capture.
- Changes to capture, matching, the ration or the chip.

## Done when

`scripts/check-drift.sh` passes; closeout (ADR-0005 D16). This effort owes no new gate. The M1 S5 gate in
`device-passes.md` was rewritten for the Capture tab by the plan PR that dispatched this, so closeout adds no gate line.
