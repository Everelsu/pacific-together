# PT6 radio: guest radio and shared music

Lane `radio`, 2026-10-25. Module `mod/PacificTogether/Scripts/radio.lua` (replaces the radio half of `carfeel.lua`), messages
`g.radio.i` (guest intent), `g.radio.s` (host state), `g.radio.have` (guest's custom files), protocol 3 to 4.
Scenario `radio` (rendered only), mutation `noradio`. Test pair `C:\PTLanes\radio`, port 7861.

## Observations (live game, 0.0.7 build 21896301, `pacific-game` MCP)

- Radios: `BP_MusicManager_C` (`GarageStereoOn`, `MusicVolume`, `radioOn`, `RadioPlaylist`, `DefaultRadioPlaylist`, `SkipTrack`,
  `SetRadioVolume`, `SetGarageStereoOn`, `CurrentRadioTrack`) and `BP_CarManager_C` (`CarState_RadioOnOff`, `SetCarRadioOnOffState`).
  The car's `BP_CarPart_Internal_Radio_C` and the garage's `BP_Garage_Stereo_01_C` each own a `BP_RadioComponent_C` with
  `ChangeChannel(dir)`, `VolUp`, `VolDown`, `VolSetTo`, `TogglePlayback`; the part has `ToggleRadio` (interaction).
- Two `BP_CarPart_Internal_Radio_C` exist in the garage on both sides: the installed one (attached to the car) and a loose copy with no
  parent. `ChangeChannel` on the loose copy does not reach the hook and does nothing. Pick the one with `GetAttachParentActor()` valid.
- The part's own `ToggleRadio` on a guest standing outside the car did not change `CarState_RadioOnOff` (carfeel seats the guest first).
- `RadioPlaylist` (61 entries, the same objects as `DefaultRadioPlaylist`) is a queue: `SkipTrack` (or a station change) takes a random
  front entry (not the last), removes every copy of it and appends it; the last entry is the playing track (`CurrentRadioTrack`).
  Seen: picks at index 3 and 10. `mm.RadioPlaylist = mm.DefaultRadioPlaylist` copies the whole array from Lua (elements can be
  assigned, the array cannot be resized). Filling every front entry with one track makes `SkipTrack` play exactly that track within
  about 0.3 s; the list then has 2 entries (all copies were removed), so it must be restored from the default.
- `CurrentRadioTrack` is valid only with the audio engine (headless `-nosound`: never). It was valid with the radio off too.
- Track identity: built-in tracks are `/Game/Music/MT_<name>` (`Title`, `Artist`, empty `ExternalUrl`). Custom tracks are `MusicTrack`
  objects under the music manager's `DirectoryMusicLibrarySource` with `ExternalUrl` = `file://C:/<game>/PenDriverPro/Custom/Radio/<file>`
  and `Title` = file name without extension.
- Custom music: folder `<game dir>\PenDriverPro\Custom\Radio` (opened by `OpenLocalMusicFolder`, readme in it): `*.mp3 *.wav *.ogg *.m3u
  *.m3u8` and symlinked folders. Setting `DrivingGameUserSettings.RadioSource` (int, 0 default) with `RadioSourceTermsAcknowledged`;
  with `RadioSource=1` in `GameUserSettings.ini` the library scanned the folder at start (`LogMusicLibrary: Finished scanning for music! Found
  4 possible entries`, `GetNumLocalFilesScanned` 4); with 0 there was no scan. `RescanLocalFiles` rescans.
- In the probe the scanned files never appeared in `RadioPlaylist` (still the 61 built-in entries; tried: rescan, `InitSettings`, radio
  on, skips, `OnSongFinished`; also in a rendered session). The one time `MusicTrack` objects with an `ExternalUrl` existed (fake mp3 files,
  headless), they were not in the playlist either. Why the real game adds them is unknown (see unknowns).
- A synthetic `MusicTrack` (`StaticConstructObject`, `ExternalUrl` set) forced through `SkipTrack` becomes `CurrentRadioTrack`; the game then
  logged `LogWmfMedia: Error: Failed to open or read media file /C:/.../ptA.wav` and `Song finished` (my generated 16-bit mono wav, or the path
  form, is not opened by WmfMedia). The game moves on by itself after a failed file.
- Reading a destroyed synthetic track from the console crashed the host once (access violation); the scenario keeps its tracks in
  `DefaultRadioPlaylist`.

## Derived

- Interaction hook: the interaction events call manager state, so state polling is the hook (as carfeel did): `GarageStereoOn`,
  `CarState_RadioOnOff`, volume are compared with the last sent or received value. Station changes are caught with a hook on
  `BP_RadioComponent_C:ChangeChannel` (guest only; direction and whether the owner is the stereo or the car part).
- Host authority (the guestact pattern): guest local change sends an intent, the host applies it with the game's own functions
  (`SetGarageStereoOn`, `SetCarRadioOnOffState`, `SetRadioVolume`, the host radio component's `ChangeChannel`), then sends the resulting state to
  all guests (also on a 5 s heartbeat, on join and after a map load), so a refused intent is corrected.
- Same track: the host sends `trk=<key>` whenever its current track changes; the guest plays that key with the fill-and-skip trick, then
  restores its playlist from the default with that track last. On join and after a map load the host restarts its own track and sends
  `r=1`, so both start it at the same moment.
- Position: no seek from Lua (Wwise Blueprint API has none; only `mus_radio_seekNewStation` random seek). "Roughly the same position" comes
  from starting the same track on both sides together (join, map load, every track change); a heartbeat re-plays the host's track when the
  guest's differs. Drift inside one track cannot be measured or corrected from Lua, and nothing is promised beyond that.
- Matching rule for custom files: **by lower-case file name** (key `L:<name>`). A content hash needs the whole file read on both sides at
  every join and the game itself identifies a custom track by its file; the name is free (the `ExternalUrl`) and reliable between two
  players who share files. Risk: two different files with one name on the two sides are treated as the same song (nothing breaks, they
  just hear different audio). The guest sends the key list of the custom tracks it knows (`g.radio.have`); the host skips (`SkipTrack`, at most
  12 times, 1.5 s apart) while its current track is a custom file the guest lacks, never announces it, and records a `miss` the guest sends
  when a key it cannot find arrives. The guest never keeps a track the host did not announce (the host's track overrides). If a playlist held
  only custom files the guest lacks, the host would stop after 12 skips and the guest has nothing to apply: it keeps its own track.
  Built-in tracks exist in every copy, so a shared track exists in the normal case.

## Unknowns

- How the game adds scanned custom files to the radio playlist (probe: it did not). `radio.lua` handles keys from any `MusicTrack` with an
  `ExternalUrl` whether they reach `RadioPlaylist` or not, but a real file played on both sides was not heard or tested.
- Whether a custom file the guest has but the host lacks is ever picked by the guest's own radio: it is overridden within 5 s at the latest.
- Audible output and song position were not heard by a human.
