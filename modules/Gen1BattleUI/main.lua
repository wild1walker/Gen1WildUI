-- Gen1BattleUI: the battle command and move menus, as four buttons.
--
-- Five links and no replaced engine function.  The battle still decides
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
--   battle.exp_award           and the battle.exp_gained event with it: the
--                              level-up line and the stat box that follows
--                              it are queued as two screens, so the box
--                              arrives over a text box the engine has just
--                              emptied.  The award is still the engine's --
--                              next() runs it -- and two of the rows it
--                              queued come back re-marked as the one screen
--                              pokered prints.  See levelup.lua.
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
    -- The XP bar under the player's Pokemon: Gen 2 has one in its own HUD and
    -- Gen 1 does not.  It was Gen1WildQOL's until this release; it is here
    -- because it is a battle UI feature and this is the battle UI mod, and
    -- because over there it could not be stopped from drawing across the move
    -- panel.  See xpbar.lua.  On, which is what it was over there.
    { key = "xp_bar", type = "toggle", label = "XP BAR",
      default = true },
    -- The level-up stat box, over the line that announced it.  pokered
    -- prints "X grew to level N!" with a text_end tail and draws
    -- PrintStatsBox into the screen that line is still on, so the stats and
    -- the sentence they belong to are one screen dismissed once; the engine
    -- queues them as two, with the line cleared before the box arrives and
    -- the text box under it left empty.  On puts them back together.  Off is
    -- the engine's own two screens.  See levelup.lua.
    { key = "levelup_box", type = "toggle", label = "LEVEL-UP BOX",
      default = true },
  })

  local makeChrome = loadSibling(mod, "chrome.lua")
  local makeGrid = loadSibling(mod, "grid.lua")
  local makeXP = loadSibling(mod, "xpbar.lua")
  local makeLevelUp = loadSibling(mod, "levelup.lua")

  local C = makeChrome(mod)
  if type(C) ~= "table" then
    error(("chrome.lua did not build the drawing kit (got %s)"):format(type(C)),
          0)
  end

  local Grid = makeGrid(mod, C)
  if not (type(Grid) == "table" and type(Grid.draw) == "function") then
    error("grid.lua did not build the button grid", 0)
  end

  local XP = makeXP(mod, C)
  if not (type(XP) == "table" and type(XP.draw) == "function") then
    error("xpbar.lua did not build the XP bar", 0)
  end

  local LevelUp = makeLevelUp(mod, C)
  if not (type(LevelUp) == "table" and type(LevelUp.retime) == "function") then
    error("levelup.lua did not build the level-up retiming", 0)
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
  --
  -- The XP bar goes down FIRST and the grid second, and that order is the
  -- whole of how the bar stops lying across the move panel.  While it lived
  -- in another mod it was drawn by a wrapper around battle.draw, which runs
  -- after every link on this hook however high a priority they carry, so it
  -- could only clip itself -- to x=88, the vanilla panel's edge, while this
  -- mod's panel ends at 112.  Two files in one function have nothing to
  -- negotiate: the panel covers the bar because it is drawn after it, and a
  -- panel that changes width takes the covering with it.
  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)
    local okBar, barProblem = pcall(XP.draw, battle)
    if not okBar then
      warn("Gen1BattleUI could not draw the XP bar: %s", tostring(barProblem))
    end
    local ok, problem = pcall(Grid.draw, battle)
    if not ok then
      warn("Gen1BattleUI could not draw the battle menu: %s", tostring(problem))
    end
  end, 5000)

  -- ------- the level-up line and its stat box are one screen
  --
  -- Draw order cannot fix this one: the empty text box under the stat box is
  -- empty because the line was CLEARED before the box was pushed, two queue
  -- rows earlier, and nothing this mod draws afterwards can put a message
  -- back that the engine no longer has.  The join has to happen where the
  -- rows are made, which is the exp award.
  --
  -- Two links, because the two halves of the answer arrive apart.
  -- battle.exp_gained fires per mon with the levels it gained and fires
  -- BEFORE the rows for them are queued, so it can only be recorded; the
  -- award hook wraps the whole thing, so by the time next() has returned the
  -- rows really are there to be read.  Neither replaces anything: the award
  -- is the engine's own, run by next(), and what comes back is what a queue
  -- with no mod on it would have held, with two of its rows re-marked.  See
  -- levelup.lua.
  if type(mod.events) == "table" and type(mod.events.on) == "function" then
    mod.events:on("battle.exp_gained", function(payload)
      LevelUp.expect(payload)
    end)
  else
    warn("Gen1BattleUI has no event bus to hear level-ups on; the stat box "
         .. "keeps the engine's timing")
  end

  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    local result = next(ctx)
    -- After the award, never instead of it: a throw here is a level-up with
    -- the engine's own two screens, not an award that never happened.
    local ok, problem = pcall(LevelUp.retime,
                              type(ctx) == "table" and ctx.battle or nil)
    if not ok then
      warn("Gen1BattleUI could not join the level-up line to its stat box: %s",
           tostring(problem))
    end
    return result
  end)

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
  -- The one export that exists for another mod rather than for the suite.
  -- battle.overlay is the last hook INSIDE BattleState:draw, so a mod that
  -- wraps battle.draw itself draws after every link on it however high the
  -- priority -- which is why the EXP bar sat on this panel through a whole
  -- release that thought priority had settled it.  A neighbour in that
  -- position cannot be out-drawn, only told, so this says where the panel is
  -- and lets it clip.
  mod.exports.panelRect = Grid.panelRect
  mod.exports.expPixels = XP.pixels
end
