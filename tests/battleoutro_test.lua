-- Headless coverage of BLACK OUTRO's wrap of BattleState:finish
-- (modules/WidescreenBattleIntro/main.lua).
--
-- finish() is not one call.  The engine re-enters it: the PAY DAY pickup
-- queues its line and comes back, and EvolveAfterBattle hands the battle
-- screen to Evolution.checkParty and RETURNS, coming back once the
-- evolutions have played (src/battle/BattleState.lua, engine/battle/
-- end_of_battle.asm:42-45).  Only the last of those calls is the ending.
--
-- Fading on an earlier one is not a cosmetic mistake.  The fade runs the
-- engine finish at its midpoint, at full black, and then -- finding the
-- battle still on the stack, because that call did not leave -- pops what
-- is on top and drives the exit again.  What was on top was the evolution.
-- So the whole evolution happened behind the black and was then thrown
-- away: with the bundle installed, nothing ever evolved, and there was
-- nothing on screen to say so.  That is the bug this file exists for.
--
-- The engine is not here, so the two shapes that decide it are stood up
-- from the engine's own source: finish()'s evolution branch and
-- Evolution.checkParty's "push a screen, call back when it closes".
--
-- Run:  luajit tests/battleoutro_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  local same = actual == expected
  if not same then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

-- ---------------------------------------------------------------- harness

local MODULE = "modules/WidescreenBattleIntro/main.lua"

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

local function strings(text, ...)
  if select("#", ...) > 0 then return (tostring(text):format(...)) end
  return text
end

love = { graphics = {} }

-- The engine seams the module reaches for at load time.  Renderer.endFrame
-- is wrapped by the install and never called here; Game is the options
-- store the two toggles ride.
local Game = { stack = nil, mods = { modOptions = {} } }

-- The engine's own post-battle hold, which the outro borrows for its own:
-- home/overworld.asm:351-352 spends `ld c, 10 / DelayFrames` before
-- GBFadeInFromWhite starts stepping.
package.preload["src.core.Timing"] = function()
  return { POST_BATTLE_RETURN = 10 }
end
package.preload["src.core.Strings"] = function() return strings end
package.preload["src.render.Renderer"] = function()
  return { endFrame = function() end }
end
package.preload["src.core.Game"] = function() return Game end

-- The engine's state stack, as much of it as a fade needs: push/pop/top
-- and the `states` array BattleOutro:onStack walks.
local function newStack()
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state; return state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end

-- ------- the engine's BattleState:finish, in the shape the wrap sees
--
-- Copied from src/battle/BattleState.lua rather than approximated, because
-- the re-entry IS the thing under test: the evolution branch flips
-- evolutionsChecked, hands off, and returns without the battle leaving;
-- everything after it is the real exit.
local BattleState = {}
BattleState.__index = BattleState

