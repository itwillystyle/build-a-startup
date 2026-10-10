# Not Built: Valley Markets and Founders Coffee
**What:** These two shops are named in the plans but do not exist as places you can use. There is no building, no prompt, no menu, no code that sells anything there. Do not look for a feature. Do not "fix" a missing shop.
**Where the plan says so (outside the repo, in the parent folder):**
- `../REFERENCE.md` section E6, "Food markets: customer sanity". It says "Nothing in code" and that the economy spec chose not to build them. The open question is what "customer sanity" would change.
- `../docs/superpowers/specs/2026-10-07-loop-complements-design.md`, heading "Founders Coffee and Valley Markets are not built". Downtown has two destinations only: The Residences and Valley Motors. A shop you must drive to, selling what the phone already sells, is an errand with a sign on it. If the world needs more life, it should come from the environment work (its section 8).
**What I checked (grep of `src` for "Coffee" and "Market", 2026-10-09):**
- No file defines a shop, prompt or remote for either name. `tests/` and `tools/` have no hit either.
- That same spec describes a phone shop with sale prices. `packPrice` and `SALE_SECONDS` do not appear in `src`, so that is also not built.
**What exists nearby (do not confuse these with the shops):**
- Signs only, in the retail district: a shop awning reads "FOUNDER COFFEE" (`src/ServerScriptService/CampusDistricts.lua:450`) and the grocery name band reads "VALLEY MARKET" (:468). A food truck menu has a "COFFEE" line (:577). The file says districts are scenery with no prompts (`CampusDistricts.lua:16`).
- The `coffee` item is shown as "Cold Brew" in the bag: 3x code for 60 s (`src/ReplicatedStorage/Items.lua:32`). It comes from the daily ladder, launches and investors. See daily-bag.md.
- Coffee decor: the "Coffee Maker" furniture piece (`src/ReplicatedStorage/FurnitureKit.lua:222`), the Sky Cafe coffee bar (`src/ServerScriptService/HQFloors.lua:16, 454-460`), and a machine in each apartment (`Apartments.lua:181`).
- `CFG.MARKETS` are the six product categories you pick when you launch an app: SOCIAL, GAMES, AI, FINTECH, HEALTH, DELIVERY (`src/ServerScriptService/CoreConfig.lua:100-114`). They drive the `PickMarket` remote (`SiliconCore.server.lua:3294`), not any shop. "Market share" is about rivals.
- The market bell is a shared 90 s growth race every 330 s in `src/ServerScriptService/Valley.lua` (:25-31, :40-43). Drive it with SVDev `bell` or `bell end` (`DevHook.lua:102-109`).
- "Valley Exchange" is the name of the public company board and the GO PUBLIC step (`Journey.lua:45`, `Ranks.lua:6`). Not a market you walk into.
**Drive it:** none. Nothing to jump to.
**Prove it:** no automated check. To re-confirm, grep `src` for `Coffee` and `Market` and check that no hit adds a prompt, menu or remote.
**Gotchas:**
- The word "market" means three things here: product category, the bell, and the Exchange board. Read the file before assuming which.
- If someone builds one of these shops, the plan says it must land on an existing beat (a launch or a hire), not add a trip (`../REFERENCE.md` E6).
**Last verified:** 2026-10-10 a7700e2
