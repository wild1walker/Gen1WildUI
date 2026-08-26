-- Gen1Dex: the Pokédex LIST -- a party icon beside every entry, and three
-- views to read them in.
--
-- Returns a factory: factory(mod, DexData, C, Area) -> { new = function(game,
-- opts) }, which main.lua installs over the builtin "PokedexMenu" id.  Area
-- is area.lua's surface, or nil when it did not build: every row here carries
-- its species whether it has been discovered or not, and that is what lets A
-- on an undiscovered entry open AREA on the right POKéMON.
--
-- ------- the shape of the screen
--
--   rows 0-2    the header: which view you are in, and a pip per view
--   rows 3-14   six entries, the icon column ruled off from the names
--   rows 15-17  the footer: SEEN and OWN, for the whole dex
--
-- Six rows rather than the vanilla seven.  The vanilla list is a bare
-- 160x144 fill with nothing drawn on it but text, so all seven fit; boxing
-- the top and bottom costs three tile rows each and buys the body hard edges.
-- Six 16-pixel rows fill the 96 pixels between them exactly, which is the
-- same arithmetic the party pane in Gen1BillsBox runs on.
--
-- ------- the shape of a row
--
--   x 0-7     the cursor, on the row it is on
--   x 8-23    the POKéMON, 16x16, two tiles square
--   x 26      the rule: the icon column, ruled off
--   x 32-     "001 BULBASAUR"
--   x 150     the owned ball, in a column of its own
--
-- The ball sits in a FIXED column rather than one blank glyph after the name,
-- which is where the vanilla list puts it.  Two reasons: the name column has
-- to end somewhere for the rule to mean anything, and a marker that moves
-- with the length of the word before it cannot be scanned down -- a column of
-- balls answers "what do I still need" at a glance and a scatter of them
-- does not.
--
-- ------- why the icon sits on a tile boundary
--
-- An SGB palette zone is ADDRESSED in tiles (PaletteFX.zone), so an icon that
-- is not on a tile boundary cannot carry one, and a zone per row is what
-- gives every POKéMON on screen its own species colours at once -- where the
-- Game Boy could show four.  Move the icon a pixel and its colour goes with
-- the row above it.
--
-- ------- and why an undiscovered one is black
--
-- Not a palette zone -- a TINT.  PartyMenu.drawIcon never sets a colour of
-- its own, it draws in the caller's, and LÖVE multiplies the image by it: so
-- setColor(0,0,0,1) takes every pixel's RGB to zero and leaves its alpha
-- alone, which is a silhouette of the exact shape the icon draws, for free.
--
-- The palette route cannot do this job.  A zone of four blacks would blacken
-- a DMG icon, but an icon mod's authored full-colour art is re-blit UNSHADED
-- over the colourised pass (PaletteFX.markTrueColor / Renderer's
-- withTrueColor), so it would come back in colour underneath -- the entry you
-- have not met would be the only one on the screen in full colour.  A tint is
-- applied at draw time, before any of that, so it holds for both kinds of art
-- and needs to know about neither.  The matching half of the rule is below:
-- an undiscovered row asks for no species zone and marks no true-colour rect,
-- because both would repaint what the tint just blacked out.

