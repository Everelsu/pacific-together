Pacific Together - dev preview (not a release)
==============================================

Two-player online co-op mod for Pacific Drive. This is an early build for the developers and friends only.
Game build: Steam v1.15.0 (build 21896301). The installer refuses any other build.

What works in this build
- The guest joins the host by IP address straight from the main menu.
- Both players see each other's bodies and name tags, in the garage and out on a run.
- The guest follows the host through every map change: starting a run, the gateway home, death, run failure, and the
  host's save and quit. The guest's screen holds still for a few seconds while the host loads, then it loads the
  same map (no trip through the main menu). If the guest's game drops or crashes, the host keeps going and the guest
  can join again.
- The car: the host drives; the guest gets in through the passenger door (the game's own door) and rides along,
  smoothly, and leaves with the X key. The guest's dashboard shows the host's fuel and battery; car parts the host
  installs or removes, their health, fuel and battery match on both sides.
- Loot: the guest sees the host's lootable containers and items in the same places with the same contents. Taking
  from or putting into a container, the car trunk or garage storage changes it for both players within a second. An
  item picked up from the ground disappears for both; whoever took it has it in their own backpack.
- The run: the guest sees the same time of day, weather, instability, storm and gateway as the host, and the host's
  anomalies in the same places (updated a few times a second).
- Health: each player sees the other's health under their name tag. The guest takes damage and radiation and heals
  normally. When the guest dies, the screen goes black for a few seconds and they come back at the car with full
  health; the host's run goes on. When the host dies, the run fails for both, as in the normal game.
- The guest's backpack is kept by the host next to the host's save and comes back when the guest rejoins the same save
  under the same player name. When the guest dies, their items drop as a crate where they fell; either player can loot it.
- Story: missions, radio and cutscenes play for the host only; the guest is a bystander.
- The guest's own saves are never written while joined. Only the host's save game is used.
- Pausing and the Chrono Dilator don't freeze the game while a guest is connected.

Not done yet (expect oddities)
- Only the host drives. The guest's speedometer stays at zero. Wipers, horn, radio and flat-tyre status aren't synced.
- Items are rebuilt on the other side as new: durability, upgrades and colours of moved items aren't kept.
- Anomalies act on the guest only partly (grabbing, shocks and stealing may look off). Some rare ones aren't synced.
- Items in the guest's death crate lose their grid layout, and the other player's copy of them loses durability.
- Scrapping wrecks and the abandoned cars' parts aren't synced yet.
- The guest's backpack is stored per player name and per host save slot; a different slot starts the guest fresh.
- The guest can't use the garage stations, plan the route or summon the gateway yet.

Install and start (both players, with the game closed)
1. Unpack this zip anywhere.
2. Double-click PacificTogether.exe. If Windows SmartScreen says "unknown publisher", press More info, then Run anyway
   (the app is not code-signed yet). Check the game folder (Browse... if your game is on another drive), choose
   "I am the host" or "I am the guest" and type the host's address, then press Install & play.
   The app installs the mod, then starts Pacific Drive through Steam. It remembers your choices for next time.
   The first install of each build backs up your saves to Documents\PacificDrive-saves-backup-<date>.zip.
   The app also has tabs for what's new, the known limitations (the lists above) and a playtester guide, and buttons to
   uninstall, open the log folder and collect your logs into a zip on the Desktop.
Without the app: install.cmd (host) or install.cmd -Join <host IP> (guest), then start the game from Steam.
Starting from Steam directly also works after an install; it uses the last IP you set.

Play
- Host: load your save. The game now accepts one guest on UDP port 7777.
- Guest: just start the game. At the main menu it connects to the host by itself.
- Both players need the same zip. A mismatch is refused with a message saying what differs.
- You need a network path between you. The easiest is Tailscale (tailscale.com, free): both install it and sign in,
  and the guest uses the host's 100.x.x.x address. Port forwarding UDP 7777 on the host's router also works.
- On the first host session Windows asks whether Pacific Drive may use the network: allow it. If the guest still
  can't connect, allow Pacific Drive on both Private and Public networks in Windows Defender Firewall.

Uninstall and restore
- install.cmd -Uninstall removes UE4SS and the mod (the whole ue4ss folder, including any other UE4SS mods).
- To restore saves, close the game and unzip the backup over %LOCALAPPDATA%\PenDriverPro\ (it holds the Saved folder).

When something breaks
- Send PenDriverPro\Binaries\Win64\ue4ss\UE4SS.log (from both players if you can) and say what you were doing.
- Don't send crash reports to Ironwood Studios for a modded game. The mod switches the game's own crash upload off.
