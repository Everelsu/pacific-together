# M6 overlay: version label, session status, event feed

Lane `hud`. Module `mod/PacificTogether/Scripts/overlay.lua`, scenario `overlay` (mutation `nooverlay`).

## What it does

- Top right, always while the mod is installed (menu, single player, sessions): "Pacific Together <MOD_VERSION>".
  Under it a status line: host "Host · N guest(s) · P ms", guest "Guest · <host name> · P ms", while connecting or
  rejoining "Joining <address>…" (the status is empty for a host with nobody connected).
- Under that a feed (5 lines, newest at the bottom, 6 s life, last 1.5 s fade). Only fed during a session.
- `overlay.post(fmt, kind, key, n)`: `kind` "info" / "good" / "warn" (colour); lines with the same `key` that are still
  visible merge: `%d` in `fmt` is the running count, `{s}` its plural ("%d item{s} taken from trunk" -> "3 items taken from
  trunk"); without `%d` a repeat shows "x3". Identical text without a key within 3 s is dropped. `overlay.other()` is the
  other player's name; `overlay.settled()` is false for the first 6 s of a session (the first full sync is not news).
- The overlay itself posts: "<name> joined / rejoined / left" (host, from the remote PlayerStates with a real name),
  "Connected to <host>" and "Connection lost, rejoining" (guest).

## How (UMG from Lua works)

`WidgetBlueprintLibrary:Create(pc, /Script/UMG.UserWidget, pc)` returns a UserWidget with a live `WidgetTree`
(`StaticConstructObject` of the bare class has none). Then `StaticConstructObject` of CanvasPanel / VerticalBox /
TextBlock with the tree as outer, `tree.RootWidget = canvas`, `canvas:AddChildToCanvas(box)` -> slot
(`SetAnchors` min=max=(1,0), `SetAlignment` (1,0), `SetPosition` (-18,12), `SetAutoSize`), `box:AddChildToVerticalBox(text)`
(`SetHorizontalAlignment(3)` = right), TextBlock `SetText(FText)`, `SetJustification(2)`, `SetColorAndOpacity({SpecifiedColor, ColorUseRule=0})`,
`SetShadowOffset/SetShadowColorAndOpacity`, font size through `local f = t.Font; f.Size = n; t:SetFont(f)`, `SetRenderOpacity` for the
fade, `SetVisibility(1)` for empty lines. `widget:AddToViewport(10000)`. Visibility `HitTestInvisible` (3) on the widget, the
canvas and the box: nothing takes input, focus or hit tests. No HUD/Canvas fallback was needed (no tournament).

## Observations

- The widget's outer is the GameInstance, but the viewport and the owning player die with the world. A guest's zone load
  crashed the game (access violation inside UE4SS, game thread) when the Lua side still called `IsInViewport` on the old
  handle. Now the handle is released (`RemoveFromParent`, `ui = nil`) in the LoadMap pre-hook, nothing touches widgets until the post-hook
  and the next tick builds a fresh one. Result folder of the crash: `20261021-151503-hud-overlay`.
- `PlayerState.Ping` is the compressed ping (ms / 4): the status shows `Ping * 4`, so 0 ms on a LAN. `ExactPing` is not readable from Lua.
- Hot reload: the old widget would stay in the viewport; the module removes any `PTOverlayBox` it finds at load.
- Test access: FindAllOf("VerticalBox") for the box named `PTOverlayBox` (`:GetOuter():GetOuter()` is the widget); its children are
  label, status, five feed lines. `FindAllOf("TextBlock")` lists thousands of game widgets (8000+): never print it.
- `pacific-game` tools default to `root=C:/PacificTogetherTest`: always pass `root`, or the call goes to another lane's game.

## Where the feed is fed (additive `ov.post` calls)

| Message | File | Side |
|---|---|---|
| "<guest> entered / left the car" | car.lua | host |
| "N car parts changed by the host" | car.lua (state apply, after settling) | guest |
| "N items taken from / put into <container>" | loot.lua `announce` (S message of a container, after settling) | both, about the other player |
| "<name> picked up an item" | loot.lua (world pickup intent T on the host, D on the guest) | both |
| "<guest> repaired / refuelled / charged <part>", "summoned the gateway", "deposited an anchor" | guestact.lua | host |
| "Gateway summoned" | world.lua (guest applies the host's picked exit) | guest |
| "Hit by an anomaly", "<guest> was hit by an anomaly" | anomalies.lua | guest, host |
| "Backpack restored from the host", "Backpack dropped as a death crate", "<guest>'s death crate dropped" | backpack.lua | guest, host |
| "Failed run: some of your items were lost" | progression.lua | guest |
| "Host progress applied" | progression.lua | guest |
| "New objective", "Mission updated" | story.lua | guest |

## Derived

- Coalescing by key makes loot polling harmless: a burst of S messages for one container is one line with a running count.
- Container name: `Inventory_Trunk` -> "trunk"; lootables take the Blueprint class name without `BP_Lootable_`.

## Guesses / unknowns

- Fonts: the default engine font (Roboto) is used; the game's own cooked font was not looked for. The look was checked in one windowed run (screenshots in the lane report).
- The feed is not hidden under the pause or main menus (z order 10000, so it draws over them); hiding is not done.
- A host map change makes the guest drop and rejoin: the host's feed shows "<name> left" then "<name> rejoined".
- Anchors deposited by the host itself, guest repairs seen from the guest's side, and the host's own car actions are not relayed.
- The status/feed text is English only.

## Screenshots

`HighResShot` (the MCP `screenshot` tool) leaves the UI out; the console command `SCREENSHOT SHOWUI` keeps it
(`Saved/Screenshots/WindowsNoEditor/ScreenShot00000.png`). One windowed run: `local/screenshots/hud/` (host-overlay.png,
guest-overlay.png, host-first.png). At 960x540 the label, teal status and a feed line read well on the HUD.

## Results

overlay 39/39 (mutation nooverlay 18/39), session 40/40, carsync 36/36, lootsync 34/34, guestact 31/31, anomalies 19/19,
backpacksync 32/32, storysync 24/24, progsync 30/30, worldsync 27/27.
