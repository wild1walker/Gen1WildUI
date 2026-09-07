-- Gen1BillsBox
--
-- Gen 1's storage screen is a menu of four verbs over a list of twenty
-- names.  This replaces it -- not adds to it -- with the thing the list was
-- always standing in for: the party down the left, the open box as a grid
-- on the right, and a cursor that picks a POKeMON up and puts it down.
--
-- Two decisions are worth stating up front, because they are the whole
-- brief:
--
--   * It REPLACES the screen.  `mod.content.screens:override("BoxMenu")` is
--     the id BILL'S PC pushes, so there is no second entrance to maintain
--     and no vanilla list left underneath to fall out of step with the save.
--   * It looks like the game it is in.  Four shades, the Game Boy's own
--     font, line art and the standard bordered boxes -- no type colours, no
--     widescreen layout, no card chrome.  The grid is Gen 3's idea; every
--     pixel drawing it is Gen 1's.
--
-- The slots are drawn with `PartyMenu.drawIcon`, the engine's own party-menu
-- icon path, so per-species icons, the `pokemon.icon` hook and any icon
-- replacement mod land in the box exactly as they land in the party.

-- Which game this is.  The two arms build the same screen -- the party down
-- the left, the open box as a grid on the right, a cursor that carries a
-- POKeMON -- over two entirely different storage models, so they are two
-- files rather than one with branches in it.  See gen2screen.lua's header for
-- what Gold ships and why this replaces it.
local function isGen2()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not (ok and type(GameVersion) == "table"
          and type(GameVersion.generation) == "function") then
    return false
  end
  local okCall, generation = pcall(GameVersion.generation)
  return okCall and generation == 2
end

