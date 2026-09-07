-- Gold's party list, drawn like the rest of the set.
--
-- Returns a factory: factory(mod) -> { install, layout, nameRow, iconY,
-- cancelCursorTx, truncate }.  main.lua installs it on a Gen 2 boot only.
--
-- ------- what was wrong with the page, and what was not
--
-- Everything ON Gold's party list is already better than Red's: the icons are
-- animated, the held-item marker replaces a quadrant of the icon rather than
-- sitting beside it, every row carries an HP bar, a level and a status tag,
-- and since 0.32.23 each mon wears its own species colours (see main.lua).
-- None of that is touched here and none of it needed touching.
--
-- What the page has is no FRAME.  `PartyMenu:drawPanel` opens with
-- `Chrome.clear()` -- bare paper -- and the six rows, the CANCEL row and the
-- icons stand on it with nothing around them; the only box on the screen is
-- the prompt at the bottom.  That is faithful to the cart, and it is also the
-- one page in this suite with no chrome on it, so a party opened next to the
-- Pokedex or the PACK reads as a different game.  Which is the same sentence
-- the Gen 1 screen's own note ends on, arrived at from the other side.
--
-- ------- so this replaces the FRAME and not the row
--
-- `drawPanel` is the only method swapped.  Input, the seven flavours of the
-- list, the submenu, switching, SOFTBOILED, the item result and every branch
-- that decides what A does are the engine's and are never reached from here.
-- That is the same discipline the Gen 1 arm keeps -- it swaps `draw`,
-- `sgbPalettes` and `update` and nothing else -- and it is what makes this
-- safe on a screen the player cannot get out of if it goes wrong.
--
-- Inside `drawPanel`, the rule is: MOVE the block, keep the columns.
--
--   * the six rows move down two tile rows, from 1..12 to 3..14, which is
--     what makes room for a header box on 0-2 and leaves the footer 15-17.
--   * every COLUMN on the second line stays exactly where the ASM puts it --
--     status at 5, level at 8, the bar at 11.  Those three are packed against
--     each other at L100 already, and buying a right margin there is a
--     collision this does not need to risk for a page whose problem was the
--     frame.
--   * the first line moves by one tile and only because of the rule below.
--
-- ------- the icon column, ruled off
--
-- Gold's icon slides right by eight pixels on the selected row
-- (`PartyMenu:iconX`) and its name column starts at 24 -- the pixel after the
-- icon cell ends -- so on the selected row the art is flush against the first
-- letter of the name with no air at all, which is the same complaint the Gen 1
-- screen fixes with the dex list's hairline.
--
-- So the icon is fixed at 8 rather than sliding, a rule goes at 26, and names
-- start at 32.  The slide was a selection cue and the cursor is already one;
-- the bob is kept, because that is the cue that survives being framed.  Ten
-- glyphs of name need every pixel from 24 to the HP digits at 104, so the air
-- is bought with the tenth: CHARMANDER reads CHARMANDE.  RULED ICONS off puts
-- the name back at 24 with all ten, and the icon back on the engine's slide.
--
-- ------- where CANCEL went, and why it had to go somewhere
--
-- Gold's CANCEL is a real row -- an index past the last mon, cursored and
-- chosen like any other -- where Red's party has none.  Six mons at two rows
-- each is twelve rows, a header is three and a footer is three: eighteen, and
-- the screen has eighteen.  There is no row left.
--
-- The alternatives were five visible slots and a scroll -- which the Gen 1
-- note already rejects, on a screen whose whole job is showing you the party
-- at once -- or a CANCEL that sits after the last mon when the party is small
-- and jumps into the header when it is full, which is worse than either: a
-- control that moves is harder to find than one in an odd place.
--
-- So it is in the header, always, right-aligned opposite the title, with the
-- cursor beside it when it is the selection.  Nothing about how it is REACHED
-- changes: `isCancel()` is the engine's, the index past the last mon is the
-- engine's, and B still cancels.  Only where the word is drawn.
--
-- ------- the item result keeps the engine's box
--
-- A message from an item ("... was cured of poison.") can be two lines, and
-- the footer here holds one.  Rather than reword the engine's sentences or
-- clip them, the item result is drawn in the engine's own textbox at its own
-- coordinates -- which covers the bottom of the list for as long as the
-- message is up, exactly as it does on the cart.

