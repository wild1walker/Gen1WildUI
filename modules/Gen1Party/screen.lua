-- Gen1Party: the party menu, drawn like the rest of the set.
--
-- Returns a factory: factory(mod, C) -> { new = function(game, opts) },
-- which main.lua installs over the builtin "PartyMenu" id.
--
-- ------- what this screen is, and is not
--
-- It is the VANILLA party menu with two of its methods replaced.  PartyMenu
-- is not one screen but seven -- the field menu, the battle switch, the
-- forced switch after a faint, the item target, the TM/HM teach list with its
-- ABLE / NOT ABLE column, the SOFTBOILED donor, the evolution-stone list --
-- and each has its own input rules, its own bottom message and its own idea
-- of what A does.  None of that is touched here: the vanilla constructor
-- builds the screen, and only `draw` and `sgbPalettes` are swapped out.  This
-- mod has an opinion about how the party LOOKS and none at all about what it
-- does.
--
-- ------- the frame, and what it cost
--
-- The set's shape is a header box on rows 0-2, a body on rows 3-14 and a
-- footer box on rows 15-17.  That body is 96 pixels, which is exactly six
-- party rows of sixteen -- the slots were never the problem.  The footer was:
-- three tile rows hold ONE line of text, and four of the five prompts the
-- engine hands back are two lines (party_menu.asm via data.text).  Three rows
-- of header plus five of footer plus twelve of party is twenty against the
-- eighteen there are, so two rows have to come from somewhere.
--
-- They come from the words.  Every prompt is printed on one line: the
-- engine's own, whenever the engine's own fits -- "Choose a POKéMON." is
-- seventeen glyphs against a box that holds eighteen, so the field menu still
-- says exactly what the engine says -- and this mod's one-line wording for the
-- four that do not.  That is the trade, and it is the only one that keeps all
-- six members on screen with a sentence under them that finishes.
--
-- The alternative was five visible slots and a scroll, on a screen whose whole
-- job is showing you the party at once.
--
-- Across the row it is just as tight.  The vanilla name column runs 24..104,
-- the level 104..128 and the status 136..160 -- packed to the last pixel of
-- the screen, which is why an FNT reads as clipped rather than placed.  The
-- three changes below are the ones that buy a margin without taking anything
-- away:
--
--   * the status moves from a fixed x=136 to right-aligned on 152.  Free: the
--     level always ends at 128 (PrintLevel overwrites the <LV> tile with the
--     third digit at L100, so two digits and three end in the same place),
--     which leaves 128..136 already empty.
--   * the HP bar moves one tile left, from tile 5 to tile 4, and the HP
--     numbers right-align on 152.  The bar keeps all six segments -- it is
--     the at-a-glance read on this screen and shortening it to buy the margin
--     would have been the wrong trade -- and the gap it moves into is the one
--     between the icon and the bar, which nothing was using.
--   * the numbers keep the "%3d/%3d" padding rather than becoming variable
--     width, because that padding is load bearing: the bar's right cap sits
--     under the first glyph, and a SPACE over the cap is what makes the two
--     not collide.  Variable width would put a digit there.
--
-- The dex list's ruled icon column is here too, and it is the same eight
-- pixels again: the rule needs the names off the icon cell, ten glyphs of
-- name need every pixel from 24 to the level column, so the tenth glyph is
-- what buys it.  That was left undone for two versions on the grounds that a
-- nickname is the player's own text -- until it was pointed out that art
-- filling its 16-pixel cell (three of six is typical for an icon pack) sits
-- flush against the first letter with no air at all, which costs more than
-- the tenth glyph does.  RULED ICONS, and off restores the wide column.
--
-- ------- the icons
--
-- Vanilla lays ONE MEWMON zone over tiles (1,0)-(2,11) -- the whole icon
-- column, all six of them -- so every POKeMON in the party wears the same
-- salmon.  That single zone is what this mod replaces with one zone per
-- member, so each wears its own species colours: the same thing the dex list
-- does for its rows and Gen1BillsBox does for its grid, and the reason a
-- party opened next to either of them stops looking like a different game.

