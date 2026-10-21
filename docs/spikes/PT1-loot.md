# PT1 loot: world-vehicle cargo and dropped items (playtest 1, bugs A and B)

## Observations
- Wreck trunk contents (`BP_TemplatePart_TrunkContents_C`, 24 in the zone fixture) and box-truck cargo (`BP_TemplatePart_TruckBedContainer_C`, not in the fixture) are template parts (kind P) whose items live in the part's ItemInstance container (`BFL_ItemPropertyUtilityFns.GetInstanceContainer`). P sync carried only item spec, pitch, roll, mesh: the guest copy had other contents and changes never travelled.
- Before the fix lootcar failed 21/25 (`20261021-221946-pt1-loot-lootcar`: guest copy lacked the host's items, host kept them). Fixed 24/24 (`20261021-230355-pt1-loot-lootcar`), mutation nocarloot 22/24 (`20261021-231552-pt1-loot-lootcar-nocarloot`).
- Host drops: the guest got one `A` line at drop height and no later position (item hung at z 8209, host rest 8135). dropfall before fix 19/20 (`20261021-231953-pt1-loot-dropfall`); fixed 20/20 (`20261021-233514`, `-233723`, `-233922`), mutation nofall 18/20 (`20261021-232731-pt1-loot-dropfall-nofall`).
- The zone fixture character's pack has 1 slot after one item: the scenario takes what fits.

## Derived
- Part contents go as `;contents` after the part state (same encoding as lootables); the key compared each tick is spec;contents. Host sends `M|id|x|y|z|yaw` for a moving world item.

## Guesses
- Box-truck cargo behaves like TrunkContents (same instance-container calls in its bytecode); not run, no truck in the fixture.

## Unknowns
- One dropfall run failed `guest_drop_on_host_ground` (19/20, `20261021-233100-pt1-loot-dropfall`), then passed 4 times; cause not found.
- The cargo highlight is not hit by a headless aim; the scenario calls the highlight's InteractPressed/Released.