return function(mod)
  local Chrome = require("src.ui.gen2.Chrome")
  local Font = require("src.render.Font")
  local PartyMenu = require("src.ui.gen2.PartyMenu")
  local Strings = require("src.core.Strings")

  local G = {}

  -- ------- geometry
  --
  -- Tile rows unless the name says px.  The body is 96 pixels between the two
  -- boxes, which is six 16-pixel rows -- exactly a full party, and the same
  -- arithmetic the Gen 1 chrome kit is built on.
  local L = {
    HEADER_TY = 0, HEADER_TH = 3,
    BODY_TY = 3,                    -- first body tile row
    BODY_PY = 24,                   -- and its first pixel row
    ROW_TH = 2,                     -- tile rows per mon
    ROW_PH = 16,
    FOOTER_TY = 15, FOOTER_TH = 3,
    TITLE_TX = 1, HEADER_TEXT_TY = 1,
    CANCEL_END_TX = 19,
    ICON_PX = 8,                    -- fixed, where the engine slides 0/8
    RULE_PX = 26,
    NAME_TX = 4, NAME_GLYPHS = 9,
    NAME_TX_WIDE = 3, NAME_GLYPHS_WIDE = 10,
    -- The engine's own columns, kept: PlacePartyMenuHPDigits (13,1),
    -- PlacePartyMonStatus (5,2), PlacePartyMonLevel (8,2), PlacePartyHPBar
    -- (11,2), and the TM/HM verdict where the bar would be.
    HP_TX = 13, STATUS_TX = 5, LEVEL_TX = 8, BAR_TX = 11, ABLE_TX = 12,
    PROMPT_TX = 1, PROMPT_TY = 16,
  }
  G.layout = L

  -- The title says what screen you are on, the footer says what you can do
  -- about it -- the split every screen in this set keeps.  Short enough that
  -- CANCEL fits opposite it: five glyphs and six against a box that holds
  -- eighteen.
  local TITLE = "PARTY"

  function G.nameRow(index) return L.BODY_TY + (index - 1) * L.ROW_TH end
  function G.iconY(index) return L.BODY_PY + (index - 1) * L.ROW_PH end

  -- Where the cursor goes beside a right-aligned CANCEL: one tile left of the
  -- first tile the word covers.  Taken from the drawn width rather than the
  -- glyph count, because a translation's CANCEL is not six glyphs.
  function G.cancelCursorTx(width)
    return L.CANCEL_END_TX - math.ceil((width or 0) / 8) - 1
  end

  -- Cut on a GLYPH boundary, not a byte one: Font.split hands back a span per
  -- glyph with its byte range, and NIDORAN's gender sign is one glyph across
  -- several bytes, so a plain sub() can slice a character in half.
  function G.truncate(text, glyphs)
    if type(text) ~= "string" then return text end
    local ok, spans = pcall(Font.split, text)
    if not ok or type(spans) ~= "table" or #spans <= glyphs then return text end
    return text:sub(1, spans[glyphs].to)
  end

  -- The hairline, in the ink the page is currently wearing.  Read off the live
  -- box palette rather than hardcoded black, so it reverses with everything
  -- else under UI THEME's DARK instead of being the one invisible line on a
  -- black page.
  local function rule(ty)
    local ink = Chrome.DEFAULT_BOX_PALETTE and Chrome.DEFAULT_BOX_PALETTE[4]
      or { 0, 0, 0 }
    local g = love.graphics
    g.setColor(ink[1] / 255, ink[2] / 255, ink[3] / 255, 1)
    g.rectangle("fill", L.RULE_PX, ty * 8, 1, L.ROW_TH * 8)
    g.setColor(1, 1, 1, 1)
  end

  local function ruled()
    local ok, value = pcall(function()
      return mod.options:get("ruled_icons")
    end)
    return not ok or value ~= false
  end

  -- ------- the panel
  --
  -- Written to be read beside the engine's own `drawPanel`: same order, same
  -- calls, and every coordinate that did not move is spelled with the same
  -- number the ASM gives it.
  function G.drawPanel(self)
    -- LoadPartyMenuGFX starts with LoadFontsBattleExtra, so tiles $60-$6f on
    -- this screen are FontBattleExtra's: <LV> is the bold ":L" here, not
    -- FontExtra's "Lv", and the HP bar's cells come from the same sheet.
    local wasBattle = Font.useBattleExtra(true)
    Chrome.clear()

    -- ---- the header
    Chrome.box(0, L.HEADER_TY, 20, L.HEADER_TH)
    Chrome.print(Strings(TITLE), L.TITLE_TX, L.HEADER_TEXT_TY)
    local cancel = Strings("CANCEL")
    local okWidth, cancelWidth = pcall(Font.width, cancel)
    Chrome.printRight(cancel, L.CANCEL_END_TX, L.HEADER_TEXT_TY)
    if self:isCancel() then
      Chrome.cursor(G.cancelCursorTx(okWidth and cancelWidth or 48),
                    L.HEADER_TEXT_TY)
    end

    -- ---- the six rows
    local withRule = ruled()
    local statuses = self.game and self.game.data and self.game.data.gen2Statuses
    for i, mon in ipairs(self.party) do
      local nameY = G.nameRow(i)
      local dataY = nameY + 1
      if i == self.index then
        Chrome.cursor(0, nameY)
      elseif self.switchFrom == i then
        -- SwitchPartyMons parks a hollow arrow on the held row; the live
        -- cursor overwrites it whenever it sits there.
        Chrome.cursor(0, nameY, true)
      end
      -- Fixed at ICON_PX with the rule on, and back on the engine's slide
      -- with it off -- which is the whole of what RULED ICONS buys or gives
      -- back on this page.
      local iconX = withRule and L.ICON_PX or self:iconX(i)
      self:drawIcon(mon, iconX, G.iconY(i) + self:iconBob(i))
      if withRule then rule(nameY) end

      local hp = self:shownHpFor(i, mon)
      local row = PartyMenu.rowFor(mon, hp, statuses)
      Chrome.print(
        G.truncate(row.name, withRule and L.NAME_GLYPHS or L.NAME_GLYPHS_WIDE),
        withRule and L.NAME_TX or L.NAME_TX_WIDE, nameY)

      if self.tmhm then
        local able = self:tmhmAble(mon)
        if able then Chrome.print(able, L.ABLE_TX, dataY) end
      elseif row.hp then
        Chrome.print(row.hp, L.HP_TX, nameY)
        self:drawHpBar(mon, L.BAR_TX, dataY, hp)
      end
      if row.status then Chrome.print(row.status, L.STATUS_TX, dataY) end
      if row.level then Chrome.print(row.level, L.LEVEL_TX, dataY) end
    end

    -- ReturnToMapWithSpeechTextbox restores the normal font afterwards, and so
    -- does this: the prompt is ordinary text.
    Font.useBattleExtra(wasBattle)

    -- ---- the footer
    if self.itemResult and self.itemResult.text
        and not self:itemResultClimbing() then
      -- The engine's own box at the engine's own coordinates; see the header.
      Chrome.textbox(0, 12, 18, 4)
      local line = 14
      for part in tostring(self.itemResult.text):gmatch("[^\n]+") do
        if line <= 16 then Chrome.print(part, 1, line) end
        line = line + 2
      end
    else
      Chrome.box(0, L.FOOTER_TY, 20, L.FOOTER_TH)
      local prompt = self.switchFrom and Strings(PartyMenu.PROMPTS.moveTo)
        or (self.softboiledFrom and Strings(PartyMenu.PROMPTS.useItem))
        or (self.promptIsBuiltin and Strings(self.prompt) or self.prompt)
      Chrome.print(
        #self.party == 0 and Strings(PartyMenu.PROMPTS.none) or prompt,
        L.PROMPT_TX, L.PROMPT_TY)
    end

    -- PokemonActionSubmenu clears its own strip before MonSubmenu draws, so
    -- the prompt is gone behind the box rather than showing through it.
    if self.submenu then self:drawSubmenu() end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- ------- installing
  --
  -- By identity rather than a flag, and the engine's own `drawPanel` is kept
  -- so a failure can hand it back: a party screen that raises every frame is
  -- one the player cannot leave, and this is decoration.
  local MARK = "__gen1PartyGen2Panel"

  function G.install()
    if rawget(PartyMenu, MARK) then return false end
    local base = PartyMenu.drawPanel
    if type(base) ~= "function" then
      mod.log:warn("src.ui.gen2.PartyMenu has no drawPanel; the party keeps "
        .. "the cart's frame")
      return false
    end
    for _, name in ipairs({ "isCancel", "iconX", "iconBob", "drawIcon",
                            "shownHpFor", "drawHpBar", "tmhmAble",
                            "itemResultClimbing", "drawSubmenu" }) do
      if type(PartyMenu[name]) ~= "function" then
        mod.log:warn("src.ui.gen2.PartyMenu has no %s; the party keeps the "
          .. "cart's frame", name)
        return false
      end
    end
    if type(PartyMenu.rowFor) ~= "function"
        or type(PartyMenu.PROMPTS) ~= "table" then
      mod.log:warn("src.ui.gen2.PartyMenu is not the shape this expects; the "
        .. "party keeps the cart's frame")
      return false
    end

    local broken = false
    PartyMenu.drawPanel = function(self, ...)
      if broken then return base(self, ...) end
      local ok, problem = pcall(G.drawPanel, self)
      if ok then return end
      broken = true
      mod.log:warn("the party is back on the cart's frame for this session: "
        .. "%s", tostring(problem))
      return base(self, ...)
    end
    PartyMenu[MARK] = true
    mod.log:info("the party is drawn in the set's own frame")
    return true
  end

  return G
end
