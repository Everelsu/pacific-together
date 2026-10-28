# Pacific Drive: game context for co-op

> Historical research; see the [index](README.md) for current implementation and later evidence.

Web research 2026-10-19. Many wiki/guide sites blocked fetching; some facts come from search snippets (marked).
Main wiki: https://pacificdrive.wiki (User Manual, Car, Anomalies, Gameplay Presets pages).

## Core loop

- 1998, Olympic Exclusion Zone (OEZ), Washington. First person only, on foot or in a station wagon. Single player.
  ([Wikipedia](https://en.wikipedia.org/wiki/Pacific_Drive_(video_game)))
- **Garage hub** (Oppy's Auto Shop): repair/replace parts, Fabrication Station (research tree), Tinker Station (quirks),
  Detailing, First Aid, locker, fuel pump, battery switch, wall Route Planner. ([PS Blog](https://blog.playstation.com/?p=386881))
- **Runs**: the map is a graph of junctions; each has scavenging areas and **anchors** (energy, measured in LIMs).
  Roads close when unstable; routes reshuffle between trips. A wall separates Outer / Mid / Deep Zones.
- **ARC Device** sits on the passenger seat: in-world map + energy store. Opens gateways, pays for fabrication.
- **Instability / storm**: after a timer or once a gateway is summoned, the safe area shrinks, outside deals damage.
  Taking an anchor can trigger an atmospheric shift. Storm timings are difficulty-preset settings.
- **Exit**: drive into the gateway light pillar -> white-out -> warped to the garage. Gateway refunds energy, records
  the junction, uploads scans to the Logbook.
- **Failure**: at critical condition the car's emergency protocol returns you to the garage, losing carried resources
  (configurable: Lose All / Most / Keep Crafted / Keep All). The wreck can sometimes be found again.
- **Expeditions** (v1.9.1, Apr 2025): roguelite mode with scaling difficulty, Ida's Exchange trader.

## The car (one shared object, the heart of the game)

- 20 part slots: chassis, 5 panels, 5 doors (incl. trunk), 2 bumpers, 2 headlights, 4 tyres, 1 engine. Each part has its
  own health and status effects (Low Traction, Low Structural Integrity, flat, leaking, shorted, oxidised).
- 8 expansion racks: 4 side (fuel, battery, storage, turbine, solar), 2 seat (back-seat tanks, Auto Parker, Jump Jacks),
  2 roof (storage, Resource Radar, Ion Shield, **Chrono Dilator**, Anti-Grav).
- Fuel (siphon from barrels/cars), battery (headlights and abilities drain it), ARC jumpstart, ARC Warp (unstick, costs energy).
- Trunk: 3 storage tiers, Craft Mat / Mobile Workbench, Transfer Trunk to the garage locker.
- **Quirks**: emergent car bugs from anomaly contact, diagnosed at the Tinker Station (8 guesses per run).
- Controls: steering, brake, reverse, park/drive shifter, ignition, handbrake, radio, headlights, wipers, horn, doors
  opened by hand. The car protects from radiation/anomalies only while healthy and the doors are closed.
- **Seats**: passenger seat holds the ARC; rear seats are expansion-rack slots. No free passenger seat by design.
  ([Wiki Car](https://pacificdrive.wiki/view/Car))

## Inventory and crafting

- Backpack 66 slots + 6 quick slots, upgradable to 76 + 8 (snippet). Tools wear out (Prybar, Scrapper, Plasma Scrapper,
  Impact Hammer, Blowtorch, Thermal Vacuum, Hand-Vac, Liberator, Anchor Radar, Repair Putty, kits).
- Fabrication tree, 12 categories; unlocks persist through death. Energy tiers: Stable (Outer), Unstable (Mid), Corrupted (Deep).
- Matter Deconstructor recycles items. Scans fill the Logbook.

## Threats

- ~60 anomalies in 12 categories, +10 from Whispers in the Woods. Key ones for co-op:
  Abductor (drags car or carried object), Tourists (mannequins that **move when the Driver is not looking**, explode on
  touch), Bubblegum Buddy and other Bunnies (grab car/player/items), Spark Tower (shoots player and car), Pickpocket
  (steals a car part), Can Opener (blade on a path). ([Wiki Anomalies](https://pacificdrive.wiki/view/Anomalies))
- Junction conditions: weather, radiation, stability, car drains, damage/hazard modifiers.

## Story

- 15-20 h main (devs), ~21.5 h HLTB; 30 linear missions, many are garage tutorials. Story tied to destinations
  (Red Meadow, zone crossings). ([Wiki Missions](https://pacificdrive.wiki/view/Missions))
- Oppy, Tobias, Francis speak **only over the radio**. Number/type of cutscenes: unknown.
- Post-story: free play, Expeditions, Whispers in the Woods.

## Saves

- Manual saves only in the garage (10 slots); autosave on level entry; Suspend (v1.9.1) saves a run mid-way.
- `%LOCALAPPDATA%\PenDriverPro\Saved\SaveGames`, 2 automatic backups (`AutoSaveBackupCount` in GameUserSettings.ini).
  Steam Cloud supported per devs (the exe has no SteamRemoteStorage calls, so likely Steam Auto-Cloud: derived).

## Versions, DLC, platforms

- Launch 22 Feb 2024 (Steam, Epic, PS5). Xbox + Game Pass since 23 Oct 2025.
- Paid DLC **Whispers in the Woods** (23 Oct 2025, v1.11.0): new region, story, anomalies, Artifacts. Cosmetic DLCs.
- Last patch **1.15.0, 23 Feb 2026**; nothing since (studio on a new project). Our buildid 21896301 matches the
  net version `PenDriverPro 1.15.0` in the reference logs. "Ritual Edition" bundle announced; could bring one more patch.
- Ironwood: "no plans for multiplayer or co-op"; no official mod support, but modding encouraged.

## Community

- Recurring Steam threads asking for co-op (162-reply thread Feb 2024; 2025 threads). Players want: loot together,
  choose who drives, one waits in the car ready to leave, extra players gated by rear-seat upgrades.
- 2024 attempt by "deasted": "half ready", frozen on **loot synchronization and stable movement of players**; never released.
- ~145 Nexus mods, mostly UE4SS Lua and LogicMods paks (UE4SS 3.0.1 or experimental). Tooling: FModel, UnrealPak.

## Single-player assumptions that bite in co-op

- Menus do not pause by default ("Pause Game While in Menus": Off / Logbook / Always) -> force Off.
- **Chrono Dilator** slows the world to ~10% -> conflicts with a shared clock; disable in co-op.
- Tourists check "the Driver's" view -> treat as observed if any player sees them.
- Damage, death, radiation framed around one Driver; car protection depends on the Driver inside with doors closed.
- Passenger seat is occupied by the ARC.
- Diegetic UI (map, radio, gauges are in-world objects).
- Globals per junction: storm walls, instability, gateway summon; run end warps everyone to the garage.
- Difficulty presets (storm speed, damage multipliers, failure penalties) are per save: the host's apply.
