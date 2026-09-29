--[[
	Phone -- ModuleScript in ServerScriptService (v3.2). Two apps.

	MESSAGES: investors text you. Each one has a hidden thesis (AI, growth,
	team, shipping, design or money) that their questions give away. You
	answer with one of three replies built from YOUR company's real numbers
	(or type your own), three times; they react, then make an offer: TAKE it,
	PUSH for more (it can go wrong), or PASS. So the chat is a puzzle about
	your own campus: a design investor loves a level 3 studio, a team investor
	loves your STAR hire. What you built is what you can say.

	  - The game decides the score; the model only writes the words. Replies
	    come from Roblox's TextGenerator (free, moderated, in-engine) with a
	    scripted fallback, so a slow or refused generation never stalls a chat.
	  - Roblox's 2026 AI rules: three messages per investor, one investor at a
	    time, minutes apart, nothing saved between sessions, and every
	    investor is labelled AI on the client.

	CALLS: voice calls to other founders in the server. The server only rings
	and connects; the audio is wired on each client (PhoneClient) from the
	other player's AudioDeviceInput to a local AudioDeviceOutput. Both players
	need voice chat on their account (13+, verified), both must accept, and
	Roblox's direct-chat rules must allow the pair (CanUsersDirectChatAsync).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local Phone = {}
local api
local event

-- ============ THE INVESTORS ============

local PERSONAS = {
	{ id = 1, name = "Priya Raman",  first = "Priya",  firm = "Northwind Ventures",   thesis = "ai",      color = Color3.fromRGB(96, 120, 255) },
	{ id = 2, name = "Marcus Hale",  first = "Marcus", firm = "Summit Peak Capital",  thesis = "growth",  color = Color3.fromRGB(255, 140, 60) },
	{ id = 3, name = "Lena Okafor",  first = "Lena",   firm = "Brightwater Partners", thesis = "team",    color = Color3.fromRGB(60, 184, 156) },
	{ id = 4, name = "Diego Santos", first = "Diego",  firm = "Launchpad Fund",       thesis = "product", color = Color3.fromRGB(232, 80, 80) },
	{ id = 5, name = "Hana Mori",    first = "Hana",   firm = "Paper Plane VC",       thesis = "design",  color = Color3.fromRGB(236, 120, 180) },
	{ id = 6, name = "Victor Lang",  first = "Victor", firm = "Ironbridge Capital",   thesis = "profit",  color = Color3.fromRGB(110, 124, 150) },
	{ id = 7, name = "Sofia Brandt", first = "Sofia",  firm = "Tidewell Ventures",    thesis = "team",    color = Color3.fromRGB(170, 130, 255) },
	{ id = 8, name = "Jonah Pierce", first = "Jonah",  firm = "Redwood Row",          thesis = "ai",      color = Color3.fromRGB(80, 160, 90) },
}

local THESES = { "ai", "growth", "team", "product", "design", "profit" }
local THESIS = {
	ai = { desc = "real AI technology: research, researchers and running your own servers",
		keywords = { "ai", "a%.i", "model", "models", "research", "researcher", "researchers", "server", "servers", "compute",
			"data", "gpu", "machine learning", "neural", "algorithm", "tech", "robot", "robots" },
		probes = {
			"Everyone says they're an AI company now. Are you, really?",
			"What's under the hood? Tell me about your tech.",
			"Last one: why couldn't a big company just copy you?",
		} },
	growth = { desc = "fast growth and a big, growing team",
		keywords = { "grow", "growing", "growth", "scale", "users", "fast", "big", "bigger", "hiring", "million", "expand", "huge" },
		probes = {
			"I only care about one thing. How fast are you growing?",
			"How big is the team getting?",
			"Last one: where will you be a year from now?",
		} },
	team = { desc = "great people and rare, talented hires",
		keywords = { "team", "people", "hire", "hired", "hiring", "talent", "talented", "star", "genius", "unicorn",
			"engineer", "engineers", "designer", "recruiter", "culture" },
		probes = {
			"I bet on people, not ideas. Who's on your team?",
			"Who's the best person you've hired so far?",
			"Last question: why would great people want to work for you?",
		} },
	product = { desc = "shipping lots of apps, often",
		keywords = { "ship", "shipped", "shipping", "launch", "launched", "launches", "app", "apps", "product", "release", "released" },
		probes = {
			"Ideas are cheap. What have you actually shipped?",
			"How often do you ship something new?",
			"Last one: do people keep using what you ship?",
		} },
	design = { desc = "beautiful design, great designers and a design studio",
		keywords = { "design", "designer", "designers", "studio", "beautiful", "pretty", "ux", "ui", "style", "clean", "polish", "art" },
		probes = {
			"I only back things people love to use. Who does your design?",
			"What makes your apps feel different?",
			"Last one: show me you care about the details.",
		} },
	profit = { desc = "making real money, right now",
		keywords = { "money", "revenue", "profit", "profitable", "cash", "earn", "earning", "earnings", "income", "paying", "sales" },
		probes = {
			"Straight to it: are you making money yet?",
			"Where does your money come from?",
			"Last one: what would you do with more cash?",
		} },
}

local OPENERS = {
	"Hi! %s here, from %s. I've been watching %s.",
	"Hey, it's %s at %s. Got a minute to talk about %s?",
	"%s from %s. I keep hearing about %s.",
}
local REACT = {
	strong = { "Now THAT is what I like to hear.", "Okay. You have my attention.", "That's exactly what I look for.", "Love that. Seriously." },
	mid = { "That's a good start.", "Interesting. Keep going.", "Not bad at all.", "Okay, I like where this is going." },
	weak = { "Nice words. I'd like to see it for real.", "Everyone says that. Prove it.", "Hmm. Talk is cheap." },
	miss = { "Sure, but that's not really my thing.", "Okay... not what I was asking about.", "Hm. That doesn't move me much." },
	repeated = { "You said that already.", "Heard that one." },
}
local DIRECTION = {
	strong = "You are genuinely impressed: it is exactly what you care about.",
	mid = "You are interested, but you want more.",
	weak = "You are skeptical: it sounds like talk without proof.",
	miss = "You are politely unimpressed: it is not what you care about.",
	repeated = "They already told you that. Point it out lightly.",
}
local ROLE_WORD = { engineer = "engineer", designer = "designer", sales = "salesperson", recruiter = "recruiter", research = "researcher" }

local function pick(list, r) return list[((r - 1) % #list) + 1] end
local function anyOf(list) return list[math.random(1, #list)] end

-- what the company can honestly say (built from the live session)
local function facts(player)
	local s = api.session(player)
	local plot = api.plotOf(player)
	local f = { staff = s and s.staff or 0, launches = s and s.launches or 0, rate = math.floor(s and s.rate or 0),
		hq = plot and plot.hq.level or 1, researchers = 0, skilled = 0, studio = 0, servers = false,
		company = (s and s.name and s.name ~= "") and s.name or "your company" }
	for _, r in ipairs(s and s.rigs or {}) do
		local role = r.rig and r.rig:GetAttribute("Role")
		if role == "research" then f.researchers += 1 end
		if (r.talent or 1) >= 2 then f.skilled += 1 end
		if (r.talent or 1) >= 3 and (not f.best or r.talent > f.best.talent) then
			f.best = { talent = r.talent, name = r.rig and r.rig:GetAttribute("PersonName") or "someone great", role = role or "engineer" }
		end
	end
	for _, sl in ipairs(plot and plot.slots or {}) do
		if sl.built == "studio" then f.studio = math.max(f.studio, sl.level or 1) end
		if sl.built == "servers" then f.servers = true end
	end
	return f
end

-- one reply per thesis: text + how true it is (0 talk, 1 some proof, 2 real proof)
local CLAIM = {}
CLAIM.ai = function(f, r)
	if f.servers and f.researchers >= 2 then return pick({ "Our researchers train models on our own servers.", "We run our own server room. Real AI, not a wrapper." }, r), 2 end
	if f.servers or f.researchers >= 1 then return pick({ "We run our own servers for our AI.", "We have researchers working on our AI." }, r), 1 end
	return pick({ "We're adding AI to everything we build.", "AI is the future, and we're all in." }, r), 0
end
CLAIM.growth = function(f, r)
	if f.staff >= 12 then return (pick({ "We've grown to %d people.", "%d people work here now, and we keep hiring." }, r)):format(f.staff), 2 end
	if f.staff >= 5 then return (pick({ "We're %d people and hiring fast.", "We doubled the team. %d people now." }, r)):format(f.staff), 1 end
	return pick({ "We're small, but we're growing fast.", "We're about to hire a lot of people." }, r), 0
end
CLAIM.team = function(f, r)
	if f.best then
		local t = string.upper(api.TALENT[f.best.talent] and api.TALENT[f.best.talent].name or "STAR")
		return (pick({ "We just signed a %s %s: %s.", "Our best hire? A %s %s named %s." }, r)):format(t, ROLE_WORD[f.best.role] or "engineer", f.best.name), 2
	end
	if f.skilled >= 1 then return (pick({ "We have %d skilled people already.", "%d of our people are skilled hires." }, r)):format(f.skilled), 1 end
	return pick({ "We hire people who ship.", "Our team works really hard." }, r), 0
end
CLAIM.product = function(f, r)
	if f.launches >= 6 then return (pick({ "We've shipped %d apps. Users keep coming back.", "%d apps shipped, and counting." }, r)):format(f.launches), 2 end
	if f.launches >= 2 then return (pick({ "We've shipped %d apps already.", "Our %d apps are live right now." }, r)):format(f.launches), 1 end
	return pick({ "Our first app is live.", "We just shipped our first app." }, r), 0
end
CLAIM.design = function(f, r)
	if f.studio >= 3 then return (pick({ "Our design studio is level %d. Everything we ship looks great.", "We have a level %d design studio." }, r)):format(f.studio), 2 end
	if f.studio >= 1 then return pick({ "We built our own design studio.", "Our designers have their own studio." }, r), 1 end
	return pick({ "We care a lot about design.", "Design matters to us." }, r), 0
end
CLAIM.profit = function(f, r)
	local money = api.fmt(f.rate)
	if f.hq >= 3 then return (pick({ "We make $%s every second, and it keeps growing.", "$%s a second, and climbing." }, r)):format(money), 2 end
	if f.hq >= 2 then return (pick({ "We're already making $%s a second.", "We're profitable: $%s a second." }, r)):format(money), 1 end
	return pick({ "We'll be profitable soon.", "Money is starting to come in." }, r), 0
end

-- ============ THE MODEL (writes words; never scores) ============

local bucket = { tokens = 20, at = os.clock() }
local function takeToken()
	local t = os.clock()
	bucket.tokens = math.min(20, bucket.tokens + (t - bucket.at) * (30 / 60))
	bucket.at = t
	if bucket.tokens < 1 then return false end
	bucket.tokens -= 1
	return true
end

local function sanitize(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("Content generated by artificial intelligence[^%.]*%.?%s*", "")
	text = text:gsub("\u{2019}", "'"):gsub("\u{2018}", "'"):gsub("\u{201C}", ""):gsub("\u{201D}", ""):gsub("\u{2014}", ", ")
	text = text:gsub("[\128-\255]", "")                 -- no emoji or stray unicode
	text = text:gsub('"', ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #text < 3 or text:find("%d") or text:find("%$") then return nil end   -- never a number: numbers are the game's
	local low = text:lower()
	for _, bad in ipairs({ "as an ai", "i'm an ai", "language model", "i can't", "i cannot", "sorry, but", "assistant" }) do
		if low:find(bad, 1, true) then return nil end
	end
	-- the investor's question comes from the game (it carries the hint), so a
	-- question the model asks on its own is dropped, sentence by sentence
	if text:find("?", 1, true) then
		local kept = {}
		for sentence in (text .. " "):gmatch("(.-[%.!%?])%s+") do
			if not sentence:find("?", 1, true) then table.insert(kept, sentence) end
		end
		text = table.concat(kept, " ")
		if #text < 3 then return nil end
	end
	if #text > 150 then
		local cut = text:sub(1, 150)
		local stop = cut:match("^.*()[%.!%?]")
		text = stop and cut:sub(1, stop) or (cut .. "...")
	end
	return text
end

local function aiReact(thread, said, verdict)
	if not takeToken() then return nil end
	local P = thread.persona
	if not thread.tg or not thread.tg.Parent then
		local ok, tg = pcall(function()
			local g = Instance.new("TextGenerator")
			g.Name = "InvestorVoice"
			g.SystemPrompt = ("You are %s, a venture capitalist at %s (a made-up firm), texting a young founder inside a Roblox tycoon game. "
				.. "You care most about %s. Write exactly ONE short, casual text message, under 18 words. No emojis, no hashtags, "
				.. "no quotation marks, no numbers or money amounts. Do not ask a question. Keep it friendly and fine for kids.")
				:format(P.name, P.firm, THESIS[thread.thesis].desc)
			g.Temperature = 0.8
			g.Parent = ServerScriptService
			return g
		end)
		if not ok then return nil end
		thread.tg = tg
	end
	local done, out = false, nil
	task.spawn(function()
		local ok, res = pcall(function()
			return thread.tg:GenerateTextAsync({
				UserPrompt = ("The founder texted: %s\nHow you feel: %s\nYour text:"):format(said, DIRECTION[verdict] or DIRECTION.mid),
				MaxTokens = 50,
			})
		end)
		if ok and type(res) == "table" then out = sanitize(res.GeneratedText) end
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 4 do task.wait(0.1) end
	return out
end

-- ============ THREADS ============

local state = {}        -- player -> { threads = {}, active, nextAt, recent = {}, serial }
local serial = 0

local function send(player, payload)
	if event and player.Parent then event:FireClient(player, payload) end
end

local function unread(player, n)
	player:SetAttribute("PhoneUnread", math.max(0, (player:GetAttribute("PhoneUnread") or 0) + n))
end

local function snapshot(th)
	return { id = th.id, name = th.persona.name, first = th.persona.first, firm = th.persona.firm, color = th.persona.color,
		msgs = th.msgs, status = th.status, offer = th.offer, chips = th.chipsOut, round = th.round }
end

local function say(player, th, from, text, notify)
	local m = { from = from, text = text, t = os.time() }
	table.insert(th.msgs, m)
	if #th.msgs > 40 then table.remove(th.msgs, 1) end
	if from == "them" then unread(player, 1) end
	send(player, { kind = "msg", id = th.id, msg = m, notify = notify and from == "them", name = th.persona.first,
		firm = th.persona.firm, color = th.persona.color })
end

local function jaccard(a, b)
	local A, B, inter, uni = {}, {}, 0, 0
	for w in a:lower():gmatch("%w+") do A[w] = true end
	for w in b:lower():gmatch("%w+") do B[w] = true end
	for w in pairs(A) do uni += 1; if B[w] then inter += 1 end end
	for w in pairs(B) do if not A[w] then uni += 1 end end
	return uni == 0 and 0 or inter / uni
end

-- three replies: one on the investor's thesis, two on others, shuffled
local function makeChips(player, th)
	local f = facts(player)
	local others = {}
	for _, t in ipairs(THESES) do if t ~= th.thesis then table.insert(others, t) end end
	for i = #others, 2, -1 do local j = math.random(1, i); others[i], others[j] = others[j], others[i] end
	local chips = {}
	for k, t in ipairs({ th.thesis, others[1], others[2] }) do
		local text, strength = CLAIM[t](f, th.round + k)
		table.insert(chips, { text = text, thesis = t, strength = strength })
	end
	for i = #chips, 2, -1 do local j = math.random(1, i); chips[i], chips[j] = chips[j], chips[i] end
	th.chips = chips
	th.chipsOut = {}
	for i, c in ipairs(chips) do th.chipsOut[i] = c.text end
	send(player, { kind = "chips", id = th.id, chips = th.chipsOut, round = th.round })
end

local function niceMoney(n)
	if n < 1000 then return math.floor(n / 10 + 0.5) * 10 end
	local mag = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / mag + 0.5) * mag
end

local function close(player, th, reason)
	th.status = "closed"
	th.chips, th.chipsOut = nil, nil
	if th.tg then th.tg:Destroy(); th.tg = nil end
	local st = state[player]
	if st and st.active == th then
		st.active = nil
		st.nextAt = os.clock() + math.random(240, 360)
	end
	send(player, { kind = "closed", id = th.id, reason = reason })
end

-- v4.5 THE ECONOMY CLOCK: an offer is a share of what you are saving for, never all of it
local Prog = require(script.Parent:WaitForChild("Progression"))
local function capped(player, kind, amount)
	local goal = api.nextGoal and api.nextGoal(player)
	return Prog.capWindfall(kind, amount, goal)
end

local function makeOffer(player, th)
	local s = api.session(player)
	local rate = s and s.rate or 0
	local f = facts(player)
	local interest = th.interest
	if interest <= 1 then
		say(player, th, "them", "I don't think we're a fit right now. Good luck, really.")
		close(player, th, "pass")
		return
	end
	local amount = niceMoney(math.max(200 * f.hq, rate * (20 + 12 * interest)) * (th.boost or 1))   -- v4.3 a Series A is x3
	amount = capped(player, th.series and "series" or "phone", amount)
	local item = (interest >= 8 and "frontpage") or (interest >= 6 and anyOf({ "scout", "noncompete" }))
		or (interest >= 4 and anyOf({ "coffee", "energy" })) or nil
	th.offer = { amount = amount, item = item, interest = interest, canPush = true }
	th.status = "offer"
	say(player, th, "them", interest >= 6 and "Okay. I'm in. Here's my offer." or "Here's what I can do.")
	send(player, { kind = "offer", id = th.id, amount = amount, item = item })
end

-- TAKE on a term sheet: the button and the v4.4 pace bot share this one path
local function takeOffer(player, th)
	local o = th.offer
	th.status = "busy"
	local cash = api.cash(player)
	if cash then cash.Value += o.amount end
	if o.item then api.grant(player, o.item, 1, th.persona.first .. " sent a gift") end
	say(player, th, "them", "Done. Sending it now. Talk soon!")
	send(player, { kind = "paid", id = th.id, amount = o.amount })
	if th.series and api.onSeriesA then api.onSeriesA(player) end
	close(player, th, "deal")
	return o.amount
end

-- the investor answers what you said; then the next question, or the offer
local function respond(player, th, said, verdict, gain)
	th.interest += gain
	th.status = "typing"
	send(player, { kind = "typing", id = th.id, on = true })
	local t0 = os.clock()
	local text = aiReact(th, said, verdict)
	th.aiUsed = th.aiUsed or (text ~= nil)
	local wait = math.random(12, 22) / 10 - (os.clock() - t0)
	if wait > 0 then task.wait(wait) end
	if th.status == "closed" then return end
	send(player, { kind = "typing", id = th.id, on = false })
	say(player, th, "them", text or anyOf(REACT[verdict] or REACT.mid), true)
	th.round += 1
	if th.round > 3 then
		task.wait(0.9)
		if th.status ~= "closed" then makeOffer(player, th) end
		return
	end
	task.wait(0.8)
	if th.status == "closed" then return end
	say(player, th, "them", THESIS[th.thesis].probes[th.round], true)
	th.status = "wait"
	th.deadline = os.clock() + 180
	makeChips(player, th)
end

local function reply(player, th, text, chip)
	if th.status ~= "wait" then return end
	local verdict, gain = "miss", 0
	local shown = text
	if chip then
		verdict = (chip.thesis ~= th.thesis) and "miss" or ((chip.strength >= 2 and "strong") or (chip.strength == 1 and "mid") or "weak")
		gain = (chip.thesis ~= th.thesis) and 0 or (1 + chip.strength)
	else
		-- typed: the RAW text is scored (filtering can hash words for young accounts); the filtered one is shown
		local low = " " .. text:lower() .. " "
		local hit = false
		for _, kw in ipairs(THESIS[th.thesis].keywords) do
			if low:find("%f[%w]" .. kw .. "%f[%W]") then hit = true break end
		end
		verdict, gain = hit and "mid" or "miss", hit and 2 or 0
		local ok, res = pcall(function()
			return TextService:FilterStringAsync(text, player.UserId):GetNonChatStringForUserAsync(player.UserId)
		end)
		if not ok or type(res) ~= "string" then return end          -- never show unfiltered text
		shown = res
	end
	for _, prev in ipairs(th.said) do
		if jaccard(prev, text) >= 0.6 then verdict, gain = "repeated", 0 break end
	end
	table.insert(th.said, text)
	th.status = "busy"
	th.chips, th.chipsOut = nil, nil
	say(player, th, "me", shown)
	task.spawn(respond, player, th, shown, verdict, gain)
end

local function startThread(player, opts)
	local st = state[player]
	local recent = st.recent
	local pool = {}
	for _, P in ipairs(PERSONAS) do if not table.find(recent, P.id) then table.insert(pool, P) end end
	local P = anyOf(#pool > 0 and pool or PERSONAS)
	table.insert(recent, P.id)
	if #recent > 3 then table.remove(recent, 1) end
	serial += 1
	local th = { id = serial, persona = P, thesis = P.thesis, round = 1, interest = 0, status = "wait", msgs = {}, said = {},
		deadline = os.clock() + 180, boost = opts and opts.boost or 1, series = opts and opts.series or nil }
	table.insert(st.threads, 1, th)
	while #st.threads > 6 do table.remove(st.threads) end
	st.active = th
	local f = facts(player)
	send(player, { kind = "thread", thread = snapshot(th) })
	say(player, th, "them", opts and opts.opener and opts.opener:format(P.first, P.firm, f.company)
		or (anyOf(OPENERS)):format(P.first, P.firm, f.company), true)
	task.wait(1.1)
	say(player, th, "them", THESIS[th.thesis].probes[1], false)
	makeChips(player, th)
end

local function findThread(player, id)
	local st = state[player]
	if not st then return nil end
	for _, th in ipairs(st.threads) do if th.id == id then return th end end
	return nil
end

-- ============ CALLS ============

local calls = {}          -- userId -> { other = userId, state = "calling"|"ringing"|"connected", id }
local blocked = {}        -- userId -> { [userId] = true }  (this session only)
local cooldown = {}       -- "caller:target" -> os.clock() of a declined/unanswered ring (no ring spam)
local RING_COOLDOWN = 45
local callSerial = 0

local function callSend(player, st, other, reason, id)
	send(player, { kind = "call", state = st, with = other and other.UserId, name = other and other.DisplayName,
		reason = reason, id = id })
end

local function endCall(player, reason)
	local c = calls[player.UserId]
	if not c then return end
	calls[player.UserId] = nil
	player:SetAttribute("InCall", nil)
	player:SetAttribute("CallSince", nil)
	callSend(player, "ended", Players:GetPlayerByUserId(c.other), reason, c.id)
	local other = Players:GetPlayerByUserId(c.other)
	local oc = other and calls[other.UserId]
	if other and oc and oc.id == c.id then
		calls[other.UserId] = nil
		other:SetAttribute("InCall", nil)
		other:SetAttribute("CallSince", nil)
		callSend(other, "ended", player, reason == "hangup" and "They hung up" or reason, c.id)
	end
end

local function canTalk(a, b)
	local ok, allowed = pcall(function()
		return TextChatService:CanUsersDirectChatAsync(a.UserId, { b.UserId })
	end)
	if ok and type(allowed) == "table" then return table.find(allowed, b.UserId) ~= nil end
	return RunService:IsStudio()          -- the check is unavailable in Studio; live servers must pass it
end

local function startCall(player, toId)
	local other = type(toId) == "number" and Players:GetPlayerByUserId(toId)
	if not other or other == player then return end
	if calls[player.UserId] then return end
	if not player:GetAttribute("HasVoice") then return callSend(player, "ended", other, "Voice chat is off for your account") end
	if not other:GetAttribute("HasVoice") then return callSend(player, "ended", other, other.DisplayName .. " doesn't have voice chat") end
	if calls[other.UserId] then return callSend(player, "ended", other, other.DisplayName .. " is on another call") end
	if blocked[other.UserId] and blocked[other.UserId][player.UserId] then return callSend(player, "ended", other, "No answer") end
	local key = player.UserId .. ":" .. other.UserId
	if cooldown[key] and os.clock() - cooldown[key] < RING_COOLDOWN then
		return callSend(player, "ended", other, "Give them a minute before calling again")
	end
	if not canTalk(player, other) then return callSend(player, "ended", other, "You can't call this player") end
	callSerial += 1
	local id = callSerial
	calls[player.UserId] = { other = other.UserId, state = "calling", id = id }
	calls[other.UserId] = { other = player.UserId, state = "ringing", id = id }
	callSend(player, "calling", other, nil, id)
	callSend(other, "ringing", player, nil, id)
	task.delay(25, function()
		local c = calls[player.UserId]
		if c and c.id == id and c.state == "calling" then
			cooldown[player.UserId .. ":" .. other.UserId] = os.clock()
			endCall(player, "No answer")
		end
	end)
end

local function answer(player, accept, block)
	local c = calls[player.UserId]
	if not c or c.state ~= "ringing" then return end
	local other = Players:GetPlayerByUserId(c.other)
	if not other or not calls[other.UserId] or calls[other.UserId].id ~= c.id then endCall(player, "Call ended") return end
	if not accept then
		cooldown[other.UserId .. ":" .. player.UserId] = os.clock()
		if block then
			blocked[player.UserId] = blocked[player.UserId] or {}
			blocked[player.UserId][other.UserId] = true
		end
		calls[player.UserId] = nil
		callSend(player, "ended", other, nil, c.id)
		calls[other.UserId] = nil
		callSend(other, "ended", player, "Declined", c.id)
		return
	end
	local t = workspace:GetServerTimeNow()
	calls[player.UserId].state = "connected"
	calls[other.UserId].state = "connected"
	player:SetAttribute("InCall", other.UserId)
	other:SetAttribute("InCall", player.UserId)
	player:SetAttribute("CallSince", t)
	other:SetAttribute("CallSince", t)
	callSend(player, "connected", other, nil, c.id)
	callSend(other, "connected", player, nil, c.id)
end

-- ============ WIRING ============

function Phone.init(a)
	api = a
	local folder = ReplicatedStorage:WaitForChild("SVRemotes")
	event = folder:FindFirstChild("PhoneEvent") or Instance.new("RemoteEvent")
	event.Name = "PhoneEvent"
	event.Parent = folder
	local action = folder:FindFirstChild("PhoneAction") or Instance.new("RemoteEvent")
	action.Name = "PhoneAction"
	action.Parent = folder
	local lastAction = {}

	action.OnServerEvent:Connect(function(player, msg)
		if type(msg) ~= "table" or type(msg.a) ~= "string" then return end
		local t = os.clock()
		if lastAction[player] and t - lastAction[player] < 0.25 then return end
		lastAction[player] = t
		-- texting and calling are playing: they keep you from going AWAY
		local sess = api and api.session and api.session(player)
		if sess and msg.a ~= "read" then sess.lastTap = t end
		if msg.a == "reply" then
			local th = findThread(player, msg.id)
			if th and th.chips and type(msg.chip) == "number" then
				local chip = th.chips[math.floor(msg.chip)]
				if chip then reply(player, th, chip.text, chip) end
			end
		elseif msg.a == "text" then
			local th = findThread(player, msg.id)
			if th and type(msg.text) == "string" then
				local text = msg.text:sub(1, 120):gsub("^%s+", ""):gsub("%s+$", "")
				if #text >= 2 then reply(player, th, text, nil) end
			end
		elseif msg.a == "offer" then
			local th = findThread(player, msg.id)
			if not th or th.status ~= "offer" or not th.offer then return end
			local o = th.offer
			if msg.choice == "take" then
				takeOffer(player, th)
				return
			end
			th.status = "busy"
			if msg.choice == "push" then
				local ok = o.interest >= 7 or (o.interest >= 4 and math.random() < (o.interest - 3) / 4)
				say(player, th, "me", "Can you do better?")
				task.wait(1.2)
				if ok then
					local amount = capped(player, th.series and "seriesPush" or "push", niceMoney(o.amount * 1.5))
					local cash = api.cash(player)
					if cash then cash.Value += amount end
					if o.item then api.grant(player, o.item, 1, th.persona.first .. " sent a gift") end
					say(player, th, "them", "You drive a hard bargain. Fine. Deal.")
					send(player, { kind = "paid", id = th.id, amount = amount })
					if th.series and api.onSeriesA then api.onSeriesA(player) end
					close(player, th, "deal")
				else
					say(player, th, "them", "Then we'll pass. Good luck out there.")
					close(player, th, "walked")
				end
			else
				say(player, th, "them", "No worries. My door's open.")
				close(player, th, "passed")
			end
		elseif msg.a == "read" then
			player:SetAttribute("PhoneUnread", 0)
		elseif msg.a == "voice" then
			player:SetAttribute("HasVoice", msg.ok == true)
		elseif msg.a == "call" then
			startCall(player, msg.to)
		elseif msg.a == "answer" then
			answer(player, msg.accept == true, msg.block == true)
		elseif msg.a == "hangup" then
			endCall(player, "hangup")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		endCall(player, "Call ended")
		local st = state[player]
		if st then
			for _, th in ipairs(st.threads) do if th.tg then th.tg:Destroy() end end
		end
		state[player] = nil
		lastAction[player] = nil
		blocked[player.UserId] = nil
	end)

	-- the investor clock: the first one after HQ 2, then one every 4 to 6 minutes
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local s = api.session(player)
				local plot = api.plotOf(player)
				if s and plot then
					local company = (s.name and s.name ~= "") and s.name or ""
					if player:GetAttribute("Company") ~= company then player:SetAttribute("Company", company) end
					local st = state[player]
					if not st then st = { threads = {}, recent = {} }; state[player] = st end
					if plot.hq.level >= 2 and s.shipped then
						if not st.nextAt then st.nextAt = os.clock() + 25 end
						local th = st.active
						if th and th.status == "wait" and os.clock() > (th.deadline or math.huge) then
							say(player, th, "them", "Looks like you're busy. Another time!")
							close(player, th, "timeout")
						elseif th and th.status == "offer" and os.clock() > (th.deadline or math.huge) + 120 then
							say(player, th, "them", "Offer's off the table for now. Talk later.")
							close(player, th, "timeout")
						elseif not th and os.clock() >= st.nextAt then
							st.nextAt = math.huge
							task.spawn(startThread, player)
						end
					end
				end
			end
		end
	end)
end

-- v4.2: a one-off text from someone who is not an investor (the Residences'
-- front desk about your VIP). Scripted, so no AI badge on the avatar.
--[[ v4.3 THE SERIES A (the HQ 4 task): an investor texts you right away with a
round worth 3x a normal term sheet. Retried by SiliconCore every 90 s until a
deal closes; never stacks on a Series A that is still open. ]]
function Phone.seriesA(player)
	local st = state[player]
	-- the first call can come the second a returning player joins, before the phone
	-- loop has made their state (live test: silently skipped, then a 90 s wait)
	if not st then st = { threads = {}, recent = {} }; state[player] = st end
	local a = st.active
	if a and a.series and a.status ~= "closed" and a.status ~= "deal" and a.status ~= "pass" then return end
	startThread(player, { boost = 3, series = true,
		opener = "Hi, it's %s from %s. We lead Series A rounds, and %s is on our list. Pitch me." })
end

function Phone.notice(player, id, first, firm, text)
	if not (player and player.Parent) then return end
	unread(player, 1)
	send(player, { kind = "msg", id = id, name = first, firm = firm, color = Color3.fromRGB(255, 190, 70), system = true,
		notify = true, msg = { from = "them", text = text, t = os.time() } })
end

-- the client asks for everything on join (and after a respawn of the UI)
function Phone.snapshot(player)
	local st = state[player]
	local out = {}
	for _, th in ipairs(st and st.threads or {}) do table.insert(out, snapshot(th)) end
	return out
end

-- Studio tests only
-- Studio test hooks (v4.3): the live thread, and a term sheet through the real makeOffer
function Phone.devActive(player)
	if not game:GetService("RunService"):IsStudio() then return nil end
	local st = state[player]
	local th = st and st.active
	if not th then return nil end
	return { id = th.id, series = th.series, boost = th.boost, firm = th.persona and th.persona.firm, status = th.status,
		first = th.msgs[1] and th.msgs[1].text, offer = th.offer and th.offer.amount }
end
function Phone.devOffer(player, interest)
	if not game:GetService("RunService"):IsStudio() then return nil end
	local st = state[player]
	local th = st and st.active
	if not th then return nil end
	th.interest = interest or 8
	makeOffer(player, th)
	return th.offer and th.offer.amount, th.id
end

-- v4.4 pace bot: a player who reads the texts and takes the term sheet. Returns
-- the amount paid, or nil while there is no offer yet (it asks for one first).
function Phone.devTake(player, interest)
	if not game:GetService("RunService"):IsStudio() then return nil end
	local st = state[player]
	local th = st and st.active
	if not th or th.status == "closed" or th.status == "busy" then return nil end
	if th.status ~= "offer" or not th.offer then
		th.interest = interest or 6
		makeOffer(player, th)
		if th.status ~= "offer" then return nil end
	end
	return takeOffer(player, th), th.series
end

function Phone._test() return { state = state, calls = calls, startThread = startThread, reply = reply, facts = facts,
	sanitize = sanitize, startCall = startCall, answer = answer, endCall = endCall } end

return Phone
