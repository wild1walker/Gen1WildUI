-- Gen1BattleUI: the battle command and move menus, as four buttons.
--
-- Three hooks and no replaced engine function.  The battle still decides
-- everything it decided before -- what the menu means, what the cursor is on,
-- what A does with it -- and this mod changes only where those four things
-- are drawn and what they are drawn inside.
--
--   battle.bottom_ui_visible   asks the engine not to draw the bottom strip
--                              while one of the three menus is up, and only
--                              then.  Every other phase, above all
--                              "messages", is left alone, which is the whole
--                              of how dialogue takes the strip back: it is
--                              still the engine's own text box in the
--                              engine's own place, and the buttons are simply
--                              not drawn underneath it.  It is also never
--                              claimed while the bag is open on top of the
--                              menu -- that answer is inherited by every box
--                              the bag puts up, so the buttons are drawn over
--                              the engine's empty one instead.
--
--   battle.overlay             draws the buttons.  It runs last in the frame,
--                              after the palette pass and the pictures, in
--                              the same coordinates under both layouts --
--                              160x144 for CLASSIC, 304x144 for WIDE.
--
--   battle.move_grid_navigation  tells the engine the classic move menu is a
--                              grid now, so LEFT and RIGHT cross it instead
--                              of doing nothing.  The wide layout answers
--                              this for itself and never asks.
--
-- What this file does not do is swallow a LOAD-time failure.  Nothing is at
-- risk while the game boots -- a mod that cannot draw leaves vanilla battles
-- exactly as they were -- and the only question left is whether the player is
-- told.  A mod.log line goes to a file nobody opens and what is left on
-- screen is an enabled mod that changes nothing, which is indistinguishable
-- from one that was never installed and is exactly the bug report that
-- produces.  Raising instead puts the reason on the loader's boot error feed
-- and marks the row enabled-but-broken in MODS, which is where a player
-- looks.
--
-- The two sibling files are loaded rather than required because a mod cannot
-- put itself on package.path: mod:read hands back the file's source from
-- wherever the mod actually lives (an installed directory, or inside an
-- imported .zip), and load() names the chunk after that path so a syntax
-- error in grid.lua reports as grid.lua and not as a line in this file.

local function loadSibling(mod, name)
  local source, readErr = mod:read(name)
  if not source then
    error(("%s is missing (%s); reinstall the mod")
      :format(name, tostring(readErr or "unknown read error")), 0)
  end
  -- mod.path is the install directory, and it is decoration on the chunk name
  -- rather than something to concatenate blind: a host that does not hand one
  -- over would otherwise fail here, on the string, with nothing to say.
  local chunkName = "@" .. (mod.path and (mod.path .. "/") or "") .. name
  local chunk, compileErr = load(source, chunkName)
  if not chunk then
    error(("%s did not compile: %s"):format(name, tostring(compileErr)), 0)
  end
  local ok, value = pcall(chunk)
  if not ok then
    error(("%s failed to run: %s"):format(name, tostring(value)), 0)
  end
  if type(value) ~= "function" then
    error(("%s did not return a factory (got %s)"):format(name, type(value)), 0)
  end
  return value
end

