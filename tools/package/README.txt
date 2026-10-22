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
- The car: the host drives; the guest gets in by tapping the DRIVER's door handle (the passenger door doesn't let you
  in yet) and rides along in the passenger seat,
  smoothly, and leaves with the X key. The guest's dashboard shows the host's fuel and battery; car parts the host
  installs or removes, their health, fuel and battery match on both sides.
- Loot: the guest sees the host's lootable containers and items in the same places with the same contents. Taking
  from or putting into a container, the car trunk or garage storage changes it for both players within a second. An
  item picked up from the ground disappears for both; whoever took it has it in their own backpack.
- The run: the guest sees the same time of day, weather, instability, storm and gateway as the host, and the host's
  anomalies in the same places (updated a few times a second).
- Anomaly hits on the guest (explosions, shocks, a Leech's leap, a BombRock blast, a Physics Grabber) hurt the guest,
  not the host. Tourists stop creeping while either player looks at them. A Part Stealer near the guest
  on foot takes a random backpack item; a Loot Creature's push shoves the guest. Spark Towers on the guest are untested. Car parts taken by a Part Stealer vanish for both.
- Health: each player sees the other's health under their name tag. The guest takes damage and radiation and heals
  normally. When the guest dies, the screen goes black for a few seconds and they come back at the car with full
  health; the host's run goes on. When the host dies, the run fails for both, as in the normal game.
- Abandoned cars and their parts are there for both players; scrapping a part or siphoning fuel is shared. Items you
  hand over keep their durability, fuel and battery charge. Opened and emptied containers look that way for both.
- The guest's backpack is kept by the host next to the host's save and comes back when the guest rejoins the same save
  under the same player name. When the guest dies, their items drop as a crate where they fell; either player can loot it.
- The guest can work on the car and the ARC: all tools (Scrapper, Electric Scrapper, Hammer, Magnetic Hammer, Prybar,
  Explosive Cutter, Blowtorch, putty) on car parts and abandoned cars, take off and install parts, charge the battery,
  refuel, deposit anchors and pick the gateway at the ARC screen. The host's car and ARC take the change within about a second.
- Garage: the doors open for both players from either player's button; the guest sees the host's garage stations.
  The garage stereo and the car radio are shared both ways.
- Riding along: the guest hears the engine follow the host's driving and sees the speedometer, horn, lights and wipers.
- The ARC device sits behind the front seats: the driver reaches the starter key, the passenger turns round to use the ARC.
- Progress: while joined, the guest's game shows the host's garage upgrades, research, route and logbook. A failed run
  costs the guest items the same way it costs the host.
- Story: the guest sees the host's active mission, objectives and finished missions on the HUD and in the journal, and
  hears the host's radio and voice lines with subtitles. A quest item the guest picks up counts for the host.
- Finding each other: the other player shows on the ARC map, and as a HUD marker with name and distance past 30 m.
  Ping: look at something and press the middle mouse button; both see a marker there for 8 seconds.
- An overlay at the bottom right shows the mod version and, during a session, who is connected and the ping, plus a short
  feed of what the other player does (joined, got in the car, took items from the trunk, ...).
- The guest's own saves are never written while joined. Only the host's save game is used.
- The Chrono Dilator doesn't slow time while a guest is connected. When the host opens the pause menu, the game pauses
  for both players.

Not done yet (expect oddities)
- Only the host drives. Flat-tyre status isn't synced. Engine and radio sound for the guest have not been listened to by
  a person yet; tell us if the engine pitch doesn't follow the host or a skipped track plays a different song.
- Moved items lose their tints and upgrades (durability, fuel and battery are kept).
- A Physics Grabber only makes the guest drift towards it (not a real grab), and a blast that catches both players can
  hide part of the host's own damage.
- Items in the guest's death crate lose their grid layout, and the other player's copy of them loses durability.
- Gas pump handles, lockboxes and anchors lying in the world aren't synced yet. Smashing map props with a hammer or
  prybar as the guest is the guest's own; the cure effects of repair tools (dirt, seal, bulb, electronics) too.
- The guest's backpack is stored per player name and per host save slot; a different slot starts the guest fresh.
- Only the host's progress counts for the story; quest tasks that check the guest's own car or health don't count.
- Car paint and cosmetics, tutorials and expedition progress are the guest's own, not the host's. A map screen that is
  already open may need reopening to show the host's route.
- The overlay uses the engine's plain font, stays visible over the pause menu, is English only, and its lines vanish without fading. A host map change
  shows the guest as leaving and rejoining.
- After a failed run the guest's game sometimes crashes while it follows the host back. Start it again and rejoin;
  the host keeps going and the guest's backpack is kept.
- If the host charges the ARC, the host should look at the ARC screen once so the guest sees the gateway choices.
- Not tried with a real mouse and keyboard yet (please check tonight): the X key to leave the car, opening the trunk as
  the guest, using repair putty or a fuel can on the car as the guest, the guest's gateway choice on the ARC screen,
  and the host abandoning a run from the pause menu with the guest connected.
- The guest can't use the garage stations or plan the route yet.

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
- Joining through Steam (new, not tested between two PCs yet): both players install as the HOST (no IP). The host loads
  a save; the guest opens the Steam friends list and picks "Join game" on the host, or accepts the host's invite. Names
  then come from Steam. If it doesn't connect, use the IP way below and tell us.
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
