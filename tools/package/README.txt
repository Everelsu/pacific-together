Pacific Together - development preview 0.0.7
==========================================

Two-player co-op for Pacific Drive. Developer/friend preview; no public release before 1.0.
Both players need this mod version (protocol 3) and Steam v1.15.0, build 21896301.

What works in this build
- Join through Steam invites/friends or direct IP. Steam traffic between two accounts was verified October 23.
- The host drives; the guest uses the driver's door handle to enter the passenger seat and X to leave.
  Parts, damage, fuel, battery, storage, repairs and part swaps are shared. The ARC sits behind the seats.
- Shared containers, pickups, wreck scrap, garage storage, weather, storms, gateways and many anomalies.
- Both players have visible animated bodies, held items, name tags, health, map/HUD markers and middle-mouse pings.
- Guest damage, radiation and death: respawn at the car with items dropped in a recoverable crate.
  The host keeps the guest backpack per save slot (SteamID for Steam joins; player_id.txt for direct IP).
- Shared run travel and failure; host missions, radio dialogue, research and upgrades reach the guest.
  The guest can fabricate, research, buy garage upgrades, shred parts and cure diagnosed car quirks.
- Zone props, car paint, flat tyres, radio, lights and supported car-upgrade effects are mirrored.
- Host Esc pauses both players; guest Esc opens their menu. Loading/seat prompts and End/F8 control reset are available.
- The guest's own saves are protected while joined. The launcher backs up saves and collects logs.

Not done yet (expect oddities)
- A guest-picked anchor can remain on the host and be deposited twice.
- Guest-only tutorial steps do not advance the host. Guest re-entry once showed the driver's pose in hand play.
- Driving, route planning, Detailing and quirk hints remain host-only. Chrono Dilator is disabled in co-op.
- Mixed DLC ownership, Expeditions, remaining anomalies and a full long-session regression need further validation.
- Direct IP works without Steam networking; keep the guest's ue4ss\Mods\PacificTogether\player_id.txt to keep
  their backpack on the host.
- Some older edge cases still need retesting: item tints/upgrades and death-crate layout, gas pump handles and
  lockboxes, guest prop/tool cure effects, and visual/audio polish. Automated passes are not proof of every hand-play path.

Install and start
1. Close the game and unpack the preview anywhere. Open PacificTogether.exe and check the game folder.
2. Steam joining: BOTH players select Host (no IP) and Install & play. The actual host loads a save; the guest uses
   Join game in Steam's friends list or accepts an invite while the game is running.
3. Direct IP: the host selects Host; the guest selects Join and enters the host's reachable address.
   Load a save on the host; the guest connects from the main menu. Direct IP uses UDP 7777.

Command line: install.cmd (host/Steam), install.cmd -Join <host IP>, or install.cmd -Uninstall.
The launcher is not code-signed. Install & play starts PenDriverPro\Binaries\Win64\PenDriverPro-Win64-Shipping.exe directly (Steam only needs to be running); starting it through Steam works too and uses the same saved join setting.
See GUIDE.md for connection troubleshooting, backups and bug reports; CHANGELOG.md for version history.

Uninstall and restore
Uninstall removes the entire ue4ss folder, including any other UE4SS mods, but does not delete saves.
The first install of each build backs up saves to Documents\PacificDrive-saves-backup-<date>.zip.
To restore, close the game and extract that backup over %LOCALAPPDATA%\PenDriverPro\.

When something breaks
Use Collect logs in the launcher and include both players' zips, their roles, the time and reproduction steps.
Logs: PenDriverPro\Binaries\Win64\ue4ss\UE4SS.log. Copy them before restarting; the log is overwritten.
Report modded-game crashes to this project. The mod blocks the game's crash uploader and writes its own crash marker.
