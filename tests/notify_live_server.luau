local p = game.Players:GetPlayers()[1]
local R = game.ReplicatedStorage.SVRemotes
R.TalentReveal:FireClient(p, { tier = 4, name = "Genius", color = {0.9, 0.6, 0.1}, role = "engineer", who = "Test Person", mult = 5, odds = 150, newIndex = false })
R.Celebrate:FireClient(p, { kind = "hq", level = 3, name = "TEST HQ", chips = { "one", "two" } })
R.Celebrate:FireClient(p, { kind = "milestone", earned = 1000000, bonus = 2 })
R.PhoneEvent:FireClient(p, { kind = "msg", id = "t_live", name = "Tess", firm = "Test Ventures", notify = true, msg = { from = "them", text = "Live notify test" } })
R.Toast:FireClient(p, "Your own line")
R.Toast:FireClient(p, "Somebody else's news", "news")
R.ItemEvent:FireClient(p, { kind = "got", id = "coffee", n = 1, source = "Live test" })
return "fired 7"
