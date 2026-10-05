--[[
	FurnitureKit -- ModuleScript in ServerScriptService.

	The Kenney Furniture Kit (CC0 1.0, kenney.nl) -- the INTERIORS.

	This is the other half of CityKit. The Quaternius MegaKit fixed the street
	and contained zero desks, chairs, monitors or tables, which is exactly what
	the rooms are made of. This kit is 140 models of nothing but that.

	CC0: no attribution required, commercial use fine on an earning place.
	No textures at all -- Kenney ships flat named materials (wood / metal / a Kd
	colour), so there is nothing to import besides the meshes themselves, and
	nothing can arrive looking like a photoreal prop next to a blocky one.

	================= THE SCALE PROBLEM, SOLVED IN CODE =================

	MEASURED IN STUDIO after the real import: every model lands at exactly 10x
	its source units (desk 7.34 studs vs 0.734 source, laptop 2.64 vs 0.264,
	tableRound 6.93 vs 0.693). One clean uniform factor across all 20.

	(An earlier note in this file claimed the ratio varied from 6.87 to 23.81.
	That was measured by reading raw FBX vertex arrays, which ignore each node's
	own transform -- it described the file, not the import. The import is uniform.)

	Even so, nothing here hardcodes 10. Scale is DERIVED per model from its own
	bounding box against the real-world size below, so a re-import at any other
	scale still lands correctly and this never has to be revisited:

	  1 Kenney source unit == 2.00 m   (verified: fridge 0.92u -> 1.84 m,
	                                    desk 0.734u -> 1.47 m, both correct)
	  a 5-stud Roblox character == 1.70 m   ->   1 m == 2.94 studs
	  therefore 1 source unit == 5.88 studs

	SIZE below is the OBJ bounding box x 5.88 -- the true dimensions of real
	furniture, in studs, standing next to a real player.

	================= MODELS, NOT MESHPARTS =================

	These FBX carry more than one material, so Roblox's importer splits each into
	a MODEL of 1-2 MeshParts rather than a single MeshPart. They also arrive
	UNANCHORED, fully COLLIDABLE and with no PrimaryPart. The city kit imported
	as plain MeshParts, so both shapes have to be handled.

	Consequence worth knowing: a Model can only be scaled UNIFORMLY (ScaleTo).
	There is no non-uniform stretch, which is why the garage workbench is two
	desks pushed together rather than one stretched desk.

	================= DEGRADES TO PRIMITIVES =================

	Every entry point is a no-op when its template is missing. Import 3 of the
	20 and you get 3 meshes and 17 primitives -- never a hole, never an error.
	That is why swap() takes the primitive it is replacing: no template, the
	primitive simply stays.
]]

