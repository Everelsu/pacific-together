# PT3-perf: host hitches in the real Steam play, polling to hooks

Research only (2026-10-23 night, no game run, no code changed). Sources: `local/playtest-20261023-steam/host-UE4SS.log`
(host = friend, 0.0.6-dev-e56651f, 38 one-minute `PT|perf` windows), the code at that commit, `local/atlas`, NOTES
"2026-10-22 night: frame-time pass". Not repeated here (already done): FindAllOf is cheap by hash tables, wreck-part reads
within 30 m, StaticFindObject/RegisterHook of unloaded paths, controller/world/BFL caches, loot budgets per frame.

## Observations

Log sums over the session. `PT|perf` prints only the 8 heaviest loops per minute, so every number is a lower bound.
Site = `main.lua` `caller()` line, which is the line after the `LoopInGameThreadWithDelay(` line.

| site | loop (period) | sum ms | calls | avg ms | max | slow lines | share of 217 s |
|---|---|---|---|---|---|---|---|
| car.lua:740 | host car tick `hostTick` (250 ms) | 40537 | 8333 | 4.9 | 47 | 83 | 19 % |
| visual.lua:552 | host levels/paint/props tick (250 ms) | 39455 | 7888 | 5.0 | 61 | 72 | 18 % |
| car.lua:753 | door swing watcher (50 ms) | 38781 | 35773 | 1.1 | 40 | 63 | 18 % |
| carfeel.lua:265 | `hostCarTick` (100 ms) | 24505 | 20226 | 1.2 | 21 | 0 | 11 % |
| anomalies2.lua:104 | grabber cone check (100 ms) | 22011 | 19470 | 1.1 | 19 | 0 | 10 % |
| loot.lua:721 | loot tick (500 ms) | 21943 | 4027 | 5.4 | 42 | 11 | 10 % |
| world.lua:228 | hazard positions (250 ms) | 13952 | 7003 | 2.0 | 19 | 0 | 6 % |
| carfeel.lua:282 | radio tick (200 ms) | 13373 | 10763 | 1.2 | 21 | 0 | 6 % |
| nametag.lua:104 | nametag (50 ms), 7 windows listed | 1751 | 6161 | 0.3 | 15 | 0 | 1 % |
| progression.lua:118 | snapshot (2 s), 3 windows listed | 552 | 89 | 6.2 | 35 | 24 | spikes only |

- Together about 5.7 s of game thread per minute (9.5 %, about 1.6 ms of every 16 ms frame) and 257 single callbacks of
  30-61 ms (2-4 dropped frames each, one about every 9 s). Every host loop returns at once without a guest, so these are
  with the guest connected.
- Lookups (top 8 per minute): `FindAllOf BP_CarManager_C` 16.6 s over 58943 calls (26 per second, 0.28 ms each),
  BP_Hazard_PhysicsGrabber_C 10.4 s / 16527, PlayerController 9.5 s / 23569, BP_PlayerCarNew_C 5.6 s, AC_CarAudio_C 3.4 s,
  Speedometer 3.4 s, BP_InventoryManager_C 2.7 s, BP_MusicManager_C 2.5 s, Gobbler + Screen 3.0 s: about 54 s in all, a
  quarter of the listed loop time. The real game's FindAllOf is slower than the lab's 0.2 ms.
- `common.lua` caches singletons in `FindFirstOf` (`SINGLE`: CarManager, InventoryManager, MusicManager, ...), but the hot
  call sites bypass it. Module-local `first(class)` helpers loop `FindAllOf`: `car.lua:46` (`carManager`, `equipped`),
  `carfeel.lua:42` (CarManager and MusicManager, several per tick), `upgrades.lua`, `world.lua` (ToD, Storm manager),
  `stations.lua`. These are the 26 CarManager lookups per second.

What each loop does per tick (read from the code):

1. **car.lua:740 `hostTick`** (4 Hz). `theCar(true)` (cached list; per car `inWorld` + `gone`: GetWorld, two GetFullName,
   K2_GetActorLocation). `carManager()` (FindAllOf). `moveArc`: two FindAllOf of the Gobbler classes with GetFullName per
   hit, though a slot is moved once (`arcDone`). `sample`: `equipped()` (FindAllOf InventoryManager +
   GetCarEquippedContainer), 6x `GetDoorState`, parking brake, then for every equipped slot (about 25-35): `itemOf` (TMap
   ForEach), `archPath` (`Archetype:GetFullName()` + string ops), `manifestation()` (UFunction with FName and tag struct),
   `readPart` (1-3 UFunctions), string.format. Then `doorParts` (GetAttachedActors, GetClass:GetFName:ToString for every
   attached actor) and per door IsSimulatingPhysics + two transforms. About 100-200 Lua-to-UE calls per tick, which fits
   4.9 ms. It sends only when the string changed or every 3 s, so nearly all the work rebuilds the same text.