return function(mod)
  mod.options:define({
    -- The panel above the move grid: the highlighted move's full name, its
    -- type and its PP.  It is where the classic layout pays back the name
    -- width that two columns inside 160 pixels costs -- THUNDERBOLT is
    -- THUNDER. in a cell and THUNDERBOLT here -- and it sits exactly where
    -- the vanilla TYPE/PP box sat, covering what that box covered.  Off gives
    -- the picture underneath it back and leaves the cells to speak for
    -- themselves.
    { key = "move_panel", type = "toggle", label = "MOVE PANEL",
      default = true },
    -- The BUTTONS, in the engine's own Plain Pixel, so a name too long for
    -- the seven glyphs a cell has prints whole instead of being cut.  Off --
    -- the default -- is the game's own font in the buttons, cut to the cell,
    -- which is what the 2x2 has always looked like.
    --
    -- Off by default because the panel above already reads the whole name,
    -- and it does that in the game's own font whenever the name fits.  The
    -- buttons are a grid to point at; the panel is the thing that answers
    -- what you are pointing at.
    --
    -- On, a grid takes the small face for all four names or none: GUST in
    -- one font beside THUNDERSHOCK in another, in the same four boxes, reads
    -- as a fault rather than a choice.
    { key = "full_names", type = "toggle", label = "FULL NAMES",
      default = false },
    -- Type colour, in the letters themselves: the move NAME on each button,
    -- and the TYPE in the panel above them.  A tile glyph is black on
    -- transparent and setColor cannot reach it, so the letters are
    -- stencilled by a shader that keeps each glyph's alpha and supplies the
    -- RGB itself -- the game's own font throughout, in a different ink.  A
    -- host with no shaders, and a type this mod has no colour for, both draw
    -- plain black.  Off is plain black everywhere.
    { key = "type_colour", type = "toggle", label = "TYPE COLOUR",
      default = true },
  })

  local makeChrome = loadSibling(mod, "chrome.lua")
  local makeGrid = loadSibling(mod, "grid.lua")

  local C = makeChrome(mod)
  if type(C) ~= "table" then
    error(("chrome.lua did not build the drawing kit (got %s)"):format(type(C)),
          0)
  end

  local Grid = makeGrid(mod, C)
  if not (type(Grid) == "table" and type(Grid.draw) == "function") then
    error("grid.lua did not build the button grid", 0)
  end

  if not (type(mod.hooks) == "table" and type(mod.hooks.wrap) == "function") then
    error("this engine has no hook bus, and the hooks are the whole mod", 0)
  end

  local function warn(fmt, ...)
    if mod.log and type(mod.log.warn) == "function" then
      mod.log:warn(fmt, ...)
    end
  end

  -- ------- the strip is ours while a menu is on it
  --
  -- next() runs FIRST and its answer is kept rather than discarded: a mod
  -- that has already hidden the battle's bottom layer means it, and the
  -- overlay reads that back before drawing over the top of it.
  --
  -- The payload is whichever state is being asked about -- the battle itself
  -- from its own drawing, or a text box above it, which inherits the battle's
  -- answer (src/battle/UIVisibility.lua).  Grid.owns says no to both a state
  -- that is not a battle and a battle that has a screen above it, so a party
  -- or bag prompt opened FROM the menu keeps its box.
  mod.hooks:wrap("battle.bottom_ui_visible", function(next, state)
    local visible = next(state)
    -- Recorded for the battle whether or not the strip is claimed, because
    -- the parked state below draws without claiming and still has to know.
    if type(state) == "table" and state.isBattle then
      Grid.rememberUpstream(state, visible)
    end
    -- Parked -- the bag open on top of the menu -- is deliberately NOT
    -- claimed.  A false here would take the bag's own boxes with it, so the
    -- engine keeps drawing its empty one and the buttons go over the top of
    -- it instead.  See Grid.parked.
    if not Grid.owns(state) then return visible end
    return false
  end)

  mod.hooks:wrap("battle.move_grid_navigation", function(next, battle)
    local upstream = next(battle)
    if Grid.gridNavigation(battle) then return true end
    return upstream
  end)

  -- Draw-only, and last.  A throw here is a frame with no menu on it rather
  -- than a crash into the boot feed, so unlike the load above it is caught:
  -- there is no version of "the battle stops" that is better than "the
  -- buttons are missing and the log says why".
  --
  -- The priority is draw order and nothing else.  Hooks sorts a chain
  -- highest-first and runs the first link outermost (src/mods/Hooks.lua), and
  -- this link calls next() BEFORE it draws -- so the highest priority is the
  -- one drawn LAST, on top of everything else on the overlay.
  --
  -- Which is the point.  Another mod draws an EXP bar under the player's HUD
  -- and drew it after this panel, so it came out as a blue line lying across
  -- the panel's own border.  Being last means the panel covers what it
  -- overlaps instead of being covered by it -- and while a move menu is up,
  -- the strip is this mod's to own.
  --
  -- It is the ONLY hook here that insists on an order.  The other two answer
  -- questions and take the rest of the chain's answer with them.
  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)
    local ok, problem = pcall(Grid.draw, battle)
    if not ok then
      warn("Gen1BattleUI could not draw the battle menu: %s", tostring(problem))
    end
  end, 5000)

  -- Published so a mod that wants to sit beside these buttons can find out
  -- where they are, and so the suite can assert against the numbers this mod
  -- draws from rather than against a screenshot.  Decorated rather than
  -- replaced: the loader hands the table over and publishes it after the
  -- entry chunk returns (src/mods/Loader.lua _loadMod), and `or {}` is only
  -- there so a host that does not is a missing export rather than a throw.
  mod.exports = mod.exports or {}
  mod.exports.geometry = Grid.geometry
  mod.exports.owns = Grid.owns
  mod.exports.parked = Grid.parked
end