return function(mod, DexData, C, Area)
  local Font = require("src.render.Font")
  local PaletteFX = require("src.render.PaletteFX")
  local PartyMenu = require("src.ui.PartyMenu")
  local Sprites = require("src.pokemon.Sprites")
  local Strings = require("src.core.Strings")
  local Theme = require("src.ui.Theme")

  -- ------- geometry, in whole tiles where a zone has to reach

  local ROWS = 6
  local ROW_H = 16
  local ROW_TOP = C.BODY_TOP             -- 24
  local CURSOR_X = 0
  local ICON_X = 8                       -- tile 1; the zone covers tiles 1-2
  local ICON = 16
  local RULE_X = 26                      -- the hairline the names start after
  local LABEL_X = 32
  local BALL_X, BALL_R = 150, 3.5
  local TEXT_DY = 4                      -- the glyph, centred on the icon

  -- A name is at most ten glyphs and the number three, so the longest label
  -- is fourteen -- 112 pixels, ending at 144, six clear of the ball column.
  local LABEL_GLYPHS = 14

  local VIEWS = DexData.MODES            -- num, alpha, caught

  -- ------- the icon
  --
  -- drawIcon wants a MON and this screen has a species: a dex row is a
  -- record, not a creature, and nothing in the save answers "what would one
  -- of these look like".  The stub is the smallest shape the icon path
  -- actually reads -- with `selected` false it never reaches hp or stats,
  -- which is the same reason Gen1BillsBox passes forceAlt for its box mons
  -- (a Gen 1 box mon has no stat block at all).
  local stubs = {}
  local function stubFor(species)
    local hit = stubs[species]
    if not hit then
      hit = { species = species, hp = 1, stats = { hp = 1 }, level = 1 }
      stubs[species] = hit
    end
    return hit
  end

  -- Does this species' icon carry colour a grey ramp cannot?  Only a mod's
  -- own image can: a built-in icon CLASS is baked through obpIcon, which
  -- flattens every pixel to a grey off its red channel, so it is never full
  -- colour whatever file it points at.  Read once per species and kept,
  -- because it is a property of the art and the art does not change.
  local colourCache = {}

  local function resolveIcon(game, species)
    local icons = game.data and game.data.icons
    if not icons then return nil, nil end
    local def = game.data.pokemon and game.data.pokemon[species]
    local entry = (icons.bySpecies and icons.bySpecies[species])
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
    local ok, hooked = pcall(Sprites.iconPath, game.data, stubFor(species),
                             path, { name = name })
    if ok then path = hooked end
    return name, path
  end

  local function fullColour(game, species)
    local hit = colourCache[species]
    if hit ~= nil then return hit end
    hit = false
    local name, path = resolveIcon(game, species)
    if path and not name then
      pcall(function()
        local data = require("src.render.Assets").imageData(path)
        local w, h = data:getDimensions()
        local drawn = h > ICON and ICON or h
        for y = 0, drawn - 1 do
          for x = 0, w - 1 do
            local r, g, b, a = data:getPixel(x, y)
            if a > 0 and (math.abs(r - g) > 0.02 or math.abs(g - b) > 0.02) then
              hit = { w = w > ICON and ICON or w, h = drawn }
              return
            end
          end
        end
      end)
    end
    colourCache[species] = hit
    return hit
  end

  -- One icon, in colour or blacked out.  `discovered` is the whole rule: a
  -- species you have seen wears its own art and asks for its own colours, one
  -- you have not is a black shape and asks for nothing.
  local function drawIcon(game, species, x, y, discovered)
    if not species then return end
    if discovered then
      C.white()
      pcall(PartyMenu.drawIcon, game, stubFor(species), x, y, false, 0, false)
      local rect = fullColour(game, species)
      if rect then
        pcall(PaletteFX.markTrueColor, x, y, rect.w, rect.h)
      end
    else
      -- the tint IS the silhouette; see the header
      C.black()
      pcall(PartyMenu.drawIcon, game, stubFor(species), x, y, false, 0, false)
    end
    C.white()
  end

  -- ------- colour
  --
  -- Base GRAYS rather than the vanilla list's BROWNMON, and for the reason
  -- Gen1BillsBox spells out: a named palette paints shade 1 a colour
  -- (MEWMON's is a salmon {239,156,107}), and everything this screen draws
  -- itself is meant to read as black line art.  Shade 3 is {0,0,0} in the
  -- grey ramp and in all 151 species palettes alike, so the chrome stays
  -- black under any zone and a species palette laid over a row reaches the
  -- POKéMON in it and nothing else.
  --
  -- SPECIES COLOURS off puts the vanilla brown back and asks for no zones,
  -- which is the whole of that option.
  local function palettesFor(screen, game)
    local ok, zones = pcall(function()
      if not C.option("species_colours", true) then
        return PaletteFX.wholeNamed(game.data, "BROWNMON")
      end
      local out = { PaletteFX.whole(PaletteFX.GRAYS) }
      for row = 1, screen.rows do
        local item = screen.items[screen.scroll + row]
        -- an undiscovered row is deliberately skipped: it is black by tint,
        -- and a species zone would colour the silhouette back in
        if item and item.species and item.seen
            and not fullColour(game, item.species) then
          local colors = PaletteFX.monPal(game.data, item.species)
          local ty = (ROW_TOP + (row - 1) * ROW_H) / 8
          local zone = colors
            and PaletteFX.zone(colors, ICON_X / 8, ty, ICON_X / 8 + 1, ty + 1)
          if zone then out[#out + 1] = zone end
        end
      end
      return out
    end)
    return ok and zones or nil
  end

  -- ------- drawing
  --
  -- A whole replacement for ListMenu:draw rather than a wrap around it: the
  -- vanilla row prints its label at x=16, which is where the icon now is, so
  -- there is no version of this that leaves that call in place.  Everything
  -- else about the list -- input, scrolling, the side menu, SELECT -- is
  -- still ListMenu's, and is not touched.

  local function activeView(self)
    for i, name in ipairs(VIEWS) do
      if name == self.dexMode() then return i end
    end
    return 1
  end

  local function drawHeader(self)
    C.headerBox()
    Font.draw(Strings(self.title), C.LEFT, C.HEADER_TEXT_Y)
    -- which of the three views, in the space a third word would not fit in
    if C.option("view_cycle", true) then
      local width = C.pipsWidth(#VIEWS)
      C.pips(C.RIGHT - width, C.HEADER_TEXT_Y + 2, #VIEWS, activeView(self))
    end
  end

  local function drawFooter(self)
    C.footerBox()
    if self.footer then Font.draw(self.footer, C.LEFT, C.FOOTER_TEXT_Y) end
    -- more below: the marker every other list uses, in the margin the counts
    -- leave free
    if self.scroll + self.rows < #self.items then
      Font.drawCode(Theme.moreArrow, C.RIGHT - 8, C.FOOTER_TEXT_Y)
    end
  end

  local function drawRow(self, row, item, i)
    local y = ROW_TOP + (row - 1) * ROW_H

    drawIcon(self.game, item.species, ICON_X, y, item.seen)

    C.black()
    -- the icon is two tiles tall and the glyphs are one, so the label sits on
    -- the icon's middle rather than on its top edge
    local textY = y + TEXT_DY
    Font.draw(C.truncate(item.label, LABEL_GLYPHS), LABEL_X, textY)

    if item.ball then
      local by = textY + 3
      love.graphics.circle("fill", BALL_X, by, BALL_R)
      C.white()
      love.graphics.rectangle("fill", BALL_X - BALL_R, by - 0.5, BALL_R * 2, 1)
      C.black()
      love.graphics.circle("fill", BALL_X, by, 1.2)
    end

    if i == self.index then
      Font.drawCode(Theme.cursor, CURSOR_X, textY)
    end
  end

  local function draw(self)
    C.clear()
    drawHeader(self)

    if #self.items == 0 then
      Font.draw(Strings("Nothing here."), LABEL_X, ROW_TOP + 32)
      drawFooter(self)
      C.white()
      return
    end

    for row = 1, self.rows do
      local i = self.scroll + row
      local item = self.items[i]
      if not item then break end
      drawRow(self, row, item, i)
    end

    -- The icon column, ruled off from the names.  One hairline the full
    -- height of the body, the way Gen1BillsBox rules its party pane off from
    -- its grid -- drawn last so a row's own drawing cannot break it.
    C.black()
    C.rule(RULE_X, ROW_TOP, 1, ROWS * ROW_H)

    drawFooter(self)
    C.white()
  end

  -- ------- the screen
  --
  -- Built by the VANILLA constructor and then re-dressed, which is what keeps
  -- the DATA / CRY / AREA / QUIT side menu, the cursor memory and the QUIT
  -- path exactly as they were: this mod has an opinion about how the list
  -- looks and which entries are in it, and none at all about what pressing A
  -- on one does.
  local List = {}

  function List.new(game, opts)
    local Vanilla = require("src.ui.PokedexMenu")
    local list = Vanilla.new(game, opts)

    -- Six rows, not the vanilla seven: the two boxes took a tile row each end.
    -- Set before the first rebuild, because the scroll clamp reads it.
    list.rows = ROWS
    list.wrap = C.option("wrap", true)          -- UP on the first row wraps
    list.keyRepeat = C.option("hold_scroll", true)

    local mode = "num"

    local function rebuild(prebuilt)
      local build = prebuilt
        or DexData.list(game.data, game.save.pokedex, mode)
      local current = list.items[list.index] and list.items[list.index].species
      list.title = DexData.MODE_LABELS[mode]
      -- fixed three-digit fields keep this at 17 glyphs, under the 18-column
      -- wrap a bare ListMenu footer goes through (engine #639)
      list.footer = Strings("SEEN %3d  OWN %3d", build.seen, build.owned)
      list.items = build.items
      list.index = 1
      list.scroll = 0
      if current then
        for i, item in ipairs(build.items) do
          if item.species == current then list.index = i break end
        end
      end
      -- the restored cursor can sit past the visible rows; clamp the scroll
      -- here so the frame drawn right after this shows the right page
      if list.index - list.scroll > list.rows then
        list.scroll = list.index - list.rows
      end
    end

    -- Rebuilt once on open even in the numbered view, because the items this
    -- mod draws carry `species` and `seen` on every row and the vanilla ones
    -- do not -- a blank row has to know which POKéMON it is not showing you.
    rebuild()

    list.onSelectKey = function()
      if not C.option("view_cycle", true) then return end
      local nextMode = DexData.NEXT_MODE[mode]
      local build = DexData.list(game.data, game.save.pokedex, nextMode)
      -- an empty filtered view would strand SELECT: ListMenu returns before
      -- onSelectKey when the list is empty, so there would be no way back
      if #build.items == 0 then return end
      mode = nextMode
      rebuild(build)
    end

    list.draw = draw
    list.sgbPalettes = palettesFor

    -- for the suite, and for anything that wants to know what is on screen
    list.dexMode = function() return mode end

    -- A on an entry you have never met.  Last, so what it wraps is the
    -- handler this screen is really going to run -- the vanilla one, with
    -- everything above still in place.
    if Area then pcall(Area.wireList, game, list, opts) end

    return list
  end

  return { new = List.new }
end
