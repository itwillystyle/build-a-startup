--[[ StyleBaseline: the counts SVStyle ratchets against.

	Re-measured 6 Oct 2026 after S2-S6, Dome path, wafer level 43, world
	settled, enforce idempotent (a second pass changes 0).

	Numbers may go DOWN in a commit, never UP. SVStyle.run() fails on any rise.
	Regenerate with SVStyle.baselineSrc() only when lowering one on purpose --
	never to make a regression go away.

	Where this started on the morning of 6 Oct, before any of it:
	  offPalette 998 -> 2      flatNeutral 724 -> 0
	  untintedPack 418 -> 0    neonLoose 94 -> 7
	  colours 191 -> 153       sharp 2951 -> 2951 (untouched; see below)

	`sharp` is the one that did not move. Rounding the architecture means
	bevelling the HQ mesh kit in Blender and re-importing, which is the
	remainder of S5 and is recorded as not done. The motif ships as the lawn
	aprons, which change the silhouette without touching the collision.

	`parts` and `untintedOwn` are context, not faults: parts says whether the
	world had finished building when the scan ran, and untintedOwn counts our
	own vertex-coloured meshes, which are correct as they are.
]]
return {
	colours = 153,
	flatNeutral = 0,
	neonLoose = 7,
	offPalette = 2,
	parts = 10096,
	sharp = 2951,
	untintedOwn = 5570,
	untintedPack = 0,
}