return function(mod)
  local Strings = require("src.core.Strings")
  local gen2 = isGen2()

  mod.options:define({
    -- The cry of whichever POKeMON just landed in a slot.  On by default
    -- because the vanilla PC plays one on every withdraw and deposit; this
    -- is the same sound at the same moment, not a new one.
    { key = "placeCry", label = "PLACE CRY", type = "toggle", default = true },
    -- Hold a direction to keep moving, the way the engine's own list menus
    -- offer it (ui.list_menu keyRepeat).  Twenty slots and six party rows
    -- is a lot of single presses.
    { key = "holdMove", label = "HOLD TO MOVE", type = "toggle", default = true },
    -- Where the cursor is when the screen opens.  BOX is the storage screen
    -- doing its job; PARTY suits a player who mostly deposits.
    { key = "startPane", label = "OPEN ON", type = "choice", default = "box",
      choices = {
        { "BOX", "box" },
        { "PARTY", "party" },
      } },
    -- See "a catch that overflows says so" below.  On by default because it
    -- only ever speaks when a POKeMON went somewhere other than the box you
    -- think you are filling, which is the one time you need telling.
    { key = "fullBoxNote", label = "FULL BOX NOTE", type = "toggle",
      default = true },
    -- The open box follows a catch that overflowed.  On by default because
    -- leaving it behind means the PC keeps opening on a box with no room in
    -- it, and every later catch walks past that box again.
    { key = "switchOnFull", label = "SWITCH ON FULL", type = "toggle",
      default = true },
    -- A BOX row on the START menu.  On by default because it was asked for,
    -- and off is here because it IS a change to where storage can be reached
    -- from: the cart wanted a PC in front of you.
    { key = "startRow", label = "BOX ON START", type = "toggle",
      default = true },
  })

  local function option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  -- ------- the screen
  --
  -- Kept in its own file and compiled through the sandbox's own `load`, which
  -- is the multi-file pattern the loader supports (src/mods/Sandbox.lua's
  -- sandboxedLoad): the chunk runs in this mod's globals rather than the real
  -- _G.  A failure here logs and returns, which leaves the builtin BoxMenu in
  -- place -- a broken storage screen must never be the only storage screen.
  local file = gen2 and "gen2screen.lua" or "screen.lua"
  local source, readErr = mod:read(file)
  if not source then
    mod.log:error("%s is missing (%s); reinstall the mod", file,
      tostring(readErr or "unknown read error"))
    return
  end

  local chunk, compileErr = load(source, "@" .. mod.path .. "/" .. file)
  if not chunk then
    mod.log:error("%s did not compile: %s", file, tostring(compileErr))
    return
  end

  local okFactory, factory = pcall(chunk)
  if not okFactory or type(factory) ~= "function" then
    mod.log:error("%s must return a factory function: %s", file,
      tostring(factory))
    return
  end

  local okScreen, screen = pcall(factory, mod)
  if not okScreen or type(screen) ~= "table"
      or type(screen.new) ~= "function" then
    mod.log:error("the box screen factory failed: %s", tostring(screen))
    return
  end

  -- `override` rather than `register` so this is the only BoxMenu on the
  -- chain: a second UI mod registering the same id composes, and two storage
  -- screens over one save is the failure mode worth spending a line to
  -- avoid.  The id is the builtin's, so nothing else has to be told.
  -- Gold pushes its storage list under a different id, and pushes it for all
  -- THREE of WITHDRAW, DEPOSIT and MOVE POKeMON (src/ui/gen2/PcMenu.lua) --
  -- which is exactly what makes one screen the right answer there: the three
  -- verbs land on the grid and there is no second entrance left over.
  local id = gen2 and "Gen2BoxMenu" or "BoxMenu"
  if mod.content.screens:get(id) then
    mod.content.screens:override(id, screen)
  else
    mod.content.screens:register(id, screen)
  end

  -- ------- BILL'S PC is BILL'S BOX
  --
  -- The Pokemon Center PC's storage row reads "SOMEONE'S PC" until you meet
  -- Bill and "BILL'S PC" after (engine/menus/pokemon_pc.asm gates on
  -- EVENT_MET_BILL, and src/world/OverworldController.lua:openPC follows it),
  -- so both labels are renamed -- anchoring on one alone would silently stop
  -- working halfway through the game.
  --
  -- next() is called FIRST and the result decorated, so another mod's row on
  -- the same menu survives instead of being rebuilt over.
  local PC_ROWS = {
    ["BILL'S PC"] = "BILL'S BOX",
    ["SOMEONE'S PC"] = "SOMEONE'S BOX",
  }

  -- Gold's storage verbs are on the PC MENU rather than inside the storage
  -- screen, so replacing the screen leaves THREE doors onto the same grid --
  -- WITHDRAW, DEPOSIT and MOVE POKéMON all push Gen2BoxMenu
  -- (src/ui/gen2/PcMenu.lua).  Collapsing them into one row is the same edit
  -- the Red arm makes one level down, where the four verbs ARE the screen.
  --
  -- The row kept is `withdraw`, relabelled: its id is a builtin the cart
  -- dispatches on, so the surviving door is the cart's own call and nothing
  -- has to be taught a new one.  CHANGE BOX stays -- the grid's L and R walk
  -- one at a time and it jumps -- and so do MAIL BOX, DECORATION and SEE YA.
  local GEN2_DROP = { deposit = true, move = true }

  mod.hooks:wrap("ui.pc.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    if not gen2 then
      for _, entry in ipairs(out) do
        if type(entry) == "table" then
          local renamed = PC_ROWS[entry.label]
          if renamed then entry.label = Strings(renamed) end
        end
      end
      return out
    end
    local kept = {}
    for _, entry in ipairs(out) do
      if type(entry) ~= "table" or not GEN2_DROP[entry.id] then
        if type(entry) == "table" and entry.id == "withdraw" then
          entry.label = Strings("BOX")
        end
        kept[#kept + 1] = entry
      end
    end
    return kept
  end)

  -- ------- a BOX row on the START menu
  --
  -- The same screen the PC opens, reached without one in front of you.  It is
  -- given the onCancel every vanilla start-menu submenu is given, so B brings
  -- the START menu back rather than dropping you into the overworld -- that is
  -- RedisplayStartMenu, and `reopen` in src/ui/StartMenu.lua does it for
  -- POKeDEX, POKeMON, ITEM and the trainer card alike.
  --
  -- Placed after POKeMON, because that is what it is about; before SAVE if
  -- this game has no POKeMON row to anchor on, and at the end if it has
  -- neither.  Anchoring on the label through Strings() rather than on a
  -- position means a translated menu still puts it in the right place, and a
  -- menu another mod has rearranged still gets the row somewhere reachable.
  --
  -- next() first, so another mod's rows survive.
  local function insertBoxRow(items, row)
    -- Each anchor is looked for in both the translated and the source word:
    -- Gold hands hooks its rows before translating them, so the translated
    -- form alone stops matching there the moment a translation is installed,
    -- and BOX would fall through to the bottom of the menu instead of landing
    -- between POKéMON and SAVE.  The same string twice in English.
    local anchors = {
      { after = true, Strings("POKéMON"), Strings.source("POKéMON") },
      { after = false, Strings("SAVE"), Strings.source("SAVE") },
    }
    for _, anchor in ipairs(anchors) do
      for i, entry in ipairs(items) do
        if type(entry) == "table"
            and (entry.label == anchor[1] or entry.label == anchor[2]) then
          -- after POKeMON, before SAVE
          table.insert(items, anchor.after and i + 1 or i, row)
          return items
        end
      end
    end
    table.insert(items, row)
    return items
  end

  -- ------- and the two games put the menu back differently
  --
  -- Red's `Menu` pops itself before it runs a row's onSelect, and
  -- `StartMenu.new(game)` builds every row's onSelect itself -- so a bare
  -- push of the id is the engine's own call spelled out.
  --
  -- Gold's does neither.  `StartMenu:choose` runs onSelect and RETURNS, so
  -- the START menu is still under whatever the row opened; and
  -- `StartMenu.new(game, opts)` takes onChoose and onClose as PUSH OPTIONS,
  -- so a bare push there builds a menu whose rows open nothing and which B
  -- does not shut.  Both were learned the hard way in Gen1MenuManager, and
  -- both are answered the same way: drop the stale menu, and ask the GAME to
  -- open its own.
  local function openBox(game)
    if not gen2 then
      return mod.ui.push(game, "BoxMenu", {
        onCancel = function() mod.ui.push(game, "StartMenu") end,
      })
    end
    -- .CheckCanUsePC: the PC cannot be opened with an empty party, and the
    -- row is a door onto the PC.  This is the FIRST thing the row does on a
    -- new game, before the player has a POKeMON -- so it is the one arm of
    -- this function every playthrough runs.
    --
    -- `canUsePc` answers `false, <the cart's refusal text>`, and that second
    -- return is a STRING.  `TextBox.new(game, text, onDone, opts)` takes the
    -- text as its second argument, not an options table: handing it
    -- `{ text = why }` reached `Tokens.expand`, which calls `text:gsub`, and
    -- a table has no gsub -- so opening BOX on a new game took the whole game
    -- down rather than printing the refusal.
    local Boxes = require("src.core.gen2.Boxes")
    local usable, why = Boxes.canUsePc(game and game.save)
    if not usable then
      local TextBox = mod.ui and mod.ui.TextBox
      if TextBox and game and game.stack then
        -- The engine's own words when it has them; its wording repeated here
        -- only if a later engine stops returning any.  Never a table.
        local text = type(why) == "string" and why
          or "You'll need a\nPOK\xe9MON to call\fwith."
        game.stack:push(TextBox.new(game, text))
      end
      return
    end
    local stack = game and game.stack
    if stack and type(stack.top) == "function"
        and type(stack.pop) == "function" then
      local top = stack:top()
      if type(top) == "table" and top.screenId == "Gen2StartMenu" then
        stack:pop()
      end
    end
    mod.ui.push(game, "Gen2BoxMenu", {
      save = game and game.save,
      onClose = function()
        if stack then stack:pop() end
        if type(game.openStartMenu) == "function" then
          pcall(game.openStartMenu, game)
        end
      end,
    })
  end

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" or not option("startRow", true) then return out end
    return insertBoxRow(out, {
      label = Strings("BOX"),
      onSelect = function() openBox(game) end,
    })
  end)

  -- ------- and so are the lines the PC prints
  --
  -- Three sentences elsewhere call the storage system a PC, and a row that
  -- says BOX opening a screen that says PC is worse than not renaming it at
  -- all.  These are ROM-extracted strings (src/core/RomText.lua reads
  -- data.text by pokered label), so they are rewritten rather than replaced:
  -- one gsub of the machine's name leaves a localized import's own wording
  -- everywhere else in the line, and a translation that does not spell it
  -- "PC" is simply left alone.
  --
  -- Done on game.ready because that is the first moment data.text is the
  -- merged table the game will actually print from; the guard makes a second
  -- firing (dev hot reload) a no-op rather than a second rewrite.
  local PC_TEXT = {
    -- engine/menus/pc.asm BillsPC / the "someone's" arm before Bill
    _AccessedBillsPCText = "Accessed BILL's\nBOX.\fAccessed POKéMON\nStorage System.",
    _AccessedSomeonesPCText =
      "Accessed someone's\nBOX.\fAccessed POKéMON\nStorage System.",
    -- the caught-a-mon-with-a-full-party line (src/battle/BattleState.lua)
    _ItemUseBallText07 = "{RAM:wStringBuffer} was\ntransferred to\nBILL's BOX!",
    _ItemUseBallText08 =
      "{RAM:wStringBuffer} was\ntransferred to\nsomeone's BOX!",
  }

  local renamed = false

  local function renameStorageText(game)
    if renamed then return end
    local text = game and game.data and game.data.text
    if type(text) ~= "table" then return end
    renamed = true
    for label, english in pairs(PC_TEXT) do
      local line = text[label]
      if type(line) == "string" then
        -- the word only ever names the machine in these four lines, and
        -- "POKéMON" carries no "PC" to catch by accident
        text[label] = (line:gsub("PC", "BOX"))
      else
        -- no extracted line for this label (an older cache, or a total
        -- conversion that dropped it): romText would fall back to the
        -- engine's own "PC" wording, so supply the renamed one
        text[label] = english
      end
    end
  end

  mod.events:on("game.ready", function(payload)
    renameStorageText(payload and payload.game)
  end)

  -- ------- a catch that overflows says so
  --
  -- The overflow itself is NOT this mod's: src/pokemon/Boxes.lua's `deposit`
  -- already walks from the open box forward through all twelve and drops the
  -- POKeMON in the first one with room, wrapping, and the catch only fails
  -- ("But every BOX is full!") when all 240 places are taken.  That is a
  -- deliberate engine divergence -- the cart refused the catch outright the
  -- moment the open box was full -- and it is what a player wants.
  --
  -- What it does not do is SAY so.  The line it prints is the cart's own
  -- ("<MON> was transferred to BILL's BOX!") and the cart never needed to
  -- name a box, because on the cart the POKeMON could only ever be in the one
  -- you had open.  Here it can be in any of twelve, and nothing on screen
  -- tells you which -- so a POKeMON caught into a full box is findable only
  -- by opening the PC and walking the boxes.
  --
  -- One extra line closes that, and only in the case that needs it: the
  -- landing box is compared against the open one, so an ordinary catch into
  -- the open box stays exactly as quiet as it was.
  --
  -- The number cannot go into the transfer line itself.  That text is
  -- ROM-extracted and reached through src/core/RomText.lua, which fills its
  -- {} slots from the caller's arguments -- BattleState passes exactly one,
  -- the POKeMON's name, so a second slot makes the arity check fail and the
  -- whole line falls back to the engine's own English (saying "PC" again).
  local Boxes = require("src.pokemon.Boxes")

  local function boxHolding(save, mon)
    local boxes = save and save.boxes
    if not (boxes and mon) then return nil end
    for i = 1, Boxes.COUNT do
      for _, held in ipairs(boxes[i] or {}) do
        if held == mon then return i end
      end
    end
    return nil
  end

  -- Where a catch actually landed, when that is not where the player thinks
  -- they are filling.  Pure: `open` is the box that was full and `landed` the
  -- one with room, or nothing at all when the catch went to the open box (the
  -- ordinary case, which has nothing to report) or to no box at all.
  local function overflowTarget(save, mon)
    local landed = boxHolding(save, mon)
    if not landed then return nil end
    local open = save.currentBox or 1
    if landed == open then return nil end
    return open, landed
  end

  -- Two lines, because the battle's text box is two lines.  Which second line
  -- depends on what actually happened, so the note can never claim a switch
  -- that the option turned off.  "Now using BOX 12." is 17 glyphs and
  -- "Stored in BOX 12." 17, both inside the box's eighteen.
  local function overflowNote(open, landed, switched)
    if switched then
      return Strings("BOX %d was full!\nNow using BOX %d.", open, landed)
    end
    return Strings("BOX %d was full!\nStored in BOX %d.", open, landed)
  end

  -- ------- and the open box follows it
  --
  -- Asked for as "Gen 2 behaviour", though that is not what Gold does: there a
  -- full party AND a full current box REFUSES the throw outright
  -- (Ball_BoxIsFullMessage, "The POKéMON BOX is full. That can't be used
  -- now."), and Bill rings you when a box fills.  Advancing to the next box
  -- with room is Gen 3's answer.  Either way it is the right one here, because
  -- this engine already refuses to lose the catch: without the switch the open
  -- box stays the full one, so every later catch overflows again and the PC
  -- keeps opening on a box with no room in it.
  --
  -- Moving currentBox also aims the NEXT overflow: Boxes.deposit starts its
  -- walk from the open box, so pointing it at the box that just took one
  -- means the next catch lands there directly instead of walking past the full
  -- one again.
  --
  -- The vanilla PC saved the game when it changed box, because the cart was
  -- swapping an SRAM bank.  This does not, for the same reason the box screen
  -- does not: all twelve boxes are one save file here.
  --
  -- BattleState:sayNext inserts at the queue's `nextInsert`, which the
  -- transfer message has just advanced, so the note lands immediately after it
  -- rather than at the end of the battle's remaining chatter.  The event fires
  -- on the line after the deposit (src/battle/BattleState.lua), which is why
  -- the POKeMON is already in a box to be found by the time we look.
  mod.events:on("pokemon.caught", function(payload)
    if type(payload) ~= "table" or payload.destination ~= "box" then return end
    local battle, game = payload.battle, payload.game
    local save = game and game.save
    if type(save) ~= "table" then return end

    local open, landed = overflowTarget(save, payload.mon)
    if not open then return end

    local switched = option("switchOnFull", true) and true or false
    if switched then save.currentBox = landed end

    if not option("fullBoxNote", true) then return end
    if type(battle) ~= "table" or type(battle.sayNext) ~= "function" then return end
    battle:sayNext(overflowNote(open, landed, switched))
  end)

  -- The per-mon popup's extension point: another mod hands it rows for a
  -- POKeMON and this screen puts them between its own verbs and CANCEL.
  -- Published whether or not anything registers, because provide() is how a
  -- mod adds a row and a caller that finds nothing to register with has no
  -- way to tell "absent" from "broken".
  --
  --   local box = mod.find("Gen1BillsBox")
  --   if box and box.exports.actions then
  --     box.exports.actions.provide(function(game, mon, pane)
  --       return { { label = "REMEMBER", onSelect = function() ... end } }
  --     end, mod.id)
  --   end
  if type(screen.actions) == "table" then
    mod.exports.actions = {
      provide = screen.actions.provide,
      rows = screen.actions.rows,
    }
  end

  -- exported so the suite can drive the rename without a booted game, and so
  -- a companion mod can ask whether the rename has run yet
  mod.exports.renameStorageText = renameStorageText
  mod.exports.pcRowLabels = PC_ROWS
  mod.exports.overflowTarget = overflowTarget
  mod.exports.overflowNote = overflowNote
  mod.exports.boxHolding = boxHolding

  mod.log:info("BILL'S PC is a box")
end
