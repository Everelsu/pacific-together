# Changelog

What changed in Pacific Together, in plain words. Newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Builds before 1.0 are previews for the developers and friends.

## [0.0.5] - unreleased

### Added
- A proper launcher app (PacificTogether.exe) replaces the small window: pick Host or Join, install, uninstall, open the
  log folder, collect your logs into one zip on the Desktop, and read what's new, what is not done yet and how to connect.
- The launcher shows the build in this download and the build installed in your game.
- The story is shared: the guest sees the host's mission and objectives on the HUD and in the journal, and hears the
  host's radio transmissions and voice lines with subtitles.
- The guest can repair the car with putty, charge its battery, refuel from a fuel can, deposit anchors and pick the
  gateway at the ARC.
- Abandoned cars and their parts are shared; scrapping and siphoning fuel happen once for both. Handed-over items keep
  their durability, fuel and battery. Opened and emptied containers look that way for both players, and garage storage
  is really shared now.
- The guest's backpack is kept by the host and comes back when the guest rejoins. A guest who dies drops their items in a
  crate that either player can loot.

## [0.0.4] - 2026-10-21

### Added
- The guest rides in the host's car: in through the passenger door, smooth movement, out with the X key. Car parts, their
  health, fuel and battery are the same for both players, and the guest's dashboard shows the host's fuel and battery.
- Loot is shared: the guest sees the host's containers and items with the same contents. Taking or putting items in a
  container, the car trunk or garage storage changes it for both. An item picked up from the ground is gone for both.
- The run is shared: the same time of day, weather, instability, storm, gateway and anomalies for both players.
- Each player sees the other's health under their name tag. A guest who dies comes back at the car; the host's run goes on.
- The guest stays out of the story: missions, radio and cutscenes play for the host.

### Changed
- Under the hood: a message channel between host and guest carries all of the above.

## [0.0.3] - 2026-10-20

### Fixed
- The guest's field of view could be squeezed to a narrow slit after joining the host. It stays normal now.
- When the game crashes, the mod now writes down what it was doing at that moment, so a crash report says more.

## [0.0.2] - 2026-10-20

### Fixed
- The host getting into the car no longer drags the guest along with them.
- When the host changes map, the guest follows straight into it without a trip through the main menu.

## [0.0.1] - 2026-10-19

First preview.

### Added
- The guest joins the host by IP address from the main menu (UDP port 7777).
- You see each other's bodies and name tags, in the garage and out on a run.
- The guest follows the host through every map change: starting a run, the gateway home, death, run failure and the host's
  save and quit. If the guest's game drops or crashes, the host keeps going and the guest can join again.
- The host can get in and out of the car.
- Only the host's save is used. The guest's own saves are never written while joined.
- Pausing and the Chrono Dilator no longer freeze the game while a guest is connected.
- The game's crash upload to the developer is switched off while the mod is installed.
- The installer checks your game build, backs up your saves before the first install and can remove the mod again.
