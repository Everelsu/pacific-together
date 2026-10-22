# PT2 upgrades: car upgrades and quirks in co-op

Code: `mod/PacificTogether/Scripts/upgrades.lua` (new, in FEATURES), scenario `upgrades` (`-Fixture garage`), mutation `noupgrades`.
No edit to car.lua or carfeel.lua. Messages: `g.up.a` (provider event), `g.up.f` (part function), `g.up.i` (interior light).

## Observations
- Capacity: batteries and tanks are ordinary car parts (`Attachments.BackSeatRight` battery, `BackSeatLeft` tank). car.lua's state message installs
  them on the guest, and the guest's own `BP_CarManager` aggregate (`AggregateBatteryMax`, `AggregateFuelMax`) follows within ~3 s. Live check: Large
  battery 80 -> 100, Basic2 tank 50 -> 75 on host and guest. The dashboard battery bar (`BP_CarPart_Internal_LimBox`) reads the same aggregate.
  `SetItem` on a slot that does not accept the part (window slot, battery) silently leaves the slot empty.
- Abilities live in `BP_CarManager.AbilityContainer` (4 slots; `AddAbility(slot, FAbilityData)`, `SetAbilityPressed(slot, bool)`, available list from
  `GetAvailableAbilities`, each entry `{AbilityClass, SourceObject = the part's ItemInstance}`). The host's press runs the `AB_*` ability, which
  - calls `BP_AbilityProviderComponent:DoAbilityStarted/Ended`, whose delegates the part binds (Boost `BP_Attach_Util_Ability_Boost_Base`, Juke,
    Power Grip, Spotlight): flame, speed lines, sparks, nitro sound all start there;
  - or calls a function on the part directly: jump rack `onJumpStart`, shields `OnAbilityStart/End` (Base, Bracer and Impact each have their own),
    bubble shield `OnAbilityStart/End`, anti-gravity `OnStart/OnStop`, Chrono `OnAbilityStart/End`.
  An ability needs battery (`Drain All Batteries` by the initial cost): a drained car does nothing. A held press must be released before the next press.
- Slot index in a press applies to every ability in that slot (Jump and Juke in one slot fire together). `AbilityContainer.SelectedAbilities` stays empty;
  the abilities are in `AbilitySlots`.
- Guest before this lane: the guest has the same part actors, and nothing happens on them (boost flame, sounds, shields) because the AB code never runs there.
- Quirks are status effects: `SE_Quirk_MixAndMatch` (condition + behaviour, added to a part item through `BP_StatusEffectManager:AddItemStatusEffect`) and
  `SE_FAF_*` fire-and-forget ones; both end in a `QB_*` behaviour object (`StartBehavior`) that calls the car manager (`StartHornHonk`, `SetCarLightsOn`,
  `SetDoorState`, wipers, radio, ignition, `car:ToggleInteriorLight`). `SE_FAF_*_DIRECTOR_*` objects exist in the manager on both sides.
  Live: `QB_ToggleLights` / `QB_ToggleWipers` on the host reach the guest through car.lua and carfeel.lua. `QB_ToggleInteriorLights` did not
  (`CarTopLightOnOff`): added here.
- The guest's game has its own quirk objects (a `SE_Quirk_MixAndMatch` director and the FAF directors in its status manager).

## Derived
- Host: hook the provider functions (only for the provider-driven part classes) and the direct part functions; send class name plus function or flag.
  Guest: find the same part class attached to the host's car, call the same function; for provider events a bare ability object of the part's ability class
  (`StaticConstructObject`, class from `GetAbilityStatus.MyAbility`) is the argument. No ability runs on the guest, so no physics or cooldown logic.
- Guest presses on `AbilityContainer:SetAbilityPressed` are dropped (abilities are the driver's).
- Guest quirks: every 2 s on the guest the quirk status effects (`SE_Quirk_MixAndMatch`, `SE_FAF_DoQuirkBehavior` family, directors included) are removed
  from its status manager.

## Not covered
See the report; filled in after the runs.
