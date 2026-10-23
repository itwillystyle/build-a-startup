# 001 — Make the HOLD TO CODE fill move at a steady speed

- **Status**: DONE (23 Oct, branch crisp-payout, verified live in Studio)
- **Commit**: 084bd8b
- **Severity**: MEDIUM
- **Category**: 2. Easing & duration
- **Estimated scope**: 1 file, ~6 lines

## Problem

HOLD TO CODE is the most-pressed control in the game. The server publishes `CodeProgress`
every 0.25 s (`src/ServerScriptService/ClientsServer.lua:658`; the cadence is stated in
`src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua:512-517`). Each update tweens the
fill with the file's default curve, Quint Out over 0.2 s, so the fill surges forward and stops
four times a second instead of flowing:

```lua
-- src/StarterPlayer/StarterPlayerScripts/HudClient.client.lua:427-433 — current
local chargeTween
local function setCoding()
	local p = math.clamp(tonumber(player:GetAttribute("CodeProgress")) or 0, 0, 1)
	if chargeTween then chargeTween:Cancel() end
	chargeTween = tween(charge, 0.2, { Size = UDim2.new(p, 0, 1, -5) })
	syncCode()
end
```

`tween` (HudClient.client.lua:73) defaults to `Enum.EasingStyle.Quint, Enum.EasingDirection.Out`.
A reset to 0 (the app is finished, `ClientsServer.lua:736`) also tweens backwards.

## Target

Constant motion is linear. Match the duration to the update interval so each tween ends as
the next update arrives. A drop (the bar resets) snaps instead of draining.

```lua
-- target
local chargeTween
local CODE_TICK = 0.25   -- ClientsServer publishes CodeProgress every 0.25 s
local function setCoding()
	local p = math.clamp(tonumber(player:GetAttribute("CodeProgress")) or 0, 0, 1)
	if chargeTween then chargeTween:Cancel() end
	if p < charge.Size.X.Scale then
		charge.Size = UDim2.new(p, 0, 1, -5)   -- a reset snaps; it never drains backwards
	else
		-- constant motion is linear, one update interval long, so the fill flows instead of surging
		chargeTween = tween(charge, CODE_TICK, { Size = UDim2.new(p, 0, 1, -5) }, Enum.EasingStyle.Linear)
	end
	syncCode()
end
```

## Repo conventions to follow

- Comments explain the why with the date, in Luke's terms (see any `-- 22 Oct` line).
- Easing goes through the file's `tween(o, t, props, style, dir)` helper (HudClient.client.lua:73).

## Steps

1. Replace `setCoding` at HudClient.client.lua:428-433 with the target above, keeping
   `local chargeTween` and the two lines after the function unchanged.

## Boundaries

- Do NOT touch anything else in HudClient (the cash counter, coin stream and pulses are other plans or deliberate).
- Do NOT change the server's publish rate.
- If the code at the cited lines differs, STOP and report.

## Verification

- **Mechanical**: from `Downloads/silicon-startup/game`: `~/.rokit/bin/selene src` → 0 errors;
  `~/.rokit/bin/lune run tests/offline/run` → all pass.
- **Feel check** (Studio, Play, hold E at the laptop for a client's app): the green fill moves
  at one steady speed with no visible pulsing; when the app finishes, the fill resets at once.
- **Done when**: the target is in place, selene and the offline tests pass.
