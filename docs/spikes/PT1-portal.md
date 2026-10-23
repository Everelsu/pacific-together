# pt3-portal: exit portals and story pickups on the guest (2026-10-24)

## Observations
- Steam play: guest logged `SerializeNewActor failed to find/spawn actor` for level-placed actors of `<zone>_Mission_Sub`
  (exit portals, Q01 radio bits, Tesla, grabbers).
- Zone fixture, scenario `portals` before the fix (`20261023-234014-pt3-portal-portals`, 18/19): portals match (guest had
  its own copies in time), the radio bits did not: host 1, guest 0.
- Probe (guest does not destroy its own copy, only logs): the guest's copy had Role 0, then the host's channel bound to it
  and it matched (`20261023-235701-pt3-portal-portals-probe`, 19/19).
- Fixed (`20261024-000105-pt3-portal-portals`, 20/20): guest grab of the bits reaches the host as `g.act.grab`, the host's copy
  runs ShortGrabComplete (its ScanObject = host quest), `SuccessfullyGrabbed` true on the host.

## Derived
- The warning is the guest having destroyed its own level-placed copy (world.lua cleanGuest / story.lua guestProps) before
  the host's actor channel opened: a stably named actor must exist on the client to be bound. Portals worked in the fixture only
  because the channel opened within cleanGuest's 5 s grace; over Steam it opened later.
- Fix: host sends the names of its portals and story props with the 1 s state (`keep`); the guest destroys only copies the
  host does not have.

## Guesses / unknowns
- Tesla and grabbers have the same cause (hazards: the guest only disables their tick, never destroys level-placed ones, so
  something else is wrong there: lane pt3-anom).
- Not seen in real Steam play; the Steam timing was not reproduced (fixture channel opens early).
- The vanish on the guest is the game's own SuccessfullyGrabbed on the guest copy; the host's mesh is destroyed locally.
- Gateway travel with both players was not re-run (runloop unchanged).
