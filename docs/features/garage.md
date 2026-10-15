# The garage room (the dressed garage)
**What:** The garage is the room every player lives in: the founder's desk and WRITE CODE laptop, the hire pad, the HQ pad (BUILD, spin-off, the end of every recruit chase) and the door. With the one-building HQ (Wafers) it stays a garage for the whole game. Since 12 Oct it is dressed as a warm startup office from his "image 5" (`silicon-startup/art/`). It has a slatted walnut wall with a glowing rocket sign over the back window, a whiteboard of sticky notes, a server rack, a coffee bar, a lounge with bean bags, trophies, posters, pendant lamps, a duct and track lights. It also has glowing pad edges, warm cream walls with a sage band, and a warm colour grade while the camera is inside.
**How a player reaches it:**
1. Join: you spawn in your garage (see core-loop.md). The dressing is built once per plot in `buildPlot`, right after the garage furniture (`src/ServerScriptService/SiliconCore.server.lua:1120`).
2. Walk in through the door. The client warms the colour grade while the camera is inside any garage, and eases it back out when you leave (`src/StarterPlayer/StarterPlayerScripts/GarageMoodClient.client.lua:26`).
**Files:**
- `src/ReplicatedStorage/GarageLayout.lua`: the room as data, pure. `WINDOWS` :40, `KEEP` (walkway, desk, both pads, door) :54, `PIECES` :62, `check` :168 (every reason a piece would block the game), `lights` :237.
- `src/ServerScriptService/GarageDress.lua`: builds from the layout. `wallFrame` :91, `at` :100, one builder per look (`B.slats` :217, `B.sign` :233, `B.whiteboard` :329, `B.tv` :393, `B.cladding` :436, `B.wainscot` :452, `B.pendants` :535, ...), `dress` :586 (refuses to build if `check` finds a problem).
- `src/StarterPlayer/StarterPlayerScripts/GarageMoodClient.client.lua`: the warm grade (`WARM` :22, `cameraInGarage` :26).
- The garage floor colour: `SiliconCore.server.lua:822` (warm mid concrete at level 1).
**State:** None saved. The dressing is a `Dressing` folder in each plot's `Garage`, one Model per piece, named by its layout id. Floor pieces that are not kit furniture carry `FKItem`, so `FurnitureKit.blocked` keeps a player's decor out of them.
**Drive it:**
- Studio Play: `workspace.SiliconValley.Plots.Plot1.Garage.Dressing` (52 pieces, about 360 parts, 4 lights on 12 Oct).
- Preview any hour of the day: set the workspace attribute `SVClockOverride` (a number) on the CLIENT (`src/StarterPlayer/StarterPlayerScripts/SkyClient.client.lua:445`). The client runs its own day and night, so the server's ClockTime is not what you see.
- Camera framed like image 5: garage-local (0, 9.5, 17.5) looking at (0, 5.5, -14).
**Prove it:**
- `tests/offline/garagelayout.spec.luau`: the real layout has no problems (nothing in the walkway, the desk, either pad or the door; nothing over a window; nothing through a wall; nothing in anything else; no lamp in front of the TV); spawn, camera and laptop line lie in kept floor; the check catches each failure on purpose; at most 6 new lights.
- `SVCheck` placement pass (Studio, server): furniture inside furniture, buried in a wall, through the glass. 12 Oct: 0 new from the garage.
- Live screenshots and side-by-sides: `silicon-startup/ui/2026-10-12-garage/`.
**Gotchas:**
- Oak renders gold. The slats are walnut (128, 88, 56) on a near-black backing, or the back wall reads as orange curtains beside the Kenney bookcases.
- The Palette sweep re-tints every colour onto its anchors. The sage band is the room's one tagged exemption (`SVNoPalette`), or it turns grass green.
- The rocket sign's face is dark NEON on purpose. A shaded ink panel six studs from the desk pendants rendered tan and washed the rocket out.
- The Kenney `lampSquareFloor` is one mesh tinted as its shade, so the whole lamp glows. The garage lamp is built from parts (`B.floorLamp`).
- The sign covers the back window deliberately (`coversWindow`). The wall skin is cut round the windows (`cutsWindow`). Every other wall piece may not cover a window.
- The meeting table is solid (`solid = true` in the layout): the doctor's "sinking surfaces" check failed it on the PR gate run, 12 Oct, as a 4-stud surface you would fall through.
- Not measured: phone frame rate with the dressing, and whether the gold rocket pulls a new player's eye off the blue laptop screen at 0:00 (the opening depends on the laptop).
- Night (the client clock) is dim: four lights do not carry the room. Not addressed yet.
**Last verified:** 2026-10-14 97ff124
