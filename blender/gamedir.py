"""
gamedir.py -- find the game's source tree from anywhere.

The Blender scripts write generated Lua straight into the game (HQMeta,
LowPolyData). They used to do it with a hardcoded hop:

    os.path.join(os.path.dirname(HERE), "game", "src", "ServerScriptService")

which only works while the Blender folder sits exactly one level above `game`.
The moment the repository is reorganised, that silently resolves to a path that
does not exist and the generated file is written somewhere nobody reads -- the
meshes then look correct in Blender and do nothing in the game, which is
exactly the silent half-wiring the HQMeta test was added to catch.

This walks UP from a starting point until it finds a directory holding
`src/ServerScriptService`, so it keeps working wherever the scripts live.
"""

import os

MARKER = os.path.join("src", "ServerScriptService")


def game_root(start=None):
    """The directory that CONTAINS src/ServerScriptService (the Rojo project root)."""
    here = os.path.abspath(start or os.path.dirname(os.path.abspath(__file__)))
    seen = []
    d = here
    while True:
        seen.append(d)
        # the game root itself, or a sibling called "game"
        for cand in (d, os.path.join(d, "game")):
            if os.path.isdir(os.path.join(cand, MARKER)):
                return os.path.abspath(cand)
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    raise RuntimeError(
        "could not find a directory containing %s, searched upward from %s:\n  %s"
        % (MARKER, here, "\n  ".join(seen))
    )


def server_dir(start=None):
    """<game>/src/ServerScriptService"""
    return os.path.join(game_root(start), "src", "ServerScriptService")


if __name__ == "__main__":
    print("game root :", game_root())
    print("server dir:", server_dir())
