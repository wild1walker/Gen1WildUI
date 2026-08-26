-- Gen1BattleUI: the level-up stat box, over the line that announced it.
--
-- What the player sees without this is two screens where the ROM has one.
-- "IVYSAUR grew to level 28!" types out, waits for A, and is CLEARED; then
-- the ATTACK/DEFENSE/SPEED/SPECIAL box comes up over an empty text box, and
-- has to be dismissed as well.  The stats arrive with nothing left on screen
-- saying what they are the stats of.
--
-- pokered prints one screen and holds it once.  GrewLevelText
-- (engine/battle/experience.asm:369-372) is `text_far` + `sound_level_up` +
-- `text_end` -- text_end, not `prompt`, so NextTextCommand returns straight
-- out of PrintText without ever blinking the arrow or running
-- ManualTextScroll (home/text.asm:328-334).  PrintStatsBox then draws its
-- window into the screen the line is STILL on, and the button press that
-- follows dismisses the pair together.  The line is the caption; the box is
-- the picture.
--
-- The engine queues that as a prompt row followed by a UI row -- two waits
-- and a cleared box between them (src/battle/BattleState.lua:4454-4459).
-- This file puts the pair back together, and does it by re-marking the two
-- rows the engine has already queued rather than by queueing anything of its
-- own:
--
--   the line becomes an `auto` row.  That is the engine's own name for a
--   page whose ROM tail is text_end -- the used-move line and the item-use
--   line are both of that kind -- and its path sets msgHold, which is
--   exactly "the typed page stays drawn behind whatever runs next"
--   (BattleState:updateQueue:1541-1556, drawTextArea:6437).  So the box goes
--   up over a text box with the level-up line still in it, and one A takes
--   both away.
--
--   the jingle moves onto the stat box's own factory, because the auto path
--   never asks a row for its sound.  It sounds once, as the box opens, which
--   is the beat the ROM's own sound_level_up lands on.
--
-- The sound loses WaitForSoundToFinish and does not need it: a ui row parks
-- the queue on waitingUI until the box is popped (updateQueue:1303-1305), so
-- the jingle has the same clear window to itself that the wait was there to
-- give it.  Which is the whole reason nothing is INSERTED here.  The queue's
-- own inserts are relative -- sayNext and friends count positions from
-- nextInsert -- and the exp award is not the last thing a faint queues: the
-- trainer's "sent out X!" is inserted by the same fn, afterwards, by
-- position (BattleState:enemyMonFainted:4625).  A row added in the middle of
-- the exp rows would slide that line into the middle of them too.  Two rows
-- re-marked in place move nothing.
--
-- ------- which two rows
--
-- Structure alone does not name them.  A level-up line is a message row
-- carrying a sound, followed by a UI row -- and so is "X learned SPLASH!"
-- when the mon it was queued for has no free slot and the forget menu comes
-- up behind it.  So the rows are named by their TEXT, from the levels
-- battle.exp_gained has just announced, built through the same Strings call
-- the engine builds them with: same catalogue, same arguments, same string
-- in any language.  A wording change upstream is then a level-up that keeps
-- the engine's two screens rather than a "learned" line that loses its
-- prompt, and the suite says which one happened.

return function(mod, C)
  local Strings = require("src.core.Strings")

  local LevelUp = {}

  -- The lines battle.exp_gained has announced but the queue has not been
  -- read for yet, per battle and weak-keyed: an award that never reaches the
  -- hook (another mod's link answering the whole thing itself) should not
  -- hold a finished battle alive on the strength of it.
  local wanted = setmetatable({}, { __mode = "k" })

  local function enabled()
    return C.option("levelup_box", true) ~= false
  end

  -- The name awardExp puts in the line: the nickname, or the species name
  -- from the battle's own dataset (BattleState.lua:4426).
  local function nameOf(battle, mon)
    if type(mon) ~= "table" then return nil end
    if mon.nickname then return mon.nickname end
    local pokemon = battle.data and battle.data.pokemon
    local def = pokemon and mon.species and pokemon[mon.species]
    return def and def.name or nil
  end

  -- battle.exp_gained, which fires per mon with the levels it has just
  -- gained -- and fires BEFORE the rows for them are queued, which is why
  -- this only records and the reading is done from the award hook.
  function LevelUp.expect(payload)
    if not enabled() then return end
    if type(payload) ~= "table" then return end
    local battle, mon, levels = payload.battle, payload.mon, payload.levels
    if type(battle) ~= "table" or type(levels) ~= "table" then return end
    local name = nameOf(battle, mon)
    if not name then return end
    if #levels == 0 then return end
    local lines = wanted[battle]
    if not lines then
      lines = {}
      wanted[battle] = lines
    end
    for _, level in ipairs(levels) do
      -- counted rather than flagged: two mons of the same name reaching the
      -- same level in one award is two rows, not one
      local line = Strings("%s grew\nto level %d!", name, level)
      lines[line] = (lines[line] or 0) + 1
    end
  end

  local function isLine(row)
    return type(row) == "table" and type(row.text) == "string"
       and not row.auto and not row.choice
  end

  local function isBox(row)
    return type(row) == "table" and type(row.ui) == "function"
  end

  local function holdLineUnder(line, box)
    -- the text_end row kind: no arrow, no wait, and the typed page left on
    -- screen under whatever runs next
    line.auto = true
    line.autoDelay = 0
    local jingle = line.waitForLearningSfx
    line.waitForLearningSfx = nil
    if not jingle then return end
    -- the auto path never asks for the row's sound, so the box takes it: a
    -- throw from another mod's sound is a silent level-up, not a battle that
    -- stops opening stat boxes
    local open = box.ui
    box.ui = function()
      pcall(jingle)
      return open()
    end
  end

  -- Read the queue the award has just built and re-mark every level-up line
  -- against the stat box it belongs to.  Returns how many pairs were joined,
  -- for the suite.
  function LevelUp.retime(battle)
    if type(battle) ~= "table" then return 0 end
    local lines = wanted[battle]
    wanted[battle] = nil
    if not lines or not enabled() then return 0 end
    local queue = battle.queue
    if type(queue) ~= "table" then return 0 end
    local joined = 0
    for i = 1, #queue - 1 do
      local line, box = queue[i], queue[i + 1]
      if isLine(line) and (lines[line.text] or 0) > 0 and isBox(box) then
        lines[line.text] = lines[line.text] - 1
        holdLineUnder(line, box)
        joined = joined + 1
      end
    end
    return joined
  end

  return LevelUp
end
