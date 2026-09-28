local DURATION = DURATION or 14
local pg = game.Players.LocalPlayer.PlayerGui
local function vis(path)
	local cur = pg
	for _, n in ipairs(string.split(path, ".")) do cur = cur and cur:FindFirstChild(n) end
	return cur and cur.Visible
end
local function onScreen(gui)
	return gui and gui:IsA("GuiObject") and gui.Visible and gui.AbsolutePosition.Y < workspace.CurrentCamera.ViewportSize.Y - 10 and gui.AbsolutePosition.Y > -20
end
_G.NotifyLive = { max = { top = 0, centre = 0, bottom = 0 }, seen = {}, samples = 0 }
local R = _G.NotifyLive
task.spawn(function()
	local t0 = os.clock()
	while os.clock() - t0 < DURATION do
		local top, centre, bottom = 0, 0, 0
		local function mark(name, lane)
			R.seen[name] = true
			if lane == "top" then top += 1 elseif lane == "centre" then centre += 1 else bottom += 1 end
		end
		if vis("PhoneNotify.Banner") and onScreen(pg.PhoneNotify.Banner) then mark("phone", "top") end
		if vis("PhoneNotify.Incoming") then mark("ring", "top") end
		local tr = pg:FindFirstChild("TalentReveal")
		for _, c in ipairs(tr and tr:GetChildren() or {}) do if c:IsA("TextButton") and onScreen(c) then mark("reveal", "top") end end
		if vis("TalentRow.Danger") then mark("headhunter", "top") end
		if vis("TalentRow.Lost") then mark("lost", "top") end
		local fx = pg:FindFirstChild("Celebrate")
		for _, c in ipairs(fx and fx:GetChildren() or {}) do
			if c:IsA("Frame") and c.Size.Y.Offset == 132 and onScreen(c) then mark("hq", "top") end
			if c:IsA("Frame") and c.Size.Y.Offset == 200 then mark("welcome", "centre") end
		end
		local ifx = pg:FindFirstChild("ItemFx")
		for _, c in ipairs(ifx and ifx:GetChildren() or {}) do if c:IsA("Frame") and c.Size.Y.Offset == 96 then mark("item", "centre") end end
		if pg:FindFirstChild("Daily") and pg.Daily.Enabled then mark("daily", "centre") end
		if pg:FindFirstChild("CompanyName") and pg.CompanyName.Enabled then mark("name", "centre") end
		local tp = pg:FindFirstChild("NotifyToast") and pg.NotifyToast:FindFirstChild("Toast")
		if tp and tp.Position.Y.Offset < 0 then mark("toast", "bottom") end
		R.max.top = math.max(R.max.top, top); R.max.centre = math.max(R.max.centre, centre); R.max.bottom = math.max(R.max.bottom, bottom)
		R.samples += 1
		task.wait(0.25)
	end
	R.done = true
end)
return "watching"