2. **car.lua:753** (50 ms, measured 15.6 per second). `theCar(true)`, `doorParts` every 2 s, per door (6) `valid`,
   `IsSimulatingPhysics`, and the angular velocity of simulating ones. 1.1 ms average although nothing swings most of the
   time. While a door swings it calls the full `hostTick()` at 20 Hz: the 63 slow lines (avg 35 ms) are those calls.
3. **visual.lua:552 `hostTick`** (250 ms beat). `levelPackages` every 2 s (cheap). `paintLines` every 500 ms: `eachPart`
   repeats the car slot walk of item 1 (equipped, ForEach, itemOf, slotName, manifestation), then per part `tintOf`
   (K2_GetComponentsByClass), `GetTintableProperties`, up to 3 GetFullName. `propsHost` every second: a sweep over
   `FindAllOf("Actor")` (about 2600 in a zone) with `kindOf` per actor in 4 ms slices, then the diff of the whole result
   and `bpLine` state strings for placed Blueprint props, `FindAllOf PlayerController`, a distance sort.
4. **carfeel.lua:265 `hostCarTick`** (10 Hz). `carCar()` (`require("car")` + `theCar`), `sample`: FindAllOf CarManager,
   `ownedBy` twice (FindAllOf AC_CarAudio_C and Speedometer, GetOwner/GetAttachParentActor + two GetFullName per object),
   SpeedArm read, string.format; resend at 1 Hz when unchanged.
5. **anomalies2.lua:104** (10 Hz). FindAllOf grabbers (6-8 per zone), `live()` (GetFullName per grabber), per grabber
   `CoreFloatingMesh:K2_GetComponentLocation`, `GetFName():ToString()`, `IsOverlappingActor` per guest. Does nothing
   unless a guest is within 700 uu.
6. **loot.lua:721** (2 Hz). `scanChanges` over every entity (about 300): lootables `GetNumItems` + `flagsOf`; wreck parts
   every 10 s round robin or 2 s near a player. `scanMoves`: `K2_GetActorLocation` of every world item every tick.
   `scanHost` every 2 s, `flush`.
7. **world.lua:228** (4 Hz). FindAllOf `BP_Base_Hazard_C`, `live` (GetFullName), `IsA`, `GetFName:ToString`,
   `K2_GetActorLocation`, `core()` (property read, IsValid, component location) per hazard. Most never move.
8. **carfeel.lua:282 `radioTick`** (5 Hz). Two FindAllOf (MusicManager, CarManager) + three property reads. Mostly lookups.
9. **progression.lua:118** (0.5 Hz, only with a guest). `snapshot` walks the whole `GlobalWhiteboard.Entries` map,
   `UnlockedNodes`/`PurchasedNodes` with GetFullName per node, the logbook and `LegStates`, builds four sorted string
   lists and compares them. 6 ms average, 35 ms max.
10. **nametag.lua:104** (20 Hz). About 6 UFunctions per other player per tick plus GetFullName. Small.

## Derived

Ranked by expected host frame-time saving. The "removes" column is my estimate (assumes the replaced work falls to
10-20 % of itself), not a measurement. Items 1 and 4 walk the same slots and 3 touches 1, so the figures overlap.

| rank | change | removes of 217 s | removes spikes |
|---|---|---|---|
| 1 | door watcher idle by hook (no per-door physics reads, no `hostTick` at 20 Hz) | about 35 s | the 63 slow lines at car.lua:753 |
| 2 | car `sample`: P (part) lines at 1 Hz or on a dirty flag, cached archPath, shared `doorParts`, `moveArc` every 5 s | about 28 s | most of the 83 at car.lua:740 |
| 3 | visual: paint on hook or 5 s, prop sweep every 10 s once stable | about 28 s | most of the 72 at visual.lua:552 |
| 4 | module-local `first()` to the cached `FindFirstOf`; cache audio/speedometer/container per car | about 25 s | none (steady cost) |
| 5 | grabber loop: cached list, distance gate | about 18 s | none |
| 6 | loot: `scanMoves` near players only, lootables by hook | about 12 s | the 11 at loot.lua:721 |
| 7 | world hazards: cached list per map, no per-tick GetFullName | about 10 s | none |
| 8 | progression: counts fingerprint, full snapshot on change or every 20 s | small | the 24 at progression.lua:118 |
| 9 | nametag 100 ms while invisible | about 1 s | none |

