-- Gen1Dex: the nickname prompt, over the screen it interrupted.
--
-- Returns a factory: factory(mod, C, Entry) -> a table with an install(),
-- which main.lua calls once the entry screen has been registered.
--
-- ------- the white field this takes away
--
-- Catch something the dex has never held and the game shows you its entry,
-- and then asks whether you want to give it a nickname.  The second question
-- is asked over a blank white screen: AskName (engine/menus/naming_screen.asm)
-- clears the sprites and wipes the field before it prints, so the entry you
-- were reading a frame ago is gone and the POKéMON you are being asked to
-- name is not on the screen while you name it.
--
-- On the cartridge that was the only affordable answer -- the dex page and the
-- battle are two different tilemaps and the Game Boy has one of those.  There
-- is no such bill here, so the page stays up: the dialogue box and its YES/NO
-- come up OVER the entry, which is what the player thinks is happening anyway.
-- Nothing about the prompt itself moves.  The box is the engine's own box, in
-- the same place, with the same words and the same two rows in the corner; the
-- only difference is what is behind it.
--
-- ------- whatever was on the screen a frame ago
--
-- Which is two different screens, because the moment before the question is
-- two different moments.  The rule is the same one both times: the prompt
-- keeps what it interrupted.
--
-- A species the dex has never held was showing its ENTRY -- the page the
-- engine queues between the catch text and the prompt.  That page stays up.
-- It is armed by the CATCH rather than by the prompt, off pokemon.caught's
-- `isNew`, which is the same bit the engine queued the page on; and it is the
-- SAME screen instance, not a fresh one built to look like it, so a page left
-- on STATS comes back on STATS, no cry plays a second time and no sprite is
-- loaded twice.  The one thing put back is the species, because UP/DOWN on
-- the entry walks the ones you have seen and the box is about to ask after a
-- particular POKéMON by name.
--
-- Anything else was showing the BATTLE, and no dex page was ever part of it.
-- So the field stays up instead: the player's POKéMON, both status boxes, and
-- the closed ball resting where the one you just caught was standing.  That
-- ball is the whole reason this reads as a moment rather than as a menu -- the
-- GB leaves it in OAM through the caught text and only AskName's ClearSprites
-- takes it away, so keeping the field means keeping the ball with it, and
-- putting it back down when the question is answered is the ClearSprites this
-- did not do.
--
-- Conjuring a dex page for the second case was the obvious other answer and it
-- is the wrong one: a page a player was never shown is not a page being kept
-- up, and the twelfth ZUBAT does not owe anyone its Pokédex paragraph.
--
-- ------- what it costs
--
-- BattleState.askNicknameUI is engine code with no hook on it, so it is
-- reached for directly -- the second thing this mod's engine_internals
-- permission buys, after TownMap in area.lua, and it is spent the same way.
-- The method is not replaced: the original is called, the box it built is the
-- box that is returned, and the backdrop is installed as instance fields over
-- it, so the engine's own draw runs untouched underneath.  Nothing is pushed
-- on the state stack and nothing is popped off it: the battle's queue waits on
-- being the top of the stack again (BattleState:updateQueue), and a screen of
-- this mod's own left sitting under the prompt would be a screen the battle
-- waits behind forever.  A backdrop is worth a lot less than that.
--
-- The two backdrops cost different things.  The entry is DRAWN, over the white
-- field the engine has already painted -- so a page that throws leaves exactly
-- the screen the cartridge drew.  The battle is not drawn by anything here at
-- all: blankForAskName is the engine's own "wipe the field for AskName" flag
-- and this clears it, which is one boolean saying `do not wipe`.

