# Valley (the shared server: founder boards and the market bell)
**What:** Up to six founders share one server and one campus. The server publishes each plot's owner, company, level, valuation and rank as attributes. Every client draws one board over each occupied tower. Every few minutes a 90 second "market bell" opens. Whoever grows their valuation most wins a payday and a gold ball over their tower. This is not the terrain: terrain is `src/ServerScriptService/ValleyGen.lua`.
**How a player reaches it:**
1. Join a server. Boards appear on their own once a plot has an owner. There is no menu.
2. The first bell opens 150 s after server start, then every 330 s (`src/ServerScriptService/Valley.lua:39-41, 154`). A toast says "THE MARKET BELL" (:116).
3. During the 90 s the player grows valuation (earning raises it every tick, `SiliconCore.server.lua:3095`). Their board shows `+gain` in green.
4. The bell closes. The best gain gets a payday of 45 s of income (:42, :137-141). A toast names the winner (:143).
**Files:**
- `src/ServerScriptService/Valley.lua`: `publish` :78, `openBell` :108, `closeBell` :119, `init` :149, `forceBell` :183, `endBell` :184.
- `src/StarterPlayer/StarterPlayerScripts/ValleyClient.client.lua`: `towerTop` :52, `makeBoard` :73, `redraw` :144, `setCrown` :182, wiring :218-251.
- `src/ServerScriptService/SiliconCore.server.lua:3695-3712`: starts it with `plots`, `session`, `plotOf`, `cash`, `fmt`, `toast`, `level`. The level comes from `Econ.Wafers.level(plot)` (:3708), so the board shows the wafer level (1 to 100), not the stage.
**State:**
- Per plot folder (`Plots/PlotN`): `OwnerId`, `Company`, `Valuation`, `Listed`, `Rank`, `Level`, `BellGain` (`Valley.lua:86-92`). Cleared when nobody owns the plot (:97-103). Refresh every 2 s (:43).
- On the `Plots` folder: `BellOn`, `BellSeconds`, `BellWinner` (a plot folder name, e.g. "Plot3") (`Valley.lua:114-115, 142, 152-153`).
- Module state: `bell` = `on`, `startedAt`, `base` (valuation per user at open), `nextAt` (:46).
- Session: `s.valuation`, `s.rate`, `s.ipo`, `s.name`. Nothing new is saved. The valuation itself is saved (`SaveLoad.lua:174`).
- Client only: `boards[folder]` parts named `SVFounderBoard`, a ball named `SVRoundCrown` (`ValleyClient.client.lua:73, 182`).
**Drive it:**
- Raw `bell` opens the bell at the next 1 s tick. `bell end` closes it (`DevHook.lua:102-110`). It needs a player in the server.
- `valuation <n>` sets `s.valuation` (`DevHook.lua:184`). Open the bell, then raise it, then `bell end`, to make a winner. Untested.
- Scenarios: none yet. Always go through SVDev. A `require` from `execute_luau` returns a copy that the game does not use (`DevHook.lua:103-107`).
**Prove it:** no automated check yet. No spec requires `Valley.lua`. `SVCheck` has nothing for boards or the crown.
**Gotchas:**
- `forceBell` only sets `nextAt = 0` (`Valley.lua:183`). If a bell is already on, nothing happens. `endBell` does nothing when no bell is on (:184).
- With zero growth the bell closes "with nothing built" and sets `BellWinner` to the number 0, not "" (`Valley.lua:130-135`). The client only treats "" as empty (`ValleyClient.client.lua:184`). Unclear what `FindFirstChild(0)` does there.
- Nothing reads `BellOn` or `BellSeconds`. I searched `src`. The only client signal is the toast (`Valley.lua:116`) and `BellGain` on boards.
- The toast text says "90 seconds" as a literal (`Valley.lua:143`). `BELL_WINDOW` is separate. Change both.
- The crown is placed once, at `towerTop + 30`. The timer only spins it, so a tower that grows later leaves it behind (`ValleyClient.client.lua:182-216, 249`).
- `towerTop` walks the parts of the plot's `Wafers` folder, because it is a Folder and has no bounding box (`ValleyClient.client.lua:52-71`).
- Boards use studs for size and `MaxDistance` is measured from `camera.Focus`. In a cutscene they pop in and out. This is expected (`ValleyClient.client.lua:19-21`).
- `Valley.init` runs inside a `pcall`. A failure only warns, and the server runs without boards (`SiliconCore.server.lua:3701-3710`).
- SiliconCore is at the 200 top-level local limit, so no handle to `Valley` is kept (:3711-3712). Tests must `require` it again.
- The bell never opens in an empty server (`Valley.lua:173`).
**Last verified:** 2026-10-09 287a211
