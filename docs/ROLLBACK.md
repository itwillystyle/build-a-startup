# When something breaks on live

Do these in order. Stop at the first one that fixes it.
Every step runs from Studio (the Build a Startup! place open, in **Edit**, not Play).

## 1. Turn the feature off (1 minute, no publish)

If the broken thing has a flag (see `Flags.DEFAULTS` in `src/ServerScriptService/Flags.lua`):

    require(game.ServerScriptService.Flags:Clone()).set("bobScenes", false, "live")

Every live server reads it within 60 s. Check it took:

    require(game.ServerScriptService.Flags:Clone()).get("live")

Turn it back on with `true` once the fix is published.

| Flag | Off means |
|---|---|
| `bobScenes` | No Bob cutscenes. New players get the old flyover; Bob's door still pays, with a toast. |

## 2. See what is breaking

    require(game.ServerScriptService.ErrorLog:Clone()).read(2)

Today and yesterday, live servers and players' clients, most frequent first. `v0` is the
place version an error first appeared in: one that starts at the newest version came with
the last publish. The doctor routine reads this every morning.

## 3. Put the last good version back

Creator Dashboard > the experience > the place > **Version History** > the version before
the bad publish > **Restore**. Then **Shut down all servers** (or "Restart servers for
updates") so nobody stays on the bad one.

Then make git match: revert the merge on a branch (`git revert -m 1 <merge sha>`), open a
PR, let CI and the doctor gate pass, merge, publish. Studio must be serving `main` (Rojo)
before the publish.

## 4. A player's save got damaged

The player must be **offline** (a live session saves over a restore within a minute).

    local R = require(game.ServerScriptService.SaveRescue:Clone())
    R.list(<userId>)                       -- the last 30 days of versions, newest first
    R.peek(<userId>, "<version>")          -- cash, hq, staff, lastSeen of one version
    R.restore(<userId>, "<version>", "restore <userId>")

`restore` backs up the current save first (SVRescue_v1, the key is in the result), so a
wrong pick can be undone the same way.

## After

Write down what broke and the check that would have caught it (a test, a doctor step, a
flag). That is how the same thing never ships twice.
