# Pacific Together

Two-player online co-op mod for [Pacific Drive](https://store.steampowered.com/app/1458140/Pacific_Drive/):
one drives, one rides along, both scavenge, the run is shared. Join through Steam invites, the friends list or direct IP.

**Status: development preview 0.8.1 (2026-10-30), network protocol 5.** Shared car, loot, progression and run systems
are implemented, with ongoing playtesting and fixes. Both players need the same mod version. No public release before
1.0; previews are for the developers and friends. See [CHANGELOG.md](CHANGELOG.md) for changes and known issues,
and [docs/PLAN.md](docs/PLAN.md) for the planned scope.

- Game build: Steam v1.15.0 (buildid 21896301). Other builds are not supported.
- Built on [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS). Not affiliated with Ironwood Studios.
- Research notes: [docs/research](docs/research). Release rules: [docs/RELEASING.md](docs/RELEASING.md).
- `reference/pdcoopnet` holds the lab notes and README of [PDCoopNet](https://github.com/BroZYTnikkkk/pacific-drive-coop) v0.2
  (MIT, by BroZYTnikkkk), kept as research material; none of its code is in this repo.

## Current features

- **Sessions:** host plus one guest, Steam friends-only lobbies and invites, or direct-IP joining. Steam joining was
  verified between two real accounts in the October 23 playtest. Guests can rejoin and follow the host through map changes.
- **Players:** animated survivor bodies, held tools and items, name tags with health, HUD and ARC-map markers, and
  middle-mouse pings. The guest has their own health, radiation damage and backpack; death drops a recoverable crate
  and respawns them at the car. The host stores the guest's backpack for later joins.
- **Car:** the host drives and the guest rides in the passenger seat. Parts, damage, fuel, battery and storage are
  shared; the guest can repair, scrap, refuel, remove and install parts. Engine audio, instruments, lights and supported
  car-upgrade effects follow the host.
- **Loot and world:** shared containers, pickups, abandoned cars and garage storage, with item condition preserved
  on handover. Zone props, instability, storms, gateways and many anomaly interactions are synchronized; weather and
  time of day are sent but were seen to differ in hand play.
- **Run and progression:** travel through junctions and return to the garage together, including shared run failure.
  The guest sees the host's research, garage and player upgrades, missions, journal and radio dialogue, and can use
  supported garage stations and summon a gateway through the ARC. The host owns the world and save; the guest's own
  saves are protected while joined.
- **Interface:** session status and activity feed, guest loading and seat prompts, shared pause when the host opens
  Esc, the game's own loading screen on both sides through map changes (each waits for the other), route/travel notices and
  an ARC energy readout. The preview launcher installs and uninstalls the mod, backs up saves and collects logs.

## Limitations and testing

This is still a preview, with known gameplay gaps:

- Anchors picked up by the guest can remain on the host and be deposited twice.
- Some anomalies are not visible to the guest (seen: the noisy car-repairing one and the "tictac"), and weather and time
  of day were different for host and guest in the October 24 hand play.
- Tutorial steps completed by the guest alone are not shared with the host.
- Re-entering through the driver's door showed the driver's pose once in hand play; automated tests have not reproduced it.
- Driving and route planning remain host-only. Detailing and buying quirk hints are also host-only, and the Chrono
  Dilator is disabled in co-op.

A full expedition (garage, a junction, two zones and back) was played by hand with a guest on October 24 with no mod
errors or crashes. Version 0.0.7 addresses join-buffer overflows, guest seating and collision after junction travel,
key-handling crashes and synchronization stalls. Automated two-instance scenarios cover these systems, but passing those checks does not
replace further human playtesting. Recorded results are in [NOTES.md](NOTES.md); the runner and test-copy workflow are
documented in [docs/TESTING.md](docs/TESTING.md).

## Building from source

Windows only. Native builds need Visual Studio C++ Build Tools, Rust and an Epic-linked GitHub account for UE4SS's
Unreal headers. Follow [docs/DEVELOPING.md](docs/DEVELOPING.md) for prerequisites, the pinned UE4SS build and test copies.
Its Lua-only setup uses a matching prebuilt native DLL.

```powershell
git clone https://github.com/ikeepcalm/pacific-together.git
cd pacific-together
git -c url."https://github.com/".insteadOf="git@github.com:" submodule update --init --recursive
tools\build-native.cmd
```

Use a short checkout path and Git long-path support. The HTTPS rewrite avoids the submodules' SSH-key requirement.

## Contributing

[docs/TASKS.md](docs/TASKS.md) tracks remaining work and the disposition of earlier task IDs. Check the code and open
PRs before claiming a task with a draft PR named after its id. Setup and validation: [docs/DEVELOPING.md](docs/DEVELOPING.md)
and [docs/TESTING.md](docs/TESTING.md).

MIT license. This repository contains no game files.