--[[
	Templates live in REPLICATED Storage, deliberately: the build mode's ghost
	preview and catalog thumbnails are built on the CLIENT from the very same
	templates the server spawns from, so the preview can never drift from the
	real thing. ServerStorage is invisible to clients. This module itself also
	lives in ReplicatedStorage for the same reason -- both sides require it.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local FurnitureKit = {}

-- v3.0.3: every seat is tagged, so StaffRig can seat a person on the real chair
local SCREEN_ON = Color3.fromRGB(150, 205, 255)   -- a lit screen when no department colour is given

local function tagSeat(inst, key)
	if key:sub(1, 5) == "chair" or key:sub(1, 5) == "stool" then CollectionService:AddTag(inst, "SVChair") end
end

-- Same folder CityKit uses, so it is one bulk import into one place.
local TEMPLATE_FOLDER = "ImportedMeshes"

-- true size in studs, at player scale. See the header for the derivation.
local SIZE = {
	desk                  = Vector3.new(4.32, 2.26, 2.31),
	chairDesk             = Vector3.new(1.97, 3.57, 1.85),
	laptop                = Vector3.new(1.55, 0.95, 1.41),
	computerScreen        = Vector3.new(2.31, 1.73, 0.61),
	computerKeyboard      = Vector3.new(1.66, 0.16, 0.69),
	cardboardBoxOpen      = Vector3.new(2.19, 1.65, 1.25),
	cardboardBoxClosed    = Vector3.new(1.25, 1.65, 1.25),
	deskCorner            = Vector3.new(5.73, 2.26, 5.73),
	bookcaseClosedDoors   = Vector3.new(2.35, 5.00, 1.47),
	kitchenBar            = Vector3.new(2.53, 2.47, 1.23),
	kitchenFridge         = Vector3.new(2.53, 5.41, 1.72),
	kitchenCoffeeMachine  = Vector3.new(1.11, 1.04, 1.41),
	kitchenMicrowave      = Vector3.new(1.71, 1.06, 1.35),
	tableRound            = Vector3.new(4.07, 2.16, 4.70),
	stoolBar              = Vector3.new(1.56, 2.56, 1.35),
	chairModernCushion    = Vector3.new(1.18, 2.70, 1.18),
	loungeDesignSofa      = Vector3.new(6.59, 2.35, 2.41),
	tableCross            = Vector3.new(5.01, 2.04, 2.63),
	lampSquareFloor       = Vector3.new(0.71, 5.06, 0.71),
	pottedPlant           = Vector3.new(1.25, 3.85, 1.42),
	-- v4.4 KayKit (CC0, ReplicatedStorage.KayKit.Furniture, imported at 1/50: these are
	-- the templates' own sizes, so ScaleTo is 1 unless a piece is shrunk on purpose)
	rug_oval_A              = Vector3.new(6.0, 0.2, 4.0),
	rug_rectangle_A         = Vector3.new(6.0, 0.2, 4.0),
	rug_rectangle_stripes_A = Vector3.new(6.0, 0.2, 4.0),
	cactus_medium_A         = Vector3.new(1.76, 1.65, 1.67),
	cactus_small_A          = Vector3.new(1.0, 1.1, 1.0),
	lamp_standing           = Vector3.new(2.0, 5.04, 2.0),
	lamp_table              = Vector3.new(1.37, 1.4, 1.37),   -- shrunk: 2 studs tall looked huge on a desk
	book_set                = Vector3.new(1.56, 1.0, 0.73),
	pictureframe_standing_A = Vector3.new(0.73, 0.9, 0.55),   -- shrunk for a desk
	cabinet_medium_decorated = Vector3.new(4.08, 3.65, 2.0),
	shelf_B_small_decorated = Vector3.new(2.0, 2.02, 1.14),
	couch_pillows           = Vector3.new(6.0, 2.45, 3.2),
	armchair_pillows        = Vector3.new(3.6, 2.45, 3.2),
}
FurnitureKit.SIZE = SIZE

--[[
	FACING, MEASURED IN GAME: every Kenney model fronts toward +Z at yaw 0.

	That is BACKWARDS from Roblox, whose LookVector is -Z, so "no rotation" here
	means "facing away from where Roblox thinks forward is". Verified by
	rendering a row of chairs, sofas, monitors and a fridge at yaw 0 and looking
	at them from +Z -- every one showed its front.

	Consequence for every call site: a piece against the BACK wall (-Z) needs
	yaw 0 to face into the room, and a chair needs yaw ~180 to face the desk it
	is pulled out from. Both read as wrong until you know the convention.

	This table stays EMPTY: the convention is consistent across all 20, so it is
	handled at the call sites where the intent is visible. It exists for a
	single model that ever breaks the rule.
]]
--[[
	MATERIAL COLOURS, RESTORED BY HAND.

	Roblox's FBX importer DROPPED every material colour: all 33 imported meshes
	arrive at the default grey 163,162,165 with an empty TextureID -- city kit
	included. Untinted, the whole interior renders as one white blob, which is
	exactly how it first looked.

	Kenney ships exact Kd values per material in the .mtl, and the FBX records
	which material each mesh node uses, so the real palette is recoverable
	exactly rather than guessed. Roblox merges a multi-material node into ONE
	MeshPart, so each part takes its DOMINANT surface -- a desk chair reads as
	its cushion, not its frame; a floor lamp as its shade, which is also why
	that one is Neon.

	Keyed "part" when the part is the whole model, "model/part" otherwise.
	MUST stay above settle(), which reads it.
]]
local TINT = {
	["desk"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["desk/drawer"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["chairDesk"] = { Color3.fromRGB(94, 119, 119), Enum.Material.Metal },   -- metalMedium
	["chairDesk/chair"] = { Color3.fromRGB(241, 94, 87), Enum.Material.Fabric },   -- carpet
	["laptop"] = { Color3.fromRGB(78, 99, 99), Enum.Material.Metal },   -- metalDark
	["computerScreen"] = { Color3.fromRGB(78, 99, 99), Enum.Material.Metal },   -- metalDark
	["computerKeyboard"] = { Color3.fromRGB(78, 99, 99), Enum.Material.Metal },   -- metalDark
	["cardboardBoxOpen"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["cardboardBoxClosed"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["deskCorner"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["deskCorner/drawer"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["bookcaseClosedDoors"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["bookcaseClosedDoors/doorLeft"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["bookcaseClosedDoors/doorRight"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["kitchenBar"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["kitchenFridge"] = { Color3.fromRGB(239, 250, 244), Enum.Material.Metal },   -- metalLight
	["kitchenFridge/doorFreezer"] = { Color3.fromRGB(239, 250, 244), Enum.Material.Metal },   -- metalLight
	["kitchenFridge/doorFridge"] = { Color3.fromRGB(239, 250, 244), Enum.Material.Metal },   -- metalLight
	["kitchenCoffeeMachine"] = { Color3.fromRGB(94, 119, 119), Enum.Material.Metal },   -- metalMedium
	["kitchenCoffeeMachine/mug"] = { Color3.fromRGB(248, 255, 255), Enum.Material.Fabric },   -- carpetWhite
	["kitchenMicrowave"] = { Color3.fromRGB(94, 119, 119), Enum.Material.Metal },   -- metalMedium
	["kitchenMicrowave/Group"] = { Color3.fromRGB(248, 255, 255), Enum.Material.Fabric },   -- carpetWhite
	["tableRound"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["stoolBar"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["chairModernCushion"] = { Color3.fromRGB(91, 132, 221), Enum.Material.Fabric },   -- carpetBlue
	["loungeDesignSofa"] = { Color3.fromRGB(91, 132, 221), Enum.Material.Fabric },   -- carpetBlue
	["tableCross"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["lampSquareFloor"] = { Color3.fromRGB(255, 233, 150), Enum.Material.Neon },   -- lamp
	["pottedPlant"] = { Color3.fromRGB(229, 153, 100), Enum.Material.Wood },   -- wood
	["pottedPlant/plant"] = { Color3.fromRGB(46, 209, 147), Enum.Material.Grass },   -- plant
}

--[[
	THE CATALOG -- what the build mode sells, and what each thing DOES.

	Placement has to be mechanical or it is slop with extra steps:
	  desk = 1        -> +1 hire capacity. You build your headcount.
	  morale = n      -> +n% output, summed across placed items, CAPPED at 15%
	                     server-side so spamming plants is not a strategy.
	  surface = true  -> sits on top of a desk/table/counter (monitors, laptops)
	  surfaceTop = h  -> other items may sit on this, at height h
	  tuck = true     -> chairs: allowed to overlap desk-family footprints,
	                     because a chair pushed under a desk is correct, not a
	                     collision
	  needs = roomId  -> locked until that wing is built (his ask: items unlock
	                     with the structure that contains them). COMFORT needs
	                     the design studio, KITCHEN needs the cafeteria.
	                     Server-enforced; the client only greys the card.
]]
FurnitureKit.CATALOG = {
	{ key = "desk",                name = "Desk",           cat = "OFFICE",  price = 60,  desk = 1, surfaceTop = 2.26, vibe = 2 },
	{ key = "deskCorner",          name = "Corner Desk",    cat = "OFFICE",  price = 90,  desk = 1, surfaceTop = 2.26, vibe = 2 },
	{ key = "chairDesk",           name = "Desk Chair",     cat = "OFFICE",  price = 20,  tuck = true, vibe = 1 },
	{ key = "computerScreen",      name = "Monitor",        cat = "OFFICE",  price = 25,  surface = true, vibe = 1 },
	{ key = "computerKeyboard",    name = "Keyboard",       cat = "OFFICE",  price = 10,  surface = true, vibe = 1 },
	{ key = "laptop",              name = "Laptop",         cat = "OFFICE",  price = 40,  surface = true, vibe = 1 },
	{ key = "bookcaseClosedDoors", name = "Bookcase",       cat = "OFFICE",  price = 35, vibe = 2 },
	{ key = "loungeDesignSofa",    name = "Sofa",           cat = "COMFORT", price = 120, morale = 3, needs = "studio", vibe = 4 },
	{ key = "chairModernCushion",  name = "Chair",          cat = "COMFORT", price = 30,  morale = 1, tuck = true, needs = "studio", vibe = 2 },
	{ key = "stoolBar",            name = "Stool",          cat = "COMFORT", price = 15,  tuck = true, needs = "studio", vibe = 1 },
	-- v2.6.0 stations: desk = seats (RoomEconomy owns which room each works in)
	{ key = "tableRound",          name = "Round Table",    cat = "KITCHEN", price = 180, desk = 4, surfaceTop = 2.16, needs = "cafe", vibe = 3 },
	{ key = "tableCross",          name = "Work Table",     cat = "COMFORT", price = 90,  desk = 2, surfaceTop = 2.04, needs = "studio", vibe = 2 },
	{ key = "pottedPlant",         name = "Plant",          cat = "DECOR",   price = 25,  morale = 1, vibe = 2 },
	{ key = "lampSquareFloor",     name = "Floor Lamp",     cat = "DECOR",   price = 30,  morale = 1, vibe = 2 },
	{ key = "cardboardBoxClosed",  name = "Box",            cat = "DECOR",   price = 5, vibe = 1 },
	{ key = "cardboardBoxOpen",    name = "Open Box",       cat = "DECOR",   price = 5, vibe = 1 },
	{ key = "kitchenBar",          name = "Counter",        cat = "KITCHEN", price = 40,  surfaceTop = 2.47, needs = "cafe", vibe = 1 },
	{ key = "kitchenFridge",       name = "Fridge",         cat = "KITCHEN", price = 80,  morale = 2, needs = "cafe", vibe = 2 },
	{ key = "kitchenCoffeeMachine", name = "Coffee Maker",  cat = "KITCHEN", price = 35,  morale = 2, surface = true, needs = "cafe", vibe = 2 },
	{ key = "kitchenMicrowave",    name = "Microwave",      cat = "KITCHEN", price = 30,  morale = 1, surface = true, needs = "cafe", vibe = 1 },
	-- v4.4 KayKit Furniture Bits (CC0). More kinds of decor = more VIBE (each kind
	-- counts 3 copies), so variety is the way to five stars, not spam.
	--   flat = true -> a rug: furniture may stand on it and it may go under furniture
	{ key = "rug_oval_A",              name = "Oval Rug",       cat = "DECOR",   price = 40,  flat = true, vibe = 2 },
	{ key = "rug_rectangle_A",         name = "Rug",            cat = "DECOR",   price = 40,  flat = true, vibe = 2 },
	{ key = "rug_rectangle_stripes_A", name = "Striped Rug",    cat = "DECOR",   price = 45,  flat = true, vibe = 2 },
	{ key = "cactus_medium_A",         name = "Cactus",         cat = "DECOR",   price = 30,  vibe = 2 },
	{ key = "cactus_small_A",          name = "Desk Cactus",    cat = "DECOR",   price = 15,  surface = true, vibe = 1 },
	{ key = "lamp_standing",           name = "Tall Lamp",      cat = "DECOR",   price = 35,  vibe = 2 },
	{ key = "lamp_table",              name = "Desk Lamp",      cat = "DECOR",   price = 20,  surface = true, vibe = 1 },
	{ key = "book_set",                name = "Books",          cat = "DECOR",   price = 15,  surface = true, vibe = 1 },
	{ key = "pictureframe_standing_A", name = "Photo Frame",    cat = "DECOR",   price = 15,  surface = true, vibe = 1 },
	{ key = "shelf_B_small_decorated", name = "Little Shelf",   cat = "DECOR",   price = 50,  vibe = 2 },
	{ key = "cabinet_medium_decorated", name = "Display Cabinet", cat = "DECOR", price = 90,  vibe = 3 },
	{ key = "couch_pillows",           name = "Comfy Couch",    cat = "COMFORT", price = 140, needs = "studio", vibe = 4 },
	{ key = "armchair_pillows",        name = "Armchair",       cat = "COMFORT", price = 60,  needs = "studio", vibe = 2 },
}
FurnitureKit.BY_KEY = {}
for _, it in ipairs(FurnitureKit.CATALOG) do FurnitureKit.BY_KEY[it.key] = it end

local YAW = {}

--[[ v4.0.2 MEASURED: the vertex-coloured pieces (SVFurniture FK_*) front toward
-Z, the opposite of the old Kenney imports this whole file is written for. A
height profile along each piece's depth, compared with the old template of the
same name: 7 of 7 asymmetric pieces (sofa, desk chair, cushion chair, monitor,
keyboard, laptop, coffee machine) came out mirrored, 0 matched. So every sofa
had its backrest toward the TV and every monitor faced the wall. Each clone
carries FKFlip, and stand()/put()/glow() add it, so every call site keeps
meaning "+Z is the front". StaffRig reads chair fronts from the mesh itself and
was never affected. ]]
local VERTEX_FLIP = 180

local templates
--[[ v4.0: the kit with its COLOURS (blender/furniture.py). Each piece is one
vertex-coloured MeshPart in ReplicatedStorage.SVFurniture named FK_<key>,
modelled at its true size and facing +Z like the old pieces. It wins over the
grey v2.0 import (re-tinted one colour per part); 69 pieces are new. ]]
local vertexKit
--[[ v4.4 KayKit (ReplicatedStorage.KayKit.Furniture, Models of one textured
MeshPart). MEASURED: they front -Z (a couch's backrest is at +Z: top heights
1.0 at -Z rising to 2.4 at +Z), the same as the vertex kit, so they carry the
same flip. Third return value = the flip in degrees. ]]
local kayKit
local function templateFor(key)
	vertexKit = vertexKit or ReplicatedStorage:FindFirstChild("SVFurniture")
	local v = vertexKit and vertexKit:FindFirstChild("FK_" .. key)
	if v then return v, true, VERTEX_FLIP end
	kayKit = kayKit or ReplicatedStorage:FindFirstChild("KayKit")
	local kf = kayKit and kayKit:FindFirstChild("Furniture")
	local k = kf and kf:FindFirstChild(key)
	if k then return k, false, 180 end
	if not templates then
		templates = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	end
	if not templates then return nil end
	return templates:FindFirstChild(key)
end

function FurnitureKit.has(key)
	return templateFor(key) ~= nil
end

-- how many of the 20 actually made it in -- printed once at boot so a
-- half-finished import is visible instead of silently looking like the old game
function FurnitureKit.report()
	local have, missing = 0, {}
	for key in pairs(SIZE) do
		if templateFor(key) then have += 1 else table.insert(missing, key) end
	end
	table.sort(missing)
	return have, missing
end

-- ============ SPAWN ============

-- the item's XZ footprint in studs after a yaw of 0/90/180/270 -- the numbers
-- the placement grid and the overlap check both run on
function FurnitureKit.footprint(key, yawDeg)
	local sz = SIZE[key]
	if not sz then return 2, 2 end
	if math.floor(((yawDeg or 0) / 90) + 0.5) % 2 == 1 then return sz.Z, sz.X end
	return sz.X, sz.Z
end

-- put an already-spawned piece so it STANDS at cf (footprint centre on the
-- floor), facing yawDeg. Shared by put() and by the client ghost every frame,
-- so the preview lands exactly where the real thing will.
function FurnitureKit.stand(inst, cf, yawDeg)
	local yaw = math.rad((yawDeg or 0) + (inst:GetAttribute("FKFlip") or 0))
	if inst:IsA("Model") then
		-- orient first, then translate: the bounding box is only meaningful
		-- once the model is already turned
		inst:PivotTo(cf * CFrame.Angles(0, yaw, 0))
		local bcf, bext = inst:GetBoundingBox()
		local want = cf.Position + Vector3.new(0, bext.Y / 2, 0)
		inst:PivotTo(inst:GetPivot() + (want - bcf.Position))
	elseif inst:IsA("BasePart") then
		inst.CFrame = cf * CFrame.Angles(0, yaw, 0) * CFrame.new(0, inst.Size.Y / 2, 0)
	end
end

--[[
	cf is where the piece STANDS: its position is the centre of its footprint on
	the floor, not the centre of the part. Furniture is placed by where its feet
	go, which is how a person thinks about a room, and it means changing a
	model's height never pushes it through the floor.
]]
-- everything the importer leaves wrong: unanchored, collidable, query-visible
local function settle(inst, key, opts)
	for _, d in ipairs(inst:IsA("BasePart") and { inst } or inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true                       -- never negotiable
			--[[
				FURNITURE DOES NOT COLLIDE, BY DEFAULT.
				His verdict on the first walkthrough was "I'm getting stuck in
				the corners". A 28x24 room of collidable chairs and plants is a
				maze of snag points, and a chair leg is exactly the height a
				humanoid catches on rather than steps over. Imports arrive fully
				collidable, so this has to be turned OFF, not left alone.
			]]
			d.CanCollide = opts.canCollide == true
			d.CanQuery = opts.canQuery == true       -- keep it out of the camera popper
			d.CastShadow = opts.castShadow == true   -- default OFF; this is a lot of mesh
			local tint = TINT[key .. "/" .. d.Name] or TINT[d.Name]
			if tint then d.Color, d.Material = tint[1], tint[2] end
			-- an explicit override still wins over the restored palette
			if opts.color then d.Color = opts.color end
			if opts.material then d.Material = opts.material end
		end
	end
end

-- the biggest part, used as a Model's PrimaryPart so callers have something a
-- ProximityPrompt can actually parent to
local function biggest(model)
	local best, bestV = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestV then best, bestV = d, v end
		end
	end
	return best
end

--[[
	cf is where the piece STANDS: its position is the centre of its footprint on
	the floor, not the centre of the object. Furniture is placed by where its
	feet go, which is how a person thinks about a room, and it means changing a
	model's height never pushes it through the floor.

	Returns the Model (PrimaryPart set) or the MeshPart. Use FurnitureKit.body()
	when you need a BasePart to hang a prompt on.
]]
--[[ v3.5 (his report: "some assets are glitched in each other"). Rooms come
furnished (v2.7) and the lobby is dressed, but placement only ever checked a
new item against the player's OTHER placed items -- a lamp could be dropped
inside a room's own table, bookcase or chair. This is the missing check: is
the rect (x, z, w, d) clear of every furniture model the rooms and the HQ
built? Footprints are shrunk a little, so things may stand close; they may
not stand inside each other. ]]
function FurnitureKit.blocked(plot, x, z, w, d)
	local roots = {}
	for _, slot in ipairs(plot.slots or {}) do
		if slot.built and slot.model then table.insert(roots, slot.model) end
	end
	if plot.garage then table.insert(roots, plot.garage) end
	local hw, hd = w * 0.45, d * 0.45
	for _, root in ipairs(roots) do
		for _, m in ipairs(root:GetDescendants()) do
			if m:GetAttribute("FKItem") then
				local cf, sz
				if m:IsA("Model") then cf, sz = m:GetBoundingBox() elseif m:IsA("BasePart") then cf, sz = m.CFrame, m.Size end
				if cf then
					local r, l = cf.RightVector, cf.LookVector
					local ex = (math.abs(r.X) * sz.X + math.abs(l.X) * sz.Z) * 0.42
					local ez = (math.abs(r.Z) * sz.X + math.abs(l.Z) * sz.Z) * 0.42
					if math.abs(cf.X - x) < ex + hw and math.abs(cf.Z - z) < ez + hd then return m:GetAttribute("FKItem") end
				end
			end
		end
	end
	return nil
end

function FurnitureKit.put(key, cf, parent, opts)
	local t, vertex, flip = templateFor(key)
	if not t then return nil end
	opts = opts or {}

	local target = opts.size or SIZE[key]
	local yaw = (YAW[key] or 0) + (opts.yaw or 0)
	local m = t:Clone()
	m.Name = opts.name or key

	if m:IsA("Model") then
		if flip and not vertex then m:SetAttribute("FKFlip", flip) end   -- v4.4 KayKit fronts -Z
		--[[
			A Model scales UNIFORMLY only. Height is the dimension to match:
			human-scale objects are wrong in the eye when they are the wrong
			HEIGHT, and a desk that is 3% narrow than life reads as a desk.

			The factor is derived from this model's own bounding box, so the
			import scale is irrelevant and stays irrelevant.
		]]
		local _, ext = m:GetBoundingBox()
		if ext.Y > 0 then
			-- v4.4: ScaleTo is ABSOLUTE (relative to the import), and the KayKit
			-- templates already sit at 0.02, so scale from the current factor
			m:ScaleTo(m:GetScale() * (target.Y / ext.Y) * (opts.scale or 1))
		end
		settle(m, key, opts)
		m.Parent = parent
		FurnitureKit.stand(m, cf, yaw)
		m.PrimaryPart = m.PrimaryPart or biggest(m)
		tagSeat(m, key)
		m:SetAttribute("FKItem", key)          -- v3.5: placement keeps decor out of room furniture
		if key == "computerScreen" and opts.glow ~= false then FurnitureKit.glow(m, opts.glow or SCREEN_ON) end
		return m
	end

	-- MeshPart: exact size, no bounding-box dance needed
	local size = (vertex and t.Size) or target or t.Size
	if opts.scale then size = size * opts.scale end
	m.Size = size
	if vertex then m:SetAttribute("FKFlip", VERTEX_FLIP) end
	m.CFrame = cf * CFrame.Angles(0, math.rad(yaw + (vertex and VERTEX_FLIP or 0)), 0) * CFrame.new(0, size.Y / 2, 0)
	settle(m, key, opts)
	if vertex then
		-- the colours are in the mesh: white lets them through
		m.Color = opts.color or Color3.new(1, 1, 1)
		m.Material = opts.material or Enum.Material.SmoothPlastic
	end
	m.Parent = parent
	tagSeat(m, key)
	m:SetAttribute("FKItem", key)
	if key == "computerScreen" and opts.glow ~= false then FurnitureKit.glow(m, opts.glow or SCREEN_ON) end
	return m
end

-- the BasePart of whatever put() returned -- a ProximityPrompt cannot parent to
-- a Model, and the garage laptop is the object the entire opening hangs on
function FurnitureKit.body(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	return inst.PrimaryPart or biggest(inst)
end

-- stand a piece on a floor whose TOP surface is at floorY, in baseCF's space
function FurnitureKit.onFloor(key, baseCF, x, z, floorY, parent, opts)
	return FurnitureKit.put(key, baseCF * CFrame.new(x, floorY, z), parent, opts)
end

--[[
	Replace a primitive with the real thing, keeping its place in the world.

	Returns the new MeshPart, or the ORIGINAL primitive when the template is
	missing -- so callers can write

	    laptop = FurnitureKit.swap(laptop, "laptop")

	and every later reference (the ProximityPrompt, the ClickDetector, the popup
	anchor) follows whichever one exists. That is the whole reason this returns
	a part instead of a boolean.
]]
function FurnitureKit.swap(primitive, key, opts)
	if not primitive or not primitive.Parent then return primitive end
	local t = templateFor(key)
	if not t then return primitive end
	opts = opts or {}

	local parent = primitive.Parent
	local cf = primitive.CFrame
	-- sit the replacement on the same floor the primitive sat on, rather than on
	-- the primitive's centre: the two are different heights, and matching
	-- centres is how furniture ends up buried or floating
	local floorTop = opts.floorTop or (primitive.Position.Y - primitive.Size.Y / 2)
	local _, yaw = cf:ToEulerAnglesYXZ()
	local flat = CFrame.new(cf.Position.X, floorTop, cf.Position.Z) * CFrame.Angles(0, yaw, 0)

	local m = FurnitureKit.put(key, flat, parent, opts)
	if not m then return primitive end
	m.Name = opts.name or primitive.Name
	primitive:Destroy()
	-- a BasePart, NOT the Model: callers hang ProximityPrompts, ClickDetectors
	-- and popup anchors off whatever comes back, and none of those can parent
	-- to a Model. The Model stays in the world; this is a handle into it.
	return FurnitureKit.body(m)
end

--[[
	A small emissive plane on the screen's face, so a monitor can flash the
	accent colour the way the primitive one did.

	HIS BUG REPORT, CONFIRMED: "the screens are not attached to the monitors."
	The old version read the MeshPart's own CFrame and offset along its local Z
	-- but an imported part's local axes need not match its visual orientation,
	so the plane floated beside the mesh. The ORIENTED BOUNDING BOX is the truth
	for imported geometry: the plane now sits on the +Z face of the bbox, which
	is the front on every Kenney model.
]]
function FurnitureKit.glow(screen, colour)
	if not screen then return nil end
	--[[
		v3.0.3 MEASURED, not guessed: the old plane sat 0.3 studs IN FRONT of the
		screen (bounding-box face, and the box includes the stand's foot). Now a
		ray is fired at the mesh from its front; the plane goes on the surface it
		hits, facing along that surface's normal, 0.02 studs proud of it.
	]]
	local parts = {}
	for _, d in ipairs(screen:IsA("BasePart") and { screen } or screen:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Glow" then table.insert(parts, d) end
	end
	if #parts == 0 then return nil end
	local body = FurnitureKit.body(screen) or parts[1]
	local cf, size
	if screen:IsA("Model") then cf, size = screen:GetBoundingBox() else cf, size = body.CFrame, body.Size end
	local was = {}
	for i, d in ipairs(parts) do was[i] = d.CanQuery; d.CanQuery = true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local centre = cf.Position + Vector3.new(0, size.Y * 0.1, 0)
	local hit
	-- Kenney fronts face -LookVector, so the ray starts out in FRONT and travels
	-- along +LookVector into the screen (first draft fired from behind and put
	-- 14 of 19 glows on the backs of the monitors -- measured, then fixed)
	-- (a vertex piece fronts the other way in its own axes: see VERTEX_FLIP)
	local sign = (screen:GetAttribute("FKFlip") or body:GetAttribute("FKFlip")) and -1 or 1
	local dir = cf.LookVector * sign
	local h = workspace:Raycast(centre - dir * 4, dir * 8, params)
	if h and h.Normal:Dot(-dir) > 0.9 then hit = h end
	for i, d in ipairs(parts) do d.CanQuery = was[i] end
	local pos, n
	if hit then
		pos, n = hit.Position, hit.Normal
	else
		-- not in the workspace yet (rays see nothing): the Kenney screen panel is the
		-- mesh's centre plane (measured: face 0.02 in front of centre), front = -LookVector
		n = -body.CFrame.LookVector * sign
		pos = body.Position + n * 0.02 + Vector3.new(0, size.Y * 0.1, 0)
	end
	local g = Instance.new("Part")
	g.Name = "Glow"
	g.Size = Vector3.new(size.X * 0.8, size.Y * 0.52, 0.04)
	g.CFrame = CFrame.lookAt(pos + n * 0.02, pos + n * 1)
	g.Anchored = true
	g.CanCollide = false
	g.CanQuery = false
	g.CastShadow = false
	g.Color = colour
	g.Material = Enum.Material.Neon
	g.Parent = screen
	return g
end

-- ============ A WORKSTATION ============

--[[
	Desk + screen + keyboard + chair, as one call.

	Six of these across the game, so the arrangement is defined once: monitor at
	the back edge facing the seat, keyboard in front of it, chair pulled out and
	turned. A row of identically square workstations reads as a spreadsheet --
	the chair angle is what makes it read as a room people actually use.
]]
function FurnitureKit.workstation(baseCF, x, z, floorY, parent, opts)
	opts = opts or {}
	local yaw = opts.yaw or 0
	local at = baseCF * CFrame.new(x, floorY, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local made = {}

	made.desk = FurnitureKit.put("desk", at, parent, { name = "Desk", canCollide = true })

	local deskTop = baseCF * CFrame.new(x, floorY + SIZE.desk.Y, z)
		* CFrame.Angles(0, math.rad(yaw), 0)

	made.screen = FurnitureKit.put("computerScreen", deskTop * CFrame.new(0, 0, -0.55),
		parent, { name = "Monitor", glow = opts.accent })
	made.glow = made.screen and made.screen:FindFirstChild("Glow")
	made.keyboard = FurnitureKit.put("computerKeyboard", deskTop * CFrame.new(0, 0, 0.45),
		parent, { name = "Keyboard" })
	-- pulled out and turned: a chair square to a desk looks unoccupied
	made.chair = FurnitureKit.put("chairDesk", at * CFrame.new(0.3, 0, 2.4),
		parent, { name = "Chair", yaw = 165 })
	return made
end

-- ============ ROOM DRESSING ============

--[[
	Called after the primitive contents are built, so this is purely additive:
	whatever is missing stays as it was. Each room gets furniture that states its
	mechanical job, because the fascia colour is the only other thing telling you
	what a room does.
]]
function FurnitureKit.dressRoom(model, roomId, cf, accent)
	if not model then return 0 end
	local before = #model:GetChildren()
	local F = 1.0                          -- room floors are 1 thick, top at y = 1

	if roomId == "office" then
		-- the four primitive desks become four real workstations
		for k = 1, 4 do
			local old = model:FindFirstChild("Desk" .. k)
			local mon = model:FindFirstChild("Mon" .. k)
			if old and FurnitureKit.has("desk") then
				local p = cf:PointToObjectSpace(old.Position)
				old:Destroy()
				if mon then mon:Destroy() end
				FurnitureKit.workstation(cf, p.X, p.Z, F, model,
					{ yaw = (p.Z < 0) and 0 or 180, accent = accent })
			end
		end
		-- v2.0: rooms are player-furnished shells, so the primitive desks above no
		-- longer exist; two starter workstations on the back wall make an empty
		-- office read as an office. The player adds the rest.
		if FurnitureKit.has("desk") then
			FurnitureKit.workstation(cf, -4.5, -8.6, F, model, { yaw = 0, accent = accent })
			FurnitureKit.workstation(cf, 4.5, -8.6, F, model, { yaw = 0, accent = accent })
		end
		FurnitureKit.onFloor("bookcaseClosedDoors", cf, -11.5, -10.4, F, model)
		FurnitureKit.onFloor("bookcaseClosedDoors", cf, -8.6, -10.4, F, model)
		FurnitureKit.onFloor("pottedPlant", cf, 11.5, -10, F, model)
		FurnitureKit.onFloor("pottedPlant", cf, 11.5, 9, F, model)

	elseif roomId == "servers" then
		-- the racks stay primitive on purpose: a server rack IS a metal box with
		-- lights, and this kit has no rack. What the room was missing was a
		-- reason for a person to be in it, so it gets a monitoring station.
		FurnitureKit.workstation(cf, 0, 7, F, model, { yaw = 180, accent = accent })
		FurnitureKit.onFloor("kitchenCoffeeMachine", cf, 11.4, 6.6, F, model)
		FurnitureKit.onFloor("cardboardBoxClosed", cf, -11.6, 7.4, F, model)
		FurnitureKit.onFloor("cardboardBoxOpen", cf, -11.6, 9.2, F, model, { yaw = 24 })

	elseif roomId == "studio" then
		FurnitureKit.onFloor("loungeDesignSofa", cf, 0, 7.2, F, model,
			{ yaw = 180, canCollide = true })
		FurnitureKit.onFloor("tableCross", cf, 0, 2.4, F, model)
		FurnitureKit.onFloor("chairModernCushion", cf, -3.7, 2.8, F, model, { yaw = 90 })   -- v3.0.3: at the table, not 2.9 studs off it
		FurnitureKit.onFloor("chairModernCushion", cf, 3.7, 2.8, F, model, { yaw = -90 })
		FurnitureKit.onFloor("lampSquareFloor", cf, -10.8, 6.4, F, model)
		FurnitureKit.onFloor("lampSquareFloor", cf, 10.8, 6.4, F, model)
		FurnitureKit.onFloor("pottedPlant", cf, -11.6, -6, F, model)
		FurnitureKit.onFloor("pottedPlant", cf, 11.6, -6, F, model)

	elseif roomId == "cafe" then
		-- the counter becomes a real run of bar units, and gains the two props
		-- that say "people take a break here"
		local counter = model:FindFirstChild("Counter")
		if counter and FurnitureKit.has("kitchenBar") then
			counter:Destroy()
			for k = -3, 3 do
				FurnitureKit.onFloor("kitchenBar", cf, k * 2.5, -9, F, model,
					{ name = "Bar", canCollide = true })
			end
			local barTop = F + SIZE.kitchenBar.Y
			FurnitureKit.put("kitchenCoffeeMachine", cf * CFrame.new(-6.2, barTop, -9), model)
			FurnitureKit.put("kitchenMicrowave", cf * CFrame.new(6.2, barTop, -9), model)
		end
		FurnitureKit.onFloor("kitchenFridge", cf, -11.6, -9.4, F, model, { canCollide = true })
		for k = 1, 3 do
			FurnitureKit.onFloor("stoolBar", cf, -5 + (k - 1) * 5, -6.4, F, model, { yaw = 180 })
		end
		-- the three primitive tables become round ones with chairs
		for k = 1, 3 do
			local old = model:FindFirstChild("Table" .. k)
			if old and FurnitureKit.has("tableRound") then
				local p = cf:PointToObjectSpace(old.Position)
				old:Destroy()
				FurnitureKit.onFloor("tableRound", cf, p.X, p.Z + 3, F, model,
					{ name = "Table" .. k, canCollide = true })
				FurnitureKit.onFloor("chairModernCushion", cf, p.X - 3.4, p.Z + 3, F, model,
					{ yaw = 90 })
				FurnitureKit.onFloor("chairModernCushion", cf, p.X + 3.4, p.Z + 3, F, model,
					{ yaw = -90 })
			end
		end
	end

	return #model:GetChildren() - before
end

-- ============ THE GARAGE ============

--[[
	The opening. Everything in here is seen before the player has done anything,
	so it is the most-looked-at geometry in the game.

	The Neon Screen is DELIBERATELY LEFT PRIMITIVE. It is the big glowing target
	the eye goes to at 0:00, writeCode() flashes its Color, and the entire
	onboarding hangs off the player noticing it. A grey mesh monitor is a worse
	object for that job. The mesh screen goes beside it as a second display.
]]
function FurnitureKit.dressGarage(garage, g, parts)
	if not garage then return 0 end
	local before = #garage:GetChildren()
	local F = 1.0                          -- garage floor is 1 thick, top at y = 1

	if not FurnitureKit.has("desk") then return 0 end

	--[[
		THE WORKBENCH IS TWO DESKS, NOT ONE STRETCHED ONE.

		The primitive was 7 studs wide. A Model can only be scaled uniformly, so
		widening one desk to 7 also makes it 1.19 m TALL -- chest height on the
		player, and the desk surface would swallow the glowing Screen at y 4.35.
		Two desks pushed together give the same 8.6-stud bench at a real desk's
		height, and "two folding desks shoved together" is what a garage startup
		actually looks like.
	]]
	local oldDesk = parts.desk
	local firstDesk
	for _, dx in ipairs({ -2.16, 2.16 }) do
		local d = FurnitureKit.put("desk", g(dx, F, -9), garage,
			{ name = "Desk", canCollide = true, canQuery = true })
		-- stamped like a placed surface: the build-mode aim ray and overlap
		-- preview read these, so a monitor aimed at the bench snaps to its top
		-- instead of falling through into it (his bug)
		d:SetAttribute("key", "desk")
		d:SetAttribute("px", dx); d:SetAttribute("pz", -9)
		d:SetAttribute("pw", SIZE.desk.X); d:SetAttribute("pd", SIZE.desk.Z)
		d:SetAttribute("py", F)
		firstDesk = firstDesk or d
	end
	if oldDesk and oldDesk.Parent then oldDesk:Destroy() end
	parts.desk = FurnitureKit.body(firstDesk)
	for _, n in ipairs({ "DeskLegL", "DeskLegR" }) do
		local pgone = garage:FindFirstChild(n)
		if pgone then pgone:Destroy() end        -- the legs are inside the mesh now
	end

	local deskTop = F + SIZE.desk.Y                      -- 3.26, was 3.40

	parts.laptop = FurnitureKit.swap(parts.laptop, "laptop",
		{ floorTop = deskTop, scale = 1.15 })

	--[[ THE LAPTOP HAD NO SCREEN, reported 5 Oct with a screenshot.

		Measured: the primitive Screen sat at z -9.8 and the swapped-in laptop
		MESH is 1.6 deep centred at z -9.0, so it spans -9.8 to -8.2. The lit
		panel was therefore buried INSIDE the mesh at its rear edge -- sized 2.6
		wide for a primitive laptop that no longer existed, against a mesh 1.8
		wide. From the room you saw the laptop's back and no screen at all.

		The fix was already in this file. glow() fires a ray at a mesh from its
		front and lays the lit plane flush on whatever surface it hits; it was
		written for the monitors in v3.0.3 after 14 of 19 glows landed on their
		backs. It just never ran for the laptop. Now it does, and the lit plane
		is the object SiliconCore keeps as plot.screen, so writeCode() still
		flashes the thing the player is actually looking at. ]]
	local scr = garage:FindFirstChild("Screen")
	local lit = FurnitureKit.glow(parts.laptop, SCREEN_ON)
	if lit then
		lit.Name = "Screen"
		parts.screen = lit
		if scr then scr:Destroy() end
	elseif scr then
		scr.CFrame = g(0, deskTop + scr.Size.Y / 2 + 0.02, -9.8)
			* CFrame.Angles(math.rad(-15), 0, 0)
	end

	-- a second, ordinary monitor beside the glowing one, angled toward the seat
	FurnitureKit.put("computerScreen",
		g(2.9, deskTop, -9.5) * CFrame.Angles(0, math.rad(-22), 0), garage,
		{ name = "Monitor2" })
	FurnitureKit.put("computerKeyboard", g(0, deskTop, -7.9), garage,
		{ name = "Keyboard" })

	-- the chair. Both primitive halves go; the mesh has its own back.
	--[[
		THE CHAIR IS AIMED, NOT ANGLED.

		It sits off to one side (the primitive was moved there so it stopped
		blocking the sightline from spawn to the laptop, which is the whole
		opening). Any FIXED yaw is therefore wrong: measured, a hardcoded 152
		pointed it at the wall BEHIND the workbench, dot -0.27 against the
		direction to the desk. Aim it at the bench and the number follows the
		layout instead of having to be re-guessed whenever anything moves.
	]]
	local seat = garage:FindFirstChild("Chair")
	local back = garage:FindFirstChild("ChairBack")
	if seat and FurnitureKit.has("chairDesk") then
		local pos = seat.Position
		if back then back:Destroy() end
		seat:Destroy()
		local bench = (g(0, 0, -9)).Position
		local dir = (Vector3.new(bench.X, 0, bench.Z) - Vector3.new(pos.X, 0, pos.Z)).Unit
		-- Kenney models front toward +Z, so the yaw that points +Z along dir is
		-- atan2(dir.X, dir.Z). +24 turns it out, as though just vacated.
		local yaw = math.deg(math.atan2(dir.X, dir.Z)) + 24
		FurnitureKit.put("chairDesk",
			CFrame.new(pos.X, g(0, F, 0).Position.Y, pos.Z) * CFrame.Angles(0, math.rad(yaw), 0),
			garage, { name = "Chair" })
	end

	-- clutter. A company that started three days ago has boxes it has not
	-- unpacked, and that is the cheapest way to say "this just began".
	local boxes = garage:FindFirstChild("Boxes")
	if boxes and FurnitureKit.has("cardboardBoxClosed") then
		boxes:Destroy()
		--[[ MEASURED: the open box's right edge was 13.8 and the closed box's
			left edge 13.7, so they interpenetrated, and both sat a stride out
			from the corner looking dropped rather than stacked. Pushed into the
			corner (walls are x 18, z -15) with a clear gap between them. ]]
		FurnitureKit.put("cardboardBoxClosed", g(15.2, F, -13.4), garage, { scale = 1.3 })
		FurnitureKit.put("cardboardBoxOpen", g(11.9, F, -13.6), garage,
			{ scale = 1.3, yaw = 28 })
		FurnitureKit.put("cardboardBoxClosed",
			g(15.2, F + SIZE.cardboardBoxClosed.Y * 1.3, -13.4)
				* CFrame.Angles(0, math.rad(14), 0), garage, { scale = 1.3 })
	end

	FurnitureKit.put("pottedPlant", g(-15.6, F, 2.4), garage)
	FurnitureKit.put("lampSquareFloor", g(15.6, F, -4.4), garage)

	return #garage:GetChildren() - before
end

--[[ v2.6.3 PRICE BY INCOME. Prices used to scale only with HQ level, so a
company earning $150/s at HQ 1 paid $266 for a round table. Every item now
costs AT LEAST this many seconds of your income (the same rule wing upgrades
already use). Stations cost the most, morale items less, pure decoration
almost nothing -- decorating should never feel taxed. ]]
function FurnitureKit.floorSeconds(item)
	if not item then return 0 end
	if item.desk then return ({ [1] = 30, [2] = 45, [4] = 60 })[item.desk] or 30 end
	if item.morale then return 15 end
	return 5
end

-- one formula for server and client, so the shown price is the charged price
function FurnitureKit.priceFor(item, priceMult, rate)
	return math.max(math.floor(item.price * (priceMult or 1)),
		math.floor((rate or 0) * FurnitureKit.floorSeconds(item)))
end

--[[ v3.2.1 OFFICE VIBE. Decor had one job: +1% money per plant, capped at
+15%, and most items (desks, boxes, monitors) did nothing at all. Players
could not tell why to decorate. The reference games answer this the same
way: Restaurant Tycoon 2 and Retail Tycoon 2 turn decor into a star RATING,
and the rating brings better customers. Here the rating is VIBE, and a
better office attracts better talent: every star makes rare hires more
likely. Each item counts up to VIBE_PER_KEY copies, so variety beats spam. ]]
FurnitureKit.VIBE_PER_KEY = 3
FurnitureKit.VIBE_STARS = { 5, 15, 30, 50, 75 }   -- points for 1..5 stars
FurnitureKit.VIBE_LUCK_STEP = 0.2                 -- each star: rare hires x(1 + 0.2)

-- keys: a list of item keys (placed items). Returns the vibe points.
function FurnitureKit.vibePoints(keys)
	local n, pts = {}, 0
	for _, key in ipairs(keys or {}) do
		local it = FurnitureKit.BY_KEY[key]
		if it and it.vibe then
			n[key] = (n[key] or 0) + 1
			if n[key] <= FurnitureKit.VIBE_PER_KEY then pts += it.vibe end
		end
	end
	return pts
end

-- points -> stars (0..5), rare-hire luck, points needed for the next star (nil at 5)
function FurnitureKit.vibe(points)
	local stars = 0
	for i, need in ipairs(FurnitureKit.VIBE_STARS) do
		if (points or 0) >= need then stars = i end
	end
	return stars, 1 + FurnitureKit.VIBE_LUCK_STEP * stars, FurnitureKit.VIBE_STARS[stars + 1]
end

return FurnitureKit
