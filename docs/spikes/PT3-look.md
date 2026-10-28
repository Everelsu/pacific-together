# PT3-look: what the guest sees and hears wrong (first Steam play, #7 #13 #10 #2)

> Historical research; see the [index](README.md) for current implementation and later evidence.

## Observations
- #7 Impact Hammer = BP_Tool_Target_Breaker. Held, it has a visible `/Engine/BasicShapes/Cylinder` StaticMeshComponent (HammerRotator child,
  scale 0.1 x 0.1 x 1, bounds radius 70.7) next to the real parts (SM_Tool_Breaker_01 radius 67). hands.lua took the biggest part as the
  base, so the mirror was the plain engine cylinder (default grid material) with every other part positioned relative to it.
  Scenario hands phase 8 "hammer" failed before the fix (host_sees_hammer / guest_sees_hammer, run 20261023-232005-pt3-look-hands).
- #13 TextRender draws offline fonts only (UFont FontCacheType 0, 256 Latin glyphs): RobotoDistanceField (default), PixelDriver_Regular_Offline,
  alarm_clock_Font_Offline. Every other font the game has (Roboto, Inter, Montserrat, ...) is a runtime font (type 1), which TextRender cannot draw.
- #2 BP_PlayerCarNew binds Chassis/wheel OnComponentHit to HandleScrapingFX, which spawns BP_CarScrapeFX_C (posts sfx_car_scrape_start on its own
  Ak, stops with the owner).

## Derived
- #7 fix: hands.lua heldParts skips meshes under /Engine/.
- #13 fix: TextRenderComponent asserts Offline fonts (UE source TextRenderComponent.cpp:317, 697 "Runtime fonts can't currently be used here"), so no
  shipped Cyrillic font works on it. Names with a UTF-8 lead byte >= C4 are drawn by a UMG TextBlock (default font, as the UI hint) at the
  projected head position (nametag.lua); TextRender text is empty for them. Latin names unchanged. Look not seen (headless): position/scale/alpha
  unverified by eye; scenario checks text and visibility only.
- #2 fix: the guest destroys BP_CarScrapeFX_C actors every 100 ms (carfeel.lua); the host still hears real scrapes.

## Results
- hands 64/64 (20261023-233838-pt3-look-hands); mutation engmesh fails host/guest_sees_hammer (20261023-235014-pt3-look-hands-engmesh).
- carfeel 42/42 (20261024-004406-pt3-look-carfeel); mutation noscrapedrop fails guest_scrape_fx_dropped (20261024-000658-...).
- nametag 23/23 (20261024-002803-pt3-look-nametag); mutation nocyr fails host_cyrillic_name_in_umg (20261024-004131-...).

## Guesses
- #2 cause: the guest's posed car copy collides with the ground and takes the hit events; not seen live (no repro without two players driving).
- #10 cause unknown. Only BP_Door_Single implements the harvest audio interface (Start/EndHarvestingAudioResponse); the scrapper's own loop is
  ShredderPlayAK/ShredderStopAK on its Ak. Candidates: a target destroyed on the guest by loot.lua (host removed the part) while the scrapper was
  running, or a guest scrap of a door copy whose harvest loop never gets its End call. NOT fixed.

## Unknowns
- #10 needs a guest scrapping a door / resource / car part with sound watched (Ak component state); not done tonight.
- The nametag Latin transliteration has no scenario (the test mod cannot reach the shipping module); verified by loading the code in a live game.
