-- Gen1Party on Gold: MOVE carries a POKeMON through the list, the way Red's
-- does, instead of swapping two of them.
--
-- Returns a factory: factory(mod) -> { install, step }.  Gated on the same
-- `live_move` row Red uses -- MOVE NOT SWITCH -- because it is the same
-- behaviour and the row now means the same thing on both cartridges.
--
-- ------- what the cart does, and what it is not
--
-- Gold has a move already.  `beginSwitch` parks a '▷' on the held row,
-- `updateSwitch` walks the cursor with UP and DOWN, and A runs `finishSwitch`,
-- which is `_SwitchPartyMons`: the two structs TRADE PLACES.
--
--     party[from], party[to] = party[to], party[from]
--
-- That is an EXCHANGE, and the difference from Red's shows the moment you move
-- more than one row.  Carrying the fourth member to the top should leave the
-- three it passed in the order they were already in; a swap trades the first
-- and the fourth and leaves the two between them where they were.
--
-- Reported as: "moving the Pokemon through the party in party menu still
-- doesn't make them flash and see the list live update".  Both halves are the
-- same missing thing -- the mon does not travel, so there is nothing to watch
-- and nothing to flash.
--
-- ------- what this makes it do
--
-- UP and DOWN carry the held POKeMON one row at a time, reordering the party
-- as it goes; A lets go; B walks it home.  Modelled on
-- modules/Gen1Party/screen.lua, whose note is worth repeating because it is
-- the load-bearing part:
--
--   "The array is reordered on every step rather than once at the end...
--    Party order IS battle order -- party[1] is who you send out -- so a list
--    drawn in one order over an array stored in another has a lead POKeMON
--    nobody on screen can see."
--
-- There is no such window here either: what the list looks like IS what the
-- save says, on every frame of the carry.  It is also why letting go costs
-- nothing to commit, and why B can walk the POKeMON home exactly -- every step
-- left the others in their own order, so putting this one back in the row it
-- started in restores the party however far it travelled.
--
-- ------- and the mail rides with it
--
-- sPartyMail is six structs keyed by PARTY SLOT, so a member that moves rows
-- without its letter moving too arrives holding somebody else's mail.  The
-- cart's own `Mail.swapSlots` is the pair-copy for it, and each single-row
-- step is exactly one such pair -- which is the other reason to move a row at
-- a time rather than compute the destination and jump.
--
-- ------- and the row still says SWITCH
--
-- Red's `live_move` renames the popup row MOVE, which it can because Red's
-- popup has no other MOVE.  Gold's does: `GetMonSubmenuItems` puts STATS,
-- SWITCH, MOVE and ITEM on it, and that MOVE is the move manager -- reorder
-- the four attacks.  So the row keeps the cart's own word here; the setting
-- is named for the behaviour, which is the part that changes.
--
-- ------- the flash
--
-- Sixteen steps lit and eight dark at the engine's sixty a second, which is
-- Red's box and party to the frame: four shades cannot dim a POKeMON, so it
-- blinks, and it stays lit twice as long as it is dark because the thing
-- flashing is the thing you are trying to look at.

