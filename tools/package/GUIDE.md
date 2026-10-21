# Playtester guide

Thank you for testing. Pacific Together lets two people play one Pacific Drive save online. The host loads their save and
the guest plays in the host's world. You both need the same download, the same game build (Steam v1.15.0) and Pacific Drive
on Steam. Only the host needs the Whispers in the Woods DLC.

## Connect

Your computers need a network path to each other. Pick one.

### Tailscale (easiest)
- Both of you install Tailscale (tailscale.com, free) and sign in. The host shares their machine with the guest, or you both
  join the same tailnet.
- The host reads their 100.x.x.x address in Tailscale. The guest types that address into the Join box here.

### Port forwarding
- The host forwards UDP port 7777 on their router to their PC and shares their public IP address.
- The guest types that address into the Join box.

### Windows Firewall
- The first time the host starts a session, Windows asks if Pacific Drive may use the network. Allow it.
- If the guest still can't connect, open Windows Defender Firewall on both PCs and allow Pacific Drive on Private and
  Public networks.

## Play

- Both of you: close Pacific Drive, pick Host or Join on the Play tab and press Install & play.
- Host: load your save. The game accepts one guest.
- Guest: just wait at the main menu. The game connects to the host by itself.
- If the join is refused, the message says what differs (mod version, game build). Both need the same download.

## What to report

- What you were doing, what you expected and what happened. A short screen recording helps a lot.
- Whether you were the host or the guest, and whether it happens every time.
- Your logs: press Collect logs on the Play tab. It writes a zip to your Desktop. Send it from both players if you can.

## Where the logs are

- `PenDriverPro\Binaries\Win64\ue4ss\UE4SS.log` in your game folder (Open log folder shows it).
- After a game crash, a `PacificTogether-crash.txt` in `%LOCALAPPDATA%\PenDriverPro\Saved\Crashes\<crash folder>`. Collect logs
  includes the newest ones.
- Don't send crash reports to Ironwood Studios for a modded game. The mod switches the game's own upload off.

## Your saves

Before the first install of each build the launcher backs up your saves to
`Documents\PacificDrive-saves-backup-<date>.zip`. To restore, close the game and unzip the backup over
`%LOCALAPPDATA%\PenDriverPro\`. Uninstall removes the mod but never touches your saves.
