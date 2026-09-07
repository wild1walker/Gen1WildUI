-- Gen1Dex on Gold, Silver and Crystal: the entry for a POKeMON you have never
-- met, opened, and masked.
--
-- Returns a factory: factory(mod, DexData) -> { install, UNSEEN, maskEntry },
-- which main.lua builds on Gold after the extra pages and the AREA caption.
--
-- ------- what it does
--
-- `Pokedex_UpdateMainScreen`'s .a returns unless the mon has been seen, so on
-- the cartridge an undiscovered row is a dead press: five dashes and no way in.
-- That is exactly backwards on the screen a player opens to find out where
-- something LIVES -- which is what Red's AREA ON UNSEEN row has said since
-- 0.20, and Gold's dex has more to give than Red's did, because on Gold AREA is
-- an action ON the entry rather than a screen of its own.  So A opens the
-- entry, and AREA off that entry opens the nest map, and every nest on it
-- blinks the way it would for a POKeMON you had already met.
--
-- ------- and what it takes away on the way in
--
-- Everything that would name it.  The rule is the one Red's screen has always
-- had: the shape of the answer, never the identity.
--
--   the pic       already the question mark -- `drawPic` sends an unseen row
--                 to `questionMark()` whatever the caller asked for, so this
--                 file does not touch it and the ? stays
--   the name      the cart's own five dashes, the same token its LIST prints
--                 for the same row
--   the KIND      likewise -- "SEED POKeMON" is half a name
--   the footprint a silhouette is a portrait; not drawn
--   the CRY       silenced.  A cry is the loudest name a POKeMON has, and the
--                 cart plays it twice: once on opening the entry and once on
--                 the CRY action.  Both are dropped rather than substituted,
--                 because a wrong cry is a lie and a right one is the spoiler.
--   PRNT          stood down.  It prints "Printed X's data!" with the name
--                 read straight off the species table rather than through
--                 `monName`, so masking the screen would not have masked it.
--   HT / WT       already `?'??"` and `???lb` -- `drawEntryBody` returns early
--                 for anything not CAUGHT, so an unseen row was masked here
--                 before this file existed
--   the text      same early return
--   STATS,        this suite's own three pages, and the worst spoiler of the
--   EVOLVES,      set: base stats, what it becomes and every move it learns.
--   MOVES         Gated in gen2.lua rather than here, at `pageKind`, so PAGE
--                 goes back to being the cart's own two-page toggle.
--
-- What is left is the number, the empty frame, and AREA -- which is the whole
-- point of opening it.
--
-- ------- how the masking is done
--
-- By shadowing four methods ON THE INSTANCE for the duration of one call, and
-- putting back exactly what was there.  The screen's metatable indexes the
-- class, so an instance field shadows the class method and a nil puts the
-- class method back -- no globals, no second copy of the cart's draw, and
-- nothing left behind if the call throws.
--
-- The alternative was to re-implement `drawEntryBody` with the names left out,
-- which is a second copy of a screen that is not ours, drifting from the one
-- the cart actually ships.  Wrapping the four questions it asks is smaller and
-- cannot drift: a page the cart adds later is masked by the same four answers.

