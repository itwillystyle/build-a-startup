--[[ PaletteLoad: Palette for the server's part builders, or false if it failed
	to load. The world still builds then, just without its colours mapped, so
	every caller checks `if Pal then`. A ModuleScript cannot return nil, hence
	false. Required once and cached, so a failure warns once. ]]
local ok, m = pcall(require, script.Parent:WaitForChild("Palette", 5))
if ok and m then return m end
warn("[SV] Palette missing; colours will not be mapped")
return false
