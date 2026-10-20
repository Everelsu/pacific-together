Pacific Together - dev preview (not a release)
==============================================

Two-player online co-op mod for Pacific Drive. This is an early build for the developers and friends only.
Game build: Steam v1.15.0 (build 21896301). The installer refuses any other build.

What works in this build
- The guest joins the host by IP address straight from the main menu.
- Both players see each other's bodies and name tags, in the garage and out on a run.
- The guest follows the host when the garage reloads and rejoins on its own if a map load drops it. Starting a run
  and coming back from one with a guest connected are still being tested.
- The guest's own saves are never written while joined. Only the host's save game is used.
- Pausing and the Chrono Dilator don't freeze the game while a guest is connected.

Not done yet (expect oddities)
- The car: only the host drives, and the guest can't ride along yet.
- Loot, items, world changes and the run's state aren't synced yet. What the guest picks up or does may not
  show up for the host.
- After the guest leaves or crashes, its character may stay standing in the host's world (being fixed).

Install and start (both players, with the game closed)
1. Unpack this zip anywhere.
2. Double-click launcher.cmd. Check the game folder (Browse... if your game is on another drive). Enter the host's IP
   if you are the guest, or leave it empty if you are the host. Press Play.
   The launcher installs the mod, then starts Pacific Drive through Steam. It remembers both fields for next time.
   The first install of each build backs up your saves to Documents\PacificDrive-saves-backup-<date>.zip.
Without the launcher: install.cmd (host) or install.cmd -Join <host IP> (guest), then start the game from Steam.
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
