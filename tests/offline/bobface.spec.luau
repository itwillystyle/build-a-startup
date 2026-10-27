-- bobface.spec.luau: every FaceControls name BobFace sets is a real property (26 Oct 2026).
-- BobFace pcalls each set, so a wrong name fails silently: the shock eyes never opened on
-- dynamic heads ("LeftUpperLidRaiser" is not a property). REAL = read off a FaceControls in
-- Studio on 26 Oct with pcall(function() return fc[name] end).
local F = require("../../src/ReplicatedStorage/BobFace")
local T = {}
local function test(name, fn) table.insert(T, { name = name, fn = fn }) end

local REAL = {}
for _, n in { "JawDrop", "LeftEyeUpperLidRaiser", "RightEyeUpperLidRaiser", "LeftOuterBrowRaiser",
	"RightOuterBrowRaiser", "LeftLipCornerPuller", "RightLipCornerPuller", "LeftEyeClosed", "RightEyeClosed",
	"LeftLipCornerDown", "RightLipCornerDown", "LeftInnerBrowRaiser", "RightInnerBrowRaiser",
	"LeftBrowLowerer", "RightBrowLowerer", "LipPresser", "LeftCheekRaiser", "RightCheekRaiser" } do
	REAL[n] = true
end

test("every face control BobFace sets exists on FaceControls", function()
	for expr, t in F.CONTROLS do
		for name in t do
			assert(REAL[name], ("%s sets %s, which FaceControls does not have"):format(expr, name))
		end
	end
end)

return T