### Replacement per loop and hook status

Hooks are `RegisterHook(path, cb)` on Blueprint functions with one callback: it runs after the function (PT1-feel,
PT2-hands, PT2-stations). Do not hook the multicast delegate signature stubs (`OnDoorChanged__DelegateSignature`,
`OnCarIgnitionChanged__...`, `OnPartBroken__...`): a Blueprint broadcast does not call them, so they are expected not to
fire (unproven; hook the function that causes the change instead). Never hook a Tick.

1. Door watcher (car.lua:753): hooks on `BP_CarPart_Door_Base_C:AttemptOpen`, `AttemptShut` (already registered in
   `hookAll`, known to fire for a guest's own press; for the host's own press or a host-applied door the same Blueprint
   runs on the authority, probably fires, NEEDS A PROBE), plus `OnConstraintBroken_Event_0` and `ObjectKicked` for a door
   knocked open (needs a probe). They set `swingUntil = now + 6 s`; the loop returns at its first line unless
   `now < swingUntil`. Also re-arm when the 4 Hz tick sees a door bit change. Idle cost: one clock read per 50 ms.
   Fallback if the hooks do not fire on the host: keep the loop but test one `cm.DoorStates` read first and skip the
   per-door physics reads while all doors are shut.
2. car `sample`: split into H (ignition, gear, lights, brake, door bits: about a dozen property reads, keep 4 Hz) and P
   (parts, 1 Hz). Dirty flag set by `BP_CarManager_C:UpdatedCarEquip` (BPEvent in the atlas; whether it fires on a listen
   host when a part is installed: NEEDS A PROBE) and by the existing guest-action paths in `guestact.lua`/`guestparts.lua`
   (no hook needed there). Health, fuel and battery drift continuously: that is why P keeps a 1 Hz cap (the guest sees
   them at 1 Hz instead of 4 Hz). `archPath` cached by item address; the `doorParts` cache shared with item 1, dropped on
   `RegisterLoadMapPreHook`; `moveArc` every 5 s.
3. visual: paint on `BP_TintableComponent_C:SetPaint`, `SetDecal`, `SetTintingEnabled` (BPEvents in the atlas; garage
   paint on the host: NEEDS A PROBE) with a 5 s timer fallback. Prop sweep: after the first complete sweep rerun every
   10 s (placed props change rarely; `reset()` on map change already restarts). No `NotifyOnNewObject`: it fires on the
   loading thread (loot.lua:333 comment) and the cached `kinds` already make each actor a one-time cost.
4. `first()`: use `FindFirstOf` (already cached and dropped on map load in `common.lua`). Add `BP_ToDManager_C` and
   `BP_StormManager_C` to `SINGLE`. Level props (shredder, inventing bench, stereo): cache per map. AC_CarAudio and
   speedometer: per car address, drop on map load or when `IsValid` fails. No hook needed; the same cache already runs in
   other modules since 2026-10-22.
5. Grabbers: list cached per map (refetch every 10 s for ones the hazard director spawns), skip the body unless a guest
   pawn is within 2500 uu of any grabber. No hook: `BP_HazardManager` `OnHazardGrab/Release` are multicast delegates,
   unproven.
6. Loot: `scanMoves` for world items within 60 m of a player (`playerSpots` exists) and every second tick. For lootable
   contents `BP_Lootable_Base_C:BoundOnEventItemCountChanged` is KNOWN to fire on the host when items move (X2.md); use it
   as a dirty flag, with a full pass every 10 s as fallback. `OnRollForOpenItems` runs on open (X2.md).
7. World hazards: list cached per map; replace `live()` GetFullName with IsValid + a once-per-actor Transient verdict.
8. Radio: cached managers (item 4); `BP_RadioComponent_C:ChangeChannel` is already hooked (carfeel.lua:120).
9. Progression: `UWhiteboard` is native, no Blueprint write function to hook. Fingerprint `Entries` count, node set
   sizes, logbook length every 2 s; run the full snapshot when one changed or every 20 s. A whiteboard value that changes
   without a count change reaches the guest up to 20 s late (quest flags have their own path in story.lua).
10. Nametag: 100 ms while alpha is 0.

