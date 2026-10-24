# PT1 feel: radios and car feel for the guest

> Historical research; see the [index](README.md) for current implementation and later evidence.

Module `mod/PacificTogether/Scripts/carfeel.lua`, messages `g.feel.r` (radio state, both ways), `g.feel.pl` (playlist order, host to guest), `g.feel.k` (station skip, both ways), `g.feel.c` (car values, host to guest). Scenario `carfeel`, mutation `nofeel`.
Results: pass `20261022-001900-pt1-feel-carfeel` (41/41), mutation `20261022-010210-pt1-feel-carfeel-nofeel` (28/41, 13 feel checks fail).

## Observations
- Radio state lives in BP_MusicManager (GarageStereoOn, MusicVolume, RadioPlaylist, SkipTrack) and BP_CarManager (CarState_RadioOnOff). The game's radio components only call these.
- The guest's replicated car keeps AC_CarAudio and the speedometer part, but its VehicleController is off: GetSpeed and ThrottleInput read 0, so engine/speed sounds and the needle sat at zero.
- UE4SS post hooks do not fire for the Blueprint ReceiveTick of AC_CarAudio or the speedometer. A pre hook on the native AkGameplayStatics:SetRTPCValue fires when the Blueprint calls it and can change the value (`val:set`).
- Headless runs use -nosound: CurrentRadioTrack is never valid and the playlist reshuffles about every second.
- Test mod and shipping mod have separate Lua states: globals are not shared.
- ManualSetIgnition_NoAnim on the guest reaches AC_CarAudio:OnCarIgnitionChanged (engine audio state).

## Derived
- Radios: polled every 200 ms per side against the last value sent or received; a received value is applied and remembered (no echo). The host sends everything when a guest arrives.
- Car: the host captures the veh_engineLoad / veh_speed / veh_speed_direction values the game hands to Wwise and the speedometer arm rotation, plus horn and wipers; the guest swaps them in at the same SetRTPCValue call and in the arm's K2_SetRelativeLocationAndRotation call, and writes vehicle controller throttle input and the throttle accumulator.
- Horn: AC_CarAudio:Call_CarHorn_Active; wipers: BP_PlayerCarNew:ToggleWiperBlades (the variable flips after the animation, about 1-3 s).

## Guesses / unknowns
- Not heard by a human: that a skipped track really is the same song (list order is copied and a skip replayed, but headless has no tracks). Garage stereo audio start after SetGarageStereoOn from the guest is unverified.
- Starter/key sounds (animated ignition) are not replayed: the guest takes the no-animation ignition path from car.lua.
- No turn signals exist in the game.
- Chosen "RPM" check: AC_CarAudio.CurrentSpeed (veh_speed) close to the host's, throttle accumulator, needle roll.