return function(mod, DexData)
  local self = {}

  -- The cart's own token for a row it will not name -- `PokedexMenu:drawList`
  -- prints exactly this for an unseen entry:
  --
  --     self:text("-----", 1, ty)
  --
  -- so the entry and the list say the same thing, and the player who saw five
  -- dashes in the list and pressed A finds the same five dashes rather than a
  -- second spelling of the same silence.  Red uses "?????" for the same job,
  -- which is Red's own list token; each cartridge keeps its own.
  self.UNSEEN = "-----"

  -- A copy of the dex entry with everything that names it taken out.  Kept
  -- separate from the shims below because it is the one piece of the mask
  -- that travels as data rather than as a method: `drawEntryBody` is handed
  -- its entry, so this is where `kind` and the description are answered.
  function self.maskEntry(entry)
    local out = {}
    for key, value in pairs(type(entry) == "table" and entry or {}) do
      out[key] = value
    end
    out.kind = self.UNSEEN
    -- Belt and braces: the cart returns before the description for anything
    -- not CAUGHT, and an unseen row cannot be caught -- but the two facts are
    -- checked in different places, and this file should not be the one that
    -- assumes they stay in step.
    out.text, out.text2 = nil, nil
    return out
  end

  local MARK = "__gen1DexGen2Unseen"

  function self.install()
    local okDex, PokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
    if not (okDex and type(PokedexMenu) == "table") then
      mod.log:warn("no src.ui.gen2.PokedexMenu; AREA ON UNSEEN stands down")
      return false
    end
    if rawget(PokedexMenu, MARK) then return true end

    local baseUpdate = PokedexMenu.update
    local baseEntry = PokedexMenu.drawEntryBody
    local baseArea = PokedexMenu.drawArea
    if type(baseUpdate) ~= "function" or type(baseEntry) ~= "function"
        or type(baseArea) ~= "function" then
      mod.log:warn("src.ui.gen2.PokedexMenu has no update/drawEntryBody/"
        .. "drawArea; AREA ON UNSEEN stands down")
      return false
    end

    -- Asked every time rather than captured, so turning the row off is the
    -- cart's dead press back with no relaunch.
    local function enabled()
      return mod.options:get("area_unseen") ~= false
    end

    local function unseenRow(screen)
      if not enabled() then return nil end
      local row = type(screen.current) == "function" and screen:current() or nil
      if row and not row.seen then return row end
      return nil
    end

    -- The four questions the entry and the AREA page ask about a species,
    -- answered without naming it, for exactly one call.  `rawget` is what puts
    -- back: the instance normally carries none of these, so restoring nil is
    -- restoring the class method, and restoring a value is restoring whatever
    -- another mod had already put there.
    local FIELDS = { "monName", "drawFootprint", "playCry", "printEntry" }

    local function masked(screen, fn)
      local saved = {}
      for _, key in ipairs(FIELDS) do saved[key] = rawget(screen, key) end
      screen.monName = function() return self.UNSEEN end
      screen.drawFootprint = function() end
      screen.playCry = function() end
      screen.printEntry = function() end
      local ok, result = pcall(fn)
      for _, key in ipairs(FIELDS) do screen[key] = saved[key] end
      if not ok then error(result, 0) end
      return result
    end

    -- Reported once and then stood down from, the way the theme is: this runs
    -- on every frame of the entry, and a broken mask must cost the feature
    -- rather than show the name it was installed to hide.
    --
    -- Standing down FAILS CLOSED, which is not the same shape as the other
    -- arms in this suite.  Everywhere else the answer to a broken feature is
    -- the cartridge's own screen -- but here the cartridge's own screen is a
    -- name, a kind, a footprint and a cry for a POKeMON the player has never
    -- met, reached through a press the cartridge does not allow.  Handing that
    -- back would turn a broken feature into the exact leak it exists to
    -- prevent.  So a screen that stops masking stops OPENING (the press arm),
    -- stops DRAWING (the two draw arms draw nothing at all), and the one the
    -- player is standing in is sent back to the listing on the same frame it
    -- broke.  What is on screen after that is the dex, minus a feature.
    local broken = false
    local function stoodDown(screen, problem)
      broken = true
      if screen and screen.view ~= "list" then screen.view = "list" end
      mod.log:warn("AREA ON UNSEEN stood down for this session: %s",
                   tostring(problem))
    end

    PokedexMenu.update = function(screen, dt)
      -- The press the cartridge throws away.  Taken before the cart sees it,
      -- because the cart's own list arm reads A and returns having done
      -- nothing -- there is no "it did not handle it" to fall through from.
      --
      -- No cry on the way in.  Gold cries the species as it opens the entry
      -- (Pokedex_InitDexEntryScreen's tail), and a player who has never met
      -- this POKeMON has now heard it.
      if screen.view == "list" then
        local input = screen.game and screen.game.input
        local row = (not broken) and input and unseenRow(screen)
        if row then
          local pressed = input.wasPressed and input:wasPressed("a")
          if pressed then
            screen.view = "entry"
            screen.page = 1
            screen.entryAction = 1
            return
          end
        end
        return baseUpdate(screen, dt)
      end

      if not unseenRow(screen) then return baseUpdate(screen, dt) end
      -- Already stood down, and the player is still inside an entry that was
      -- opened before it broke: out, rather than one more frame of it.
      if broken then
        screen.view = "list"
        return
      end
      local ok, result = pcall(masked, screen, function()
        return baseUpdate(screen, dt)
      end)
      if not ok then
        stoodDown(screen, result)
        return
      end
      return result
    end

    PokedexMenu.drawEntryBody = function(screen, row, entry)
      if not (enabled() and row and not row.seen) then
        return baseEntry(screen, row, entry)
      end
      -- Nothing, rather than the name: see `stoodDown`.  The frame, the number
      -- and the question mark are the cart's and are already on the screen.
      if broken then return end
      local ok, result = pcall(masked, screen, function()
        return baseEntry(screen, row, self.maskEntry(entry))
      end)
      if not ok then
        stoodDown(screen, result)
        return
      end
      return result
    end

    PokedexMenu.drawArea = function(screen, ...)
      if not unseenRow(screen) then return baseArea(screen, ...) end
      if broken then return end
      local ok, result = pcall(masked, screen, function()
        return baseArea(screen)
      end)
      if not ok then
        stoodDown(screen, result)
        return
      end
      return result
    end

    PokedexMenu[MARK] = true
    mod.log:info("an undiscovered entry opens on Gold, masked, with its nests")
    return true
  end

  return self
end
