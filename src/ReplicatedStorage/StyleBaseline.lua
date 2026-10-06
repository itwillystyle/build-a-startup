--[[ StyleBaseline: the counts SVStyle ratchets against.

	Measured 6 Oct 2026, Dome path, wafer level 43, world settled, stable
	across two runs 8 s apart.

	Numbers may go DOWN in a commit, never UP. SVStyle.run() fails on any rise.
	Regenerate with SVStyle.baselineSrc() only when lowering one on purpose --
	never to make a regression go away.

	`parts` and `untintedOwn` are context, not faults: parts says whether the
	world had finished building when the scan ran, and untintedOwn counts our
	own vertex-coloured meshes, which are correct as they are.
]]
return {
	colours = 191,
	flatNeutral = 724,
	neonLoose = 94,
	offPalette = 998,
	parts = 10036,
	sharp = 2951,
	untintedOwn = 5139,
	untintedPack = 418,
}
