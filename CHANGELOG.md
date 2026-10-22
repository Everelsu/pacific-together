# Changelog

What changed in Pacific Together, in plain words. Newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Builds before 1.0 are previews for the developers and friends.

## [0.0.5] - unreleased

### Added
- You see where the other player is: a marker on the ARC map in the car, and a blue marker with their name and distance on the HUD once they are more than 30 m away (closer, the name tag shows).
- Car upgrades show for the guest: when the host fires nitro, the jump rack, the shields or the juke, the guest sees and hears
  them on the car; bigger batteries and fuel tanks grow the guest's gauges too; the interior light follows the host. The
  Chrono Dilator still does nothing in co-op. The guest's car no longer rolls its own quirks.
- A proper launcher app (PacificTogether.exe) replaces the small window: pick Host or Join, install, uninstall, open the
  log folder, collect your logs into one zip on the Desktop, and read what's new, what is not done yet and how to connect.
- An in-game overlay: "Pacific Together" and its version at the bottom right, the session status with ping, and a short
  feed of what the other player does.
- The launcher shows the build in this download and the build installed in your game.
- The guest's game shows the host's progress while joined: garage upgrades, research, the route on the map and the
  logbook. A failed run costs the guest items too, as it does the host.
- More anomalies act on the guest: Leech leaps, BombRock blasts and Physics Grabbers. Tourists stop while either player
  looks at them.
- The story is shared: the guest sees the host's mission and objectives on the HUD and in the journal, and hears the
  host's radio transmissions and voice lines with subtitles.
- The guest can repair the car with putty, charge its battery, refuel from a fuel can, deposit anchors and pick the
  gateway at the ARC.
- Abandoned cars and their parts are shared; scrapping and siphoning fuel happen once for both. Handed-over items keep
  their durability, fuel and battery. Opened and emptied containers look that way for both players, and garage storage
  is really shared now.
- The guest's backpack is kept by the host and comes back when the guest rejoins. A guest who dies drops their items in a
  crate that either player can loot.

- The guest's tools work on car parts and abandoned cars: Scrapper and Electric Scrapper, Hammer and Magnetic Hammer,
  Prybar, Explosive Cutter, Blowtorch and putty. The part breaks or heals for both players and its scrap drops once.
- The guest can take parts off the car, install parts, refuel and use the car's storage; the host's car takes the change.
- The garage stereo and the car radio are shared: either player switches them, changes the volume or skips a track.
- Riding along feels alive: the guest hears the engine follow the host's driving and sees the speedometer, horn,
  headlights and wipers.
- Part Stealers go for the guest too: one near the guest on foot takes a random item from their backpack. A Loot
  Creature's push hurts and shoves the guest.
- The guest sees the host's garage stations (fax machine, Part Shredder, Destabilizer and the rest), and the garage
  doors open and close for both players, from either player's button press.
- Join through Steam: the host's game opens a friends-only lobby, the guest uses "Join game" in the friends list or
  an invite, and names come from Steam (not tested between two PCs yet; joining by IP works as before).
- The guest's journal lists the host's finished missions, and a quest item the guest picks up counts for the host.
- Ping: look at something and press the middle mouse button. Both players see a marker there for about 8 seconds with
  your name, the distance and, for an item or container, its name, and hear a short HUD sound. One ping per player.
- The guest sees the host's world as the host does: the zone's buildings, props, doors, fences and crates (they only existed
  on the host before), the garage's Fig decorations, and the paint and decals of the car's parts.

### Fixed
- The host's game crashed when the host pressed Esc with a guest connected (with "Pause game while in menus" on or off).
  The real cause was the guest's controller on the host having no input object; fixed. The host's pause menu pauses
  the game for both players.
- The garage doors never opened in co-op, so the car couldn't leave the garage.
- A guest who was stuck "dead" after a car door or the game's own kill lost their materials and got no death crate.
  Every guest death now ends in the death crate with crafted items intact, and the guest comes back.
- An item the guest dropped existed twice (one for each player to pick up).
- Loot in abandoned cars' trunks and truck beds wasn't shared.
- Dropped items floated in the air on the guest's screen.
- The guest's repairs and scrapping on car parts snapped back and left ghost items on the guest's side.
- Pressing X to leave the car left the guest stuck inside on their own screen.
- The ARC device between the seats blocked the starter key and some panels; it now sits behind the front seats.
- The overlay moved higher; it overlapped the game's HUD at the bottom right.
- The guest "died" a few seconds after every map change, dropping their backpack as a crate. Fixed.
- A failed run's item loss for the guest could be undone when they rejoined. Fixed.
- An anomaly hitting the guest took the host's health instead of the guest's. It now hurts the guest.

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
