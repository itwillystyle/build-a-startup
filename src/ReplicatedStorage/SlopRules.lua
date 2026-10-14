--[[ SlopRules (14 Oct 2026): the composition checks the game doctor runs on every screen it
	probes. The PR #55 TEAM screen passed every size check and was still sloppy: three green
	buttons at once, facts said twice, a row of chips cut off. These are DESIGN.md's rules made
	measurable. Pure (DoctorProbes gathers the inputs on the player's screen); tested in
	tests/offline/sloprules.spec. Spec: docs/superpowers/specs/2026-10-14-team-screen-redesign-design.md §3. ]]
local R = {}

R.LOUD = { { 60, 203, 108 }, { 59, 139, 255 }, { 255, 138, 61 }, { 240, 78, 78 }, { 165, 92, 255 }, { 255, 200, 61 } }

function R.isLoud(rgb)
	for _, c in R.LOUD do
		if math.abs(rgb[1] - c[1]) <= 3 and math.abs(rgb[2] - c[2]) <= 3 and math.abs(rgb[3] - c[3]) <= 3 then return true end
	end
	return false
end

-- more than one loud button in one open menu: nothing leads
function R.loudButtons(buttons)
	local by, order = {}, {}
	for _, b in buttons do
		if R.isLoud(b.rgb) then
			if not by[b.menu] then by[b.menu] = {}; table.insert(order, b.menu) end
			table.insert(by[b.menu], b.path)
		end
	end
	local out = {}
	for _, m in order do
		if #by[m] > 1 then table.insert(out, { menu = m, count = #by[m], paths = by[m] }) end
	end
	return out
end

-- the same fact twice on one screen
function R.saidTwice(labels)
	local seen, out, reported = {}, {}, {}
	for _, l in labels do
		local text = (tostring(l.text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
		if #text >= 4 and text:find("%a") then   -- a number alone ("0/13") is not a fact
			local key = tostring(l.gui) .. "\0" .. text
			if seen[key] and not reported[key] then
				reported[key] = true
				table.insert(out, { gui = l.gui, text = text, paths = { seen[key], l.path } })
			elseif not seen[key] then
				seen[key] = l.path
			end
		end
	end
	return out
end

-- text that does not fit, or a button hanging outside the frame that clips it
function R.cutOff(items)
	local out = {}
	for _, it in items do
		if it.fits == false then
			table.insert(out, { path = it.path, why = "text does not fit" })
		elseif it.clip then
			local r, c = it.rect, it.clip
			if r[1] < c[1] - 1 or r[2] < c[2] - 1 or r[1] + r[3] > c[1] + c[3] + 1 or r[2] + r[4] > c[2] + c[4] + 1 then
				table.insert(out, { path = it.path, why = "outside its frame" })
			end
		end
	end
	return out
end

-- the "fits" a probe reports for one GUI object: TextFits for a text object with text, else nil.
-- (final review, 14 Oct: the probe wrote `isText and text ~= "" and o.TextFits or nil`, which is
-- nil when TextFits is false, so "text does not fit" could never fire)
function R.fitsOf(isText, text, textFits)
	if not isText or text == nil or text == "" then return nil end
	return textFits == true
end

return R