return function(mod)
  local self = {}

  local FLASH_PERIOD, FLASH_ON = 24, 16
  local MARK = "__gen1PartyGen2Carry"

  local function engineModule(name)
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" then return module end
    return nil
  end

  -- Pure, and exposed, because it is the whole of the rule: one step of a
  -- carry is an adjacent exchange, and a run of them is an insertion.
  function self.step(party, from, delta, total)
    local to = from + delta
    if to < 1 or to > total then return from end
    party[from], party[to] = party[to], party[from]
    return to
  end

  function self.install()
    local PartyMenu = engineModule("src.ui.gen2.PartyMenu")
    local Mail = engineModule("src.core.gen2.Mail")
    if not PartyMenu then
      mod.log:warn("no src.ui.gen2.PartyMenu; MOVE stays the cart's swap")
      return false
    end
    if rawget(PartyMenu, MARK) then return true end
    local baseSwitch = PartyMenu.updateSwitch
    local baseIcon = PartyMenu.drawIcon
    if type(baseSwitch) ~= "function" or type(baseIcon) ~= "function" then
      mod.log:warn("src.ui.gen2.PartyMenu has no updateSwitch/drawIcon; MOVE "
        .. "stays the cart's swap")
      return false
    end

    local function enabled()
      return mod.options:get("live_move") ~= false
    end

    PartyMenu.updateSwitch = function(screen, input, ...)
      if not enabled() then return baseSwitch(screen, input, ...) end
      local from = screen.switchFrom
      local party = screen.party
      if not (from and type(party) == "table") then
        return baseSwitch(screen, input, ...)
      end
      local total = #party
      -- Where it came from, so B can put it back exactly.  Set on the first
      -- frame of the carry rather than in `beginSwitch`, which this file does
      -- not wrap: the cart may open the move from more than one place.
      if screen.gen1wildCarryHome == nil then
        screen.gen1wildCarryHome = from
      end

      local delta
      if input:wasPressed("up") then delta = -1
      elseif input:wasPressed("down") then delta = 1 end
      if delta then
        local to = self.step(party, from, delta, total)
        if to ~= from then
          -- sPartyMail is keyed by slot, so the letter travels with the mon.
          -- Only when this list IS the save's party: a battle copy or a
          -- day-care pick has no mail to carry.
          if Mail and type(Mail.swapSlots) == "function"
              and screen.save and screen.save.party == party then
            pcall(Mail.swapSlots, screen.save, from, to)
          end
          -- The cursor rides with the POKeMON: it is the thing being moved,
          -- so it is the thing the cursor is on.
          screen.switchFrom, screen.index = to, to
        end
        return
      end

      if input:wasPressed("a") then
        -- Letting go commits nothing, because every step already did.
        screen.switchFrom = nil
        screen.gen1wildCarryHome = nil
        if type(screen.playSfxTwice) == "function" then
          pcall(screen.playSfxTwice, screen, "Sfx_SwitchPokemon")
        end
        return
      end

      if input:wasPressed("b") then
        -- Home, one row at a time, so the mail pairs the same way back.
        local home = screen.gen1wildCarryHome or from
        local at = screen.switchFrom or from
        while at ~= home do
          local to = self.step(party, at, home > at and 1 or -1, total)
          if to == at then break end
          if Mail and type(Mail.swapSlots) == "function"
              and screen.save and screen.save.party == party then
            pcall(Mail.swapSlots, screen.save, at, to)
          end
          at = to
        end
        screen.index = home
        screen.switchFrom = nil
        screen.gen1wildCarryHome = nil
        return
      end
    end

    -- ------- which row is being drawn
    --
    -- `drawIcon(mon, px, py)` is not told, and the row is the whole of what
    -- the flash needs to know.  The cart answers it one call earlier:
    --
    --     self:drawIcon(mon, self:iconX(i), 4 + (i - 1) * 16 + self:iconBob(i))
    --
    -- `iconX(index)` runs immediately before the draw it is an argument to, so
    -- recording the index there is the row `drawIcon` is about to paint -- no
    -- second copy of the list loop, and no arithmetic on `py`.
    --
    -- Recorded HERE rather than read off somebody else's bookkeeping.  This
    -- used to read `gen1wildIconRow`, which the Gen1Wild bundle's
    -- runtime/icons2.lua sets at the same seam -- and that is a field this mod
    -- does not own and does not always have.  Installed on its own, outside
    -- the bundle, nothing set it, so the carried POKeMON never flashed: the
    -- one visible half of MOVE, missing, on exactly the installs that have no
    -- bundle to fall back on.  Both wraps can sit on `iconX` at once; each
    -- writes its own field and neither reads the other's.
    local baseIconX = PartyMenu.iconX
    if type(baseIconX) == "function" then
      PartyMenu.iconX = function(menu, index, ...)
        menu.gen1wildCarryRow = index
        return baseIconX(menu, index, ...)
      end
    end

    -- The POKeMON in your hand flashes.
    PartyMenu.drawIcon = function(screen, mon, px, py, ...)
      if enabled() and screen.switchFrom
          and screen.switchFrom == screen.gen1wildCarryRow
          and ((screen.clock or 0) % FLASH_PERIOD) >= FLASH_ON then
        return
      end
      return baseIcon(screen, mon, px, py, ...)
    end

    PartyMenu[MARK] = true
    mod.log:info("MOVE carries a POKeMON through the party on Gold")
    return true
  end

  return self
end