return function(mod, C, Entry)
  local N = {}

  -- Wrapping a method stacks, and this mod's entry chunk runs again on every
  -- hot reload and every profile switch -- so the pristine one is parked on
  -- the class under a key of this mod's own, and a re-install wraps the
  -- ORIGINAL rather than the last wrap.  Exactly what area.lua does to
  -- TownMap.new, for exactly the same reason.
  local PRISTINE = "__gen1dex_pristine_askNicknameUI"

  -- The mon the dex page came up for, set by the catch and spent by the next
  -- prompt.  Held by identity rather than by species: the mon in the payload
  -- and the mon the prompt is asked about are the same table, and two
  -- VOLTORBs caught in one session are not.
  local pending

  -- ------- what the box is asked over

  -- Answers with the entry screen to draw, the string "battle" for the field
  -- the POKéMON was caught on, or nil for the white one the cartridge wiped
  -- to.  Spends `pending` either way: one catch, one page, and a prompt that
  -- takes the battle must not leave the page armed for the next one.
  function N.backdrop(game, mon)
    local caught = pending
    pending = nil
    -- read per prompt rather than once at load, so flipping the option in the
    -- manager shows up on the next POKéMON you catch
    if not C.option("nickname_backdrop", true) then return nil end
    -- no page came up for this catch, so the field it was caught on is what
    -- the question interrupted
    if caught == nil or caught ~= mon then return "battle" end

    local entry = Entry.recent and Entry.recent()
    -- The ordinary answer on a boot where some other mod won the DexEntryMenu
    -- id: the page that came up was not ours to keep up, so keep the field.
    if type(entry) ~= "table" or type(entry.draw) ~= "function" then
      return "battle"
    end
    if entry.game ~= game then return "battle" end

    -- UP/DOWN on the entry walks the species you have seen, so the page a
    -- player closes is not necessarily the page that was opened -- and the box
    -- is about to ask after this POKéMON by name.  The PAGE they left it on
    -- survives; only whose page it is is put back.
    if entry.species ~= mon.species then
      local ok, err = pcall(entry.setSpecies, entry, mon.species, false)
      if not ok then
        mod.log:warn("the nickname backdrop did not reopen on %s: %s",
                     tostring(mon.species), tostring(err))
        return "battle"
      end
    end
    return entry
  end

  -- ------- the wrap

  function N.install()
    local BattleState = require("src.battle.BattleState")
    local UIVisibility = require("src.battle.UIVisibility")

    local original = rawget(BattleState, PRISTINE) or BattleState.askNicknameUI
    if type(original) ~= "function" then
      -- an engine that asks for the nickname somewhere else entirely; the
      -- prompt is still asked, it just keeps its white field
      mod.log:warn("this build has no askNicknameUI to draw behind")
      return
    end
    rawset(BattleState, PRISTINE, original)

    BattleState.askNicknameUI = function(battle, mon, displayName)
      -- read before the original runs, because AskName's ClearSprites is what
      -- drops the resting ball and the battle backdrop wants it back
      local ball = battle and battle.lockedBall
      local box = original(battle, mon, displayName)
      local ok, entry = pcall(N.backdrop, battle and battle.game, mon)
      if not ok then
        mod.log:warn("the nickname backdrop did not build: %s", tostring(entry))
        return box
      end
      if not entry or type(box) ~= "table" then return box end

      -- The field, kept rather than wiped.  One flag: blankForAskName is the
      -- engine's own "wipe for AskName", and clearing it hands the frame back
      -- to the battle's ordinary draw -- the enemy pic is already hidden
      -- (SE_HIDE_ENEMY_MON_PIC, in the toss chain), so what comes up is the
      -- ball where the POKéMON was, which is the picture the question is
      -- about.
      if entry == "battle" then
        if not battle then return box end
        battle.blankForAskName = false
        battle.lockedBall = ball
        -- and ClearSprites, moved to where the sprites are actually finished
        -- with: the ball comes off the field when the question is answered
        -- rather than before it is asked.  TextBox calls this plainly, not as
        -- a method, so an instance field over it is the whole wrap.
        local baseChoice = box.choice
        if type(baseChoice) == "function" then
          box.choice = function(yes)
            battle.lockedBall = nil
            return baseChoice(yes)
          end
        end
        return box
      end

      -- Instance fields over the box the engine built, so its own draw runs
      -- untouched underneath -- and the YES/NO, which is a state of its own
      -- pushed above the box, still lands on top of both.
      local baseDraw = box.draw
      if type(baseDraw) ~= "function" then return box end
      local drawing = true

      box.draw = function(self)
        -- the box and the YES/NO both answer to the battle's bottom UI
        -- visibility (UIVisibility.bottomVisible); a backdrop for a prompt
        -- that is not on the screen is a dex page with nothing to explain it
        if drawing and UIVisibility.bottomVisible(self, true) then
          -- An animated sprite pack's frames were stepping a frame ago
          -- (Entry:update), and a POKéMON that stops breathing the instant
          -- the box comes up reads as the game having frozen rather than as a
          -- page held behind a question.  Stepped from the draw because a
          -- state under another one is never updated -- which is the same
          -- reason nothing ELSE about the page moves, and the reason nothing
          -- else about it should.
          if entry.crystal and love and love.timer then
            pcall(entry.stepCrystal, entry, love.timer.getDelta())
          end
          local drew, err = pcall(entry.draw, entry)
          if not drew then
            -- one bad frame, not sixty: the battle has already painted the
            -- white field under this, so dropping the backdrop lands exactly
            -- on the screen the cartridge drew
            drawing = false
            mod.log:warn("the nickname backdrop stopped drawing: %s",
                         tostring(err))
          end
          -- whatever the page left the pen set to, the box below is drawn in
          -- the caller's colour and a leaked black one paints it solid
          C.white()
        end
        return baseDraw(self)
      end

      -- The topmost state that HAS an opinion owns the colours, and neither
      -- the dialogue box nor the YES/NO has one -- so without this the page
      -- comes out wearing the battle's palette instead of the species'.  The
      -- entry's own answer, which is what it would draw with if it were still
      -- the screen: grey chrome, and the species over the sprite well.
      box.sgbPalettes = function(_, forGame)
        if not drawing then return nil end
        local zoned, zones = pcall(entry.sgbPalettes, entry, forGame)
        return zoned and zones or nil
      end

      return box
    end

    -- pokemon.caught fires while the queue is still being BUILT -- the dex
    -- page and the prompt are rows in it, and neither has run yet -- so the
    -- arming always lands before the prompt it is for.
    mod.events:on("pokemon.caught", function(ev)
      pending = (ev and ev.isNew and ev.mon) or nil
    end)
  end

  return N
end