return function(mod, C)
  local Font = require("src.render.Font")
  local HudTiles = require("src.render.HudTiles")
  local PaletteFX = require("src.render.PaletteFX")
  local PartyMenu = require("src.ui.PartyMenu")
  local Sprites = require("src.pokemon.Sprites")
  local Status = require("src.battle.Status")
  local Strings = require("src.core.Strings")
  local Theme = require("src.ui.Theme")

  -- ------- geometry
  --
  -- Everything the icons touch is a whole tile, because an SGB palette zone
  -- is ADDRESSED in tiles (PaletteFX.zone) and a zone per icon is the point.
  -- Slot i's rows are tile rows BODY_TY+(i-1)*2 and the one under it.

  local ICON_X, ICON = 8, 16
  local ICON_TX1, ICON_TX2 = 1, 2        -- x 8..23

  -- ------- the icon column, ruled off
  --
  -- The dex list rules a hairline between its icons and its rows and keeps
  -- three pixels of air either side of it.  The party had NONE: the name
  -- column starts at 24, which is the pixel after the icon cell ends, so art
  -- that fills its cell (and a good deal of it does -- three of six is
  -- typical for an icon pack) touches the first letter of the name.
  --
  -- Ten glyphs of name need exactly 24..104, and 104 is where the level's
  -- <LV> tile starts, so the gap can only be bought with the tenth glyph.
  -- That is what RULED ICONS spends: names start at 32 behind a rule at 26,
  -- and a ten-glyph name comes back nine.  Off restores the full-width
  -- column, touching icons and all.
  local NAME_X, NAME_X_WIDE = 32, 24
  local NAME_GLYPHS, NAME_GLYPHS_WIDE = 9, 10
  local RULE_X = 26
  local LV_TILE, LV_X = 104, 112         -- the <LV> tile, then the digits
  local LV_WIDE_X = 104                  -- L100: the third digit takes the tile
  local ROW_H = 16

  -- The body starts under the header box rather than at the top of the screen,
  -- so every row -- and every palette zone addressed in tiles -- moves down by
  -- three tile rows.  BODY_TY is that offset in the unit zones are counted in.
  local BODY_TY = 3
  local function entryY(i) return C.BODY_TOP + (i - 1) * ROW_H end

  -- The bar, one tile left of vanilla so the numbers can keep a margin.
  local BAR_TX = 4                       -- x 32; vanilla is tile 5
  local BAR_SEGMENTS = 6
  -- the segment cells, for the colour zone: x 48..96 is tiles 6..11
  local BAR_ZONE_TX1, BAR_ZONE_TX2 = 6, 11

  -- The TM/HM and evolution-stone lists print their verdict where the bar
  -- would be.  Right-aligned so the shorter ABLE shares NOT ABLE's right edge,
  -- which is what vanilla does -- on 152 now rather than trailing off 160.
  local ABLE_END = 152

  -- ------- the header, and the one line under the body
  --
  -- The title is fixed the way the dex list's is: it says what screen you are
  -- on, and the footer says what you can do about it.  Thirteen glyphs against
  -- a box that holds eighteen, so it sits well inside the margin.  What goes in the footer
  -- is bottomMessage() flattened to one line when it fits, because the words
  -- belong to the engine wherever the engine's words will go -- a reword that
  -- SHORTENS a prompt (or a translation that does) is printed verbatim without
  -- this table being touched.  Only a prompt too wide for the box falls back
  -- to the line here.
  local TITLE = "POKéMON PARTY"

  local PROMPTS = {
    swap   = "Move it where?",
    tmhm   = "Use TM on which?",
    item   = "Use item on which?",
    battle = "Bring out which?",
  }

  -- ------- full-colour icons
  --
  -- An icon mod's authored art is re-blit UNSHADED over the colourised pass,
  -- so a species palette under it is paint nobody ever sees -- and running it
  -- through the shade remap instead would destroy it, because that remap keys
  -- off the RED channel and an orange pixel lands on the palette's white.
  -- Decide per MON rather than per species: Sprites.iconPath is raised with
  -- the live mon, which is how a shiny tells itself apart from an ordinary one
  -- of its species.
  --
  -- A built-in icon CLASS is never full colour whatever file it points at,
  -- because drawIcon bakes those through obpIcon, which flattens every pixel
  -- to a grey off its red channel.  Only a mod's own image -- an entry table
  -- rather than an icon name -- reaches the screen untouched.
  local iconColour = setmetatable({}, { __mode = "k" })   -- mon -> info
  local pathColour = {}                                   -- path -> info

  local function resolveIcon(game, mon)
    local icons = game.data and game.data.icons
    if not icons then return nil, nil end
    local def = game.data.pokemon and game.data.pokemon[mon.species]
    local entry = (icons.bySpecies and icons.bySpecies[mon.species])
      or (def and def.icon)
    local name, path
    if type(entry) == "string" then
      name = entry
      path = icons.icons and icons.icons[entry]
    elseif type(entry) == "table" then
      path = entry.image
    end
    if not path then
      name = def and def.dex and icons.byDex and icons.byDex[def.dex]
      path = name and icons.icons and icons.icons[name]
    end
    local ok, hooked = pcall(Sprites.iconPath, game.data, mon, path,
                             { name = name })
    if ok then path = hooked end
    return name, path
  end

  -- Does this file carry a colour a grey ramp cannot?  Read once per path and
  -- remembered, because it is a property of the file.
  local function scanPath(path)
    local info = pathColour[path]
    if info ~= nil then return info end
    info = { colour = false, w = ICON, h = ICON }
    pcall(function()
      local data = require("src.render.Assets").imageData(path)
      local w, h = data:getDimensions()
      info.w, info.h = w, h
      for y = 0, (h > ICON and ICON or h) - 1 do
        for x = 0, w - 1 do
          local r, g, b, a = data:getPixel(x, y)
          if a > 0 and (math.abs(r - g) > 0.02 or math.abs(g - b) > 0.02) then
            info.colour = true
            return
          end
        end
      end
    end)
    pathColour[path] = info
    return info
  end

  local function fullColour(game, mon)
    if not mon then return nil end
    local hit = iconColour[mon]
    if hit == nil then
      local name, path = resolveIcon(game, mon)
      if not path or name then
        hit = false
      else
        local info = scanPath(path)
        hit = info.colour
          and { w = info.w > ICON and ICON or info.w,
                h = info.h > ICON and ICON or info.h }
          or false
      end
      iconColour[mon] = hit
    end
    return hit or nil
  end

  -- ------- colour
  --
  -- Two rules, the same two the dex list and the box grid run on.
  --
  -- The BASE is the plain four DMG greys, so everything drawn here -- the
  -- names, the numbers, the message box, all shade 3 -- comes out black on
  -- white.  Vanilla's base is GREENBAR, which is the bar palette standing in
  -- for a screen palette.
  --
  -- Then EACH POKeMON GETS ITS OWN, in place of the single MEWMON column
  -- vanilla lays over all six icons at once.  The bar zones are kept exactly
  -- as vanilla computes them, including the stale-colour window a medicine's
  -- fill animation needs (#252) -- that is the bar's business, not this
  -- mod's.
  local function palettesFor(vanillaSgb)
    return function(self, game)
      if not C.option("species_colours", true) then
        return vanillaSgb(self, game)
      end
      local ok, zones = pcall(function()
        local out = { PaletteFX.whole(PaletteFX.GRAYS) }
        local party = self.party or (game.save and game.save.party) or {}

        for i, mon in ipairs(party) do
          -- full-colour art sits out the pass, so a zone under it is paint
          -- nobody ever sees
          if not fullColour(game, mon) then
            local colors = PaletteFX.monPal(game.data, mon.species)
            local ty = BODY_TY + (i - 1) * 2
            local zone = colors
              and PaletteFX.zone(colors, ICON_TX1, ty, ICON_TX2, ty + 1)
            if zone then out[#out + 1] = zone end
          end
        end

        -- the TM/HM list prints ABLE / NOT ABLE where the bar would be, so
        -- those rows have no bar to colour (party_menu.asm .teachMoveMenu)
        if not (self.tmhm or self.evoStone) then
          for i, mon in ipairs(party) do
            -- while a medicine's fill runs the block palette is STALE, not
            -- recomputed; hold the starting HP for exactly that window
            local hp = mon.hp
            if self.heal and self.heal.mon == mon then hp = self.heal.from end
            local bar = PaletteFX.pal(game.data,
                                      PaletteFX.barPalName(hp, mon.stats.hp))
            if bar then
              local ty = BODY_TY + (i - 1) * 2 + 1
              out[#out + 1] = PaletteFX.zone(bar, BAR_ZONE_TX1, ty,
                                             BAR_ZONE_TX2, ty)
            end
          end
        end
        return out
      end)
      -- a screen with no palette opinion inherits whatever is underneath, so
      -- falling back to vanilla's answer matters more than falling back to nil
      if ok and zones then return zones end
      return vanillaSgb(self, game)
    end
  end

  -- ------- one line under the body
  --
  -- bottomMessage() owns the words and this owns the width.  Flatten whatever
  -- it returns onto one line and print it when it fits; the field menu's
  -- "Choose a POKéMON." does, so the commonest screen in the game still says
  -- exactly what the engine says.  When it does not fit, print this mod's
  -- wording for the mode instead of a sentence cut in half -- the two-line
  -- box those prompts were written for is what the header box was paid for
  -- with, and half of "Use TM on which POKéMON?" is not an improvement on
  -- either.
  local function flatten(text)
    return (tostring(text or ""):gsub("%s*\n%s*", " "):gsub("%s+$", ""))
  end

  local function modeOf(self)
    if self.swapFrom then return "swap" end
    if self.tmhm then return "tmhm" end
    if self.softboiledFrom or self.itemUse then return "item" end
    if self.battle then return "battle" end
    return "normal"
  end

  local function fits(text)
    local ok, w = pcall(Font.width, text)
    return ok and w <= C.LINE_W
  end

  local function promptFor(self)
    local ok, message = pcall(self.bottomMessage, self)
    local line = ok and flatten(message) or ""
    if line ~= "" and fits(line) then return line end
    local ours = PROMPTS[modeOf(self)]
    -- no fallback for the field menu on purpose: if the engine's own normal
    -- prompt ever stops fitting, its FIRST line is still a whole sentence
    -- ("Choose a POKéMON.") and closer to the engine's copy than anything
    -- written here.
    if ours then
      ours = Strings(ours)
      if fits(ours) then return ours end
    end
    return C.truncate(line, 18)
  end

  -- ------- drawing

  local function drawIcon(self, mon, y, selected)
    C.white()
    pcall(PartyMenu.drawIcon, self.game, mon, ICON_X, y, selected,
          self.blink or 0)
    local rect = fullColour(self.game, mon)
    if rect then
      pcall(PaletteFX.markTrueColor, ICON_X, y, rect.w, rect.h)
    end
    C.black()
  end

  local function draw(self)
    C.clear()

    -- the boxed top and bottom the rest of the set has, and the body between
    C.headerBox()
    Font.draw(Strings(TITLE), C.LEFT, C.HEADER_TEXT_Y)

    local game = self.game
    local party = self.party or game.save.party
    if #party == 0 then
      Font.draw(Strings("No POKéMON!"), 16, 64)
    end

    -- Each bar row carries its own GREENBAR / YELLOWBAR / REDBAR zone, so the
    -- fill must stay the raw DMG shade-2 grey and let the zone colour it --
    -- but only when a zone pass will actually run.  Renderer takes the shader
    -- path exactly when the zone list is non-empty AND PaletteFX.shader()
    -- resolves, which is the pair tested here; with no shader the canvas blits
    -- unshaded and drawHPBar's own tint is the only colour the bar can get.
    local barZoned = PaletteFX.shader() ~= nil
      and PaletteFX.pal(game.data, "GREENBAR") ~= nil

    -- the hairline, the dex's own, down the whole body rather than per row
    local ruled = C.option("ruled_icons", true) and #party > 0
    if ruled then
      C.black()
      C.rule(RULE_X, C.BODY_TOP, 1, C.BODY_BOTTOM - C.BODY_TOP + 1)
    end
    local nameX = ruled and NAME_X or NAME_X_WIDE
    local nameGlyphs = ruled and NAME_GLYPHS or NAME_GLYPHS_WIDE

    for i, mon in ipairs(party) do
      local def = game.data.pokemon[mon.species]
      local y = entryY(i)
      local selected = i == self.index

      drawIcon(self, mon, y, selected)

      -- cut on a glyph boundary, never a byte one: a nickname can carry
      -- NIDORAN's ♂/♀, which is one glyph across several bytes
      Font.draw(C.truncate(mon.nickname or def.name, nameGlyphs), nameX, y)

      -- the level, at the column PrintLevel uses.  At L100 the third digit
      -- takes the <LV> tile's cell, which is why both cases end at 128.
      if mon.level < 100 then
        HudTiles.tile(0x6E, LV_TILE, y)
        Font.draw(tostring(mon.level), LV_X, y)
      else
        Font.draw(tostring(mon.level), LV_WIDE_X, y)
      end
      C.black()

      if self.tmhm then
        local can = false
        for _, m in ipairs(def.tmhm or {}) do
          if m == self.tmhm.move then can = true break end
        end
        local text = can and Strings("ABLE") or Strings("NOT ABLE")
        Font.draw(text, C.rightAlign(text, ABLE_END), y + 8)
      elseif self.evoStone then
        local can = false
        for _, evo in ipairs(def.evolutions or {}) do
          if evo.method == "ITEM" and evo.item == self.evoStone then
            can = true break
          end
        end
        local text = can and Strings("ABLE") or Strings("NOT ABLE")
        Font.draw(text, C.rightAlign(text, ABLE_END), y + 8)
      else
        if mon.hp <= 0 then
          local text = Strings("FNT")
          Font.draw(text, C.rightAlign(text, C.RIGHT), y)
        elseif mon.status then
          local text = Status.hudLabelFor(game.data.statuses, mon.status)
          Font.draw(text, C.rightAlign(text, C.RIGHT), y)
        end

        -- While a medicine's UpdateHPBar2 fill runs, this row draws the HP the
        -- animation has reached rather than the final value; drawHPBar reads
        -- only .hp and .stats, so a shim is enough and the real mon is never
        -- mutated for display (#252).
        local shown = mon
        if self.heal and self.heal.mon == mon then
          shown = { hp = math.floor(self.heal.shown), stats = mon.stats }
        end
        C.white()
        HudTiles.drawHPBar(game.data, BAR_TX, (y + 8) / 8, shown, nil,
                           barZoned, BAR_SEGMENTS)
        C.black()
        -- "%3d/%3d" rather than variable width on purpose: the bar's right
        -- cap sits under the first glyph, and the pad's SPACE over that cap is
        -- what keeps a two-digit HP from colliding with it.
        local hpText = ("%3d/%3d"):format(shown.hp, mon.stats.hp)
        Font.draw(hpText, C.rightAlign(hpText, C.RIGHT), y + 8)
      end

      -- PartyMenuInit seeds wTopMenuItemY/X with 1/0, so the cursor sits on
      -- the entry's SECOND tile row -- level with the middle of the two-row
      -- icon, not on the name row entryY returns (#278).
      local cursorY = y + 8
      if selected then
        Font.drawCode(Theme.cursor, 0, cursorY)
      end
      -- the unfilled swap arrow; the filled cursor replaces it in the tilemap
      -- when they share a row (#814)
      if (i == self.swapFrom or i == self.softboiledFrom) and not selected then
        Font.drawCode(Theme.cursorHollow, 0, cursorY)
      end
    end

    -- ------- the footer
    --
    -- Three rows on 15-17 with its one line on 128, the same box in the same
    -- place the dex list puts its SEEN / OWN counts.  What goes in it is
    -- promptFor: the engine's own words whenever they fit the width.
    C.footerBox()
    Font.draw(promptFor(self), C.LEFT, C.FOOTER_TEXT_Y)

    if self.submenu then
      local n = #self.subItems
      Font.drawBox(9, 17 - n * 2 - 1, 11, n * 2 + 1)
      C.black()
      local y0 = (17 - n * 2) * 8
      for si, entry in ipairs(self.subItems) do
        Font.draw(entry.label, 88, y0 + (si - 1) * 16)
      end
      Font.drawCode(Theme.cursor, 80, y0 + (self.subIndex - 1) * 16)
    end

    C.white()
  end

  -- ------- the screen
  --
  -- Built by the vanilla constructor, then re-dressed.  Every mode, every key
  -- and every callback is still the engine's.
  local Party = {}

  function Party.new(game, opts)
    local menu = PartyMenu.new(game, opts)
    local vanillaSgb = PartyMenu.sgbPalettes
    menu.draw = draw
    menu.sgbPalettes = palettesFor(vanillaSgb)
    return menu
  end

  -- for the suite
  Party.geometry = {
    ICON_X = ICON_X, NAME_X = NAME_X, ROW_H = ROW_H,
    BAR_TX = BAR_TX, BAR_SEGMENTS = BAR_SEGMENTS,
    RIGHT = C.RIGHT, LEFT = C.LEFT, ABLE_END = ABLE_END,
    NAME_X_WIDE = NAME_X_WIDE, RULE_X = RULE_X,
    NAME_GLYPHS = NAME_GLYPHS, NAME_GLYPHS_WIDE = NAME_GLYPHS_WIDE,
    BODY_TOP = C.BODY_TOP, BODY_BOTTOM = C.BODY_BOTTOM, BODY_TY = BODY_TY,
    HEADER_TH = C.HEADER_TH, HEADER_TEXT_Y = C.HEADER_TEXT_Y,
    FOOTER_TY = C.FOOTER_TY, FOOTER_TEXT_Y = C.FOOTER_TEXT_Y,
    LINE_W = C.LINE_W, TITLE = TITLE,
  }
  Party.entryY = entryY
  Party.promptFor = promptFor
  Party.drawInto = draw

  return { new = Party.new, geometry = Party.geometry,
           entryY = Party.entryY, promptFor = Party.promptFor }
end