-- Evolution.checkParty: the mons in `leveledUp` that have somewhere to
-- evolve to get a screen each, and the caller's onDone runs when the last
-- one closes.  A party with nothing pending calls back immediately --
-- which is how a battle that levelled somebody but evolved nobody still
-- reaches its ending on the same tick.
local function checkParty(game, onDone, leveledUp)
  local pending = {}
  for _, mon in ipairs(game.save.party) do
    if leveledUp and leveledUp[mon] and mon.evolvesTo then
      pending[#pending + 1] = mon
    end
  end
  local i = 0
  local function nextOne()
    i = i + 1
    local mon = pending[i]
    if not mon then
      if onDone then onDone() end
      return
    end
    -- the evolution screen: it owns the top of the stack until closed
    game.stack:push({
      evolution = mon,
      close = function(self)
        game.stack:pop()
        mon.species = mon.evolvesTo
        nextOne()
      end,
      update = function() end,
      draw = function() end,
    })
  end
  nextOne()
  return #pending
end

function BattleState:finish()
  if not self.evolutionsChecked then
    self.evolutionsChecked = true
    checkParty(self.game, function() self:finish() end, self.leveledUp)
    return
  end
  -- the real exit: the battle leaves and the engine's white return takes
  -- the screen (BattleState:finish -> battleReturn)
  self.game.stack:pop()
  self.closed = (self.closed or 0) + 1
  self.game.stack:push({ engineReturn = true, onDone = function()
    self.handedBack = true
  end, update = function() end, draw = function() end })
end

package.preload["src.battle.BattleState"] = function() return BattleState end

-- ------- install

local install = chunkOf(MODULE)
local mod = {
  id = "widescreen_battle_intro",
  exports = {},
  hooks = { wrap = function() end },
}
install(mod)

local exports = mod.exports
ok(type(exports.outroWanted) == "function", "the module exports outroWanted")

local function newBattle(game, opts)
  opts = opts or {}
  local battle = setmetatable({
    game = game, result = opts.result or "win",
    leveledUp = opts.leveledUp, payDay = opts.payDay,
  }, BattleState)
  return battle
end

local function newGame(party)
  local stack = newStack()
  local game = { stack = stack, save = { party = party or {} } }
  Game.stack = stack
  return game
end

local function isFade(state)
  return type(state) == "table" and state.onMidpoint ~= nil and state.phase ~= nil
end

-- ------- outroWanted: which call is the ending

do
  local game = newGame()
  local mon = { species = "A" }
  game.save.party = { mon }

  eq(exports.outroWanted(newBattle(game)), true,
     "a plain win is the ending, so it fades")
  eq(exports.outroWanted(newBattle(game, { result = "lose" })), false,
     "a loss takes the blackout warp, not the fade")
  eq(exports.outroWanted(newBattle(game, { payDay = 100 })), false,
     "the PAY DAY pickup is a false start")

  local levelled = newBattle(game, { leveledUp = { [mon] = true } })
  eq(exports.outroWanted(levelled), false,
     "the call that hands off to the evolutions is a false start too")
  levelled.evolutionsChecked = true
  eq(exports.outroWanted(levelled), true,
     "the call that comes back from them is the ending")

  eq(exports.outroWanted(newBattle(game, { leveledUp = {} })), true,
     "an award that levelled nobody has no hand-off to wait for")
end

-- ------- the regression: an evolution is not run behind the black

do
  local mon = { species = "FIXMON_A", evolvesTo = "FIXMON_B" }
  local game = newGame({ mon })
  local battle = newBattle(game, { leveledUp = { [mon] = true } })
  game.stack:push(battle)

  battle:finish()

  local top = game.stack:top()
  ok(not isFade(top), "the first finish does not push the fade")
  ok(type(top) == "table" and top.evolution == mon,
     "the evolution has the screen, on the battle, in the light")
  eq(#game.stack.states, 2, "the battle is still up under it")
  eq(battle.closed, nil, "and the battle has not closed behind it")

  -- the player watches it and it closes: finish comes back, for real
  if type(top) == "table" and top.close then top:close() end
  eq(mon.species, "FIXMON_B", "the mon actually evolved")

  local fade = game.stack:top()
  ok(isFade(fade), "the fade owns the ending it was always meant to own")
  eq(#game.stack.states, 2, "and the battle is under it, still drawing")

  -- run the fade out; at the cut it pops itself and closes the battle
  for _ = 1, 200 do
    if not isFade(fade) or game.stack:top() ~= fade then break end
    fade:update()
  end
  eq(battle.closed, 1, "the battle closes once, at full black")
  eq(fade.phase, "in", "and the fade turns round to bring the map up")

  for _ = 1, 200 do
    if battle.handedBack or not isFade(fade) then break end
    if game.stack:top() == fade then fade:update() else break end
  end
  ok(battle.handedBack, "the fade hands the map back the way the engine would")
end

-- ------- a battle that levelled somebody but evolved nobody still fades

do
  local mon = { species = "FIXMON_C" } -- no evolvesTo
  local game = newGame({ mon })
  local battle = newBattle(game, { leveledUp = { [mon] = true } })
  game.stack:push(battle)

  battle:finish()

  ok(isFade(game.stack:top()),
     "checkParty calls straight back, and that call fades")
  eq(battle.closed, nil, "the fade still owns the close")
end

-- ------- a battle with no level-ups is untouched

do
  local game = newGame()
  local battle = newBattle(game)
  game.stack:push(battle)

  battle:finish()

  ok(isFade(game.stack:top()), "the ordinary win fades on its only call")
end


-- ------- the hold at the cut

do
  io.write("the black holds at the cut instead of turning round on it\n")

  local outroAlpha = exports.outroAlpha
  eq(outroAlpha("out", 0, 36), 0, "the battle's last live frame is not veiled")
  eq(outroAlpha("out", 18, 36), 0.5, "half way down is half black")
  eq(outroAlpha("hold", 0, 10), 1, "the hold is full black from its first frame")
  eq(outroAlpha("hold", 9, 10), 1, "...to its last")
  eq(outroAlpha("in", 0, 36), 1, "the fade in starts where the hold left off")
  eq(outroAlpha("in", 36, 36), 0, "and ends on the map")

  -- The whole shape, driven through the state the way the game drives it.
  -- What matters is not the length: it is that the fade is at FULL BLACK for
  -- more than one frame, because one frame is an instant rather than a
  -- window, and the instant it used to offer was the cut -- the frame that
  -- pops the fade, runs the engine's finish and pushes it back.  Autosave
  -- looks for exactly this and used to find only that frame.
  local game = newGame({})
  local battle = newBattle(game, {})
  game.stack:push(battle)
  battle:finish()

  local fade = game.stack:top()
  ok(isFade(fade), "the fade is up")

  local blackFrames, cutFrame = 0, nil
  for i = 1, 400 do
    if game.stack:top() ~= fade then break end
    fade:update()
    if fade:alpha() >= 1 then
      blackFrames = blackFrames + 1
      cutFrame = cutFrame or i
    end
    if fade.phase == "in" and fade.t > 0 then break end
  end

  ok(blackFrames > 1,
     "full black lasts longer than the single frame it used to")
  -- Eleven, not ten: the hold is ten frames and the CUT is the frame that
  -- opens it -- the fade flips to "hold" on the same update that pops itself,
  -- runs the engine's finish and pushes itself back, so that frame is already
  -- at full black.  Ten is the engine's own pause before its white fade in
  -- (home/overworld.asm:351-352); the eleventh is the work the pause is for.
  eq(blackFrames, 11,
     "the engine's ten-frame pause, plus the cut that opens it")
  eq(battle.closed, 1, "the battle still closes exactly once, at the cut")
end

io.write(("battle outro: %d passed, %d failed\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