## Guesses

- The 250 ms car, 250 ms visual and 50 ms loops are phase-locked from the same boot and land on one frame; delaying one
  loop's first call by 80-120 ms would split some spikes at no cost.
- The cost is the count of Lua-to-UE calls (about 1000 per second of host loops), not Lua string work.
- The 63 slow lines at car.lua:753 are `hostTick()` calls from inside the swing loop (average 35 ms, far above the 250 ms
  tick's 4.9 ms: the swing path also reaches `net.toGuests` and a cold doorParts).

## Unknowns (probe before relying)

1. Does `BP_CarManager_C:UpdatedCarEquip` fire on the listen host when a part is installed or removed (host and guest
   through the host)?
2. Do `AttemptOpen`, `AttemptShut`, `OnConstraintBroken_Event_0`, `ObjectKicked` fire on the host for a host-opened door,
   a guest-opened door applied by the host, and a physics-kicked door?
3. Do `BP_TintableComponent_C:SetPaint`/`SetDecal` fire on the host on a garage paint?
4. Is the door bit set in `H` early enough to start the swing watcher without a hook?
5. There is no frame-time source: this log gives callback times only, not FPS. A before/after number is callback sums.

## Change list for a worker (file by file, guard scenario)

Measure first: take a 900 s run with a guest, record per-site `sum_ms` and the count of `PT|slow` lines; compare after.

1. `mod/PacificTogether/Scripts/common.lua`: add `BP_ToDManager_C`, `BP_StormManager_C` to `SINGLE`; export
   `common.first(class)` (cached `FindFirstOf` + IsValid). Guard: `worldsync`, `carfeel`, `upgrades`, `stations`.
2. `car.lua`: `first` -> `common.first`; split `sample` into H every tick and P cached (1 Hz or dirty); `archPath` cache;
   one shared `doorParts` cache; `moveArc` every 5 s; swing loop gated by `swingUntil` set by host hooks on
   `AttemptOpen`/`AttemptShut`/`OnConstraintBroken_Event_0` (in `hookAll`; the existing callbacks return for non-client,
   add the host branch) and by an `R` line or door bit change in `hostTick`. Guard: `carsync` (state, door swing seen by
   the guest at 20 Hz, parts), `carenter`, `carexit`, `guestparts`, `guestact`, `arckey`, `garagesync`. Add to `carsync`
   a check that the swing loop does no work while no door moved (a debug counter `car.swingWork`).
3. `carfeel.lua`: `first` -> `common.first`; per-car cache of `ownedBy` results. Guard: `carfeel` (radio, horn, wipers,
   playlist).
4. `visual.lua`: `paintLines` on dirty or 5 s; sweep every 10 s after the first complete one (`sweepEvery`, `reset()`
   restores 2 s); `eachPart` over the cached car slots. Guard: `visual` (28 checks), `visualgarage`, `zonejoin`.
   Watch `guest_removed_mesh_gone` (NOTES round 5): a 10 s sweep needs that check's timeout at 12 s or more.
5. `anomalies2.lua`: grabber list cache, distance gate, `live()` without per-tick GetFullName. Guard: `anomalies2`,
   `anomalies`.
6. `loot.lua`: `scanMoves` near players and every second tick; `BoundOnEventItemCountChanged` dirty flag with 10 s
   fallback. Guard: `lootsync`, `lootsync2`, `lootcar`, `playpath` (p2 and p6 are known flakes on the baseline too).
7. `world.lua`: cached hazard list for the position loop. Guard: `worldsync`, `anomalies2` (grabber core).
8. `progression.lua`: fingerprint before the full snapshot, 20 s fallback. Guard: `progsync`, `storyprog`.
9. `nametag.lua`: 100 ms while the tag is invisible. Guard: `nametag`.
10. New probe scenario `perfprobe` (add `perfprobe = @(2, 600)` to `$Defaults` in `tools/run-test.ps1`, `$AutoJoin`
    too): host registers counters on the hooks in Unknowns 1-3, installs and removes a part, opens/shuts a door,
    paints; logs `PT|probe <hook> n=<k>`. Its result decides the hook parts of items 2, 3 and 6 (keep the timer
    fallbacks for any hook that does not fire).
11. Suite once after the merges (NOTES "suite once at end"), then a 900 s `carsync` and `visual` and read the host's
    `PT|perf`/`PT|slow`: target is car.lua loop sums under a quarter of the table above and no slow line above 40 ms in
    an idle 10 minutes.
