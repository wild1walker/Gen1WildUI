-- Gen1BattleUI: the drawing kit.
--
-- Returns a factory: factory(mod) -> a table of helpers.  The same shape the
-- rest of the set carries (Gen1Party, Gen1Dex), trimmed to what a battle
-- menu needs and given the two things only this mod wants: a box split into
-- four cells, and a label that knows how wide its cell is.
--
-- ------- everything here is a Game Boy text box
--
-- No new chrome idiom is introduced.  A button is Font.drawBox -- the same
-- call, the same border glyphs, the same white interior the game's own text
-- boxes are made of -- so a skin or a font mod that redraws the border
-- redraws these buttons with it, and nothing here has to know it happened.
--
-- That decision is also what fixes the sizes.  Font.drawBox spends its first
-- and last tile row on the border and leaves the rest as interior, so the
-- smallest box that can hold a line of text is three tile rows for one row of
-- 8-pixel glyphs.  Two rows of buttons is six tile rows, which is exactly the
-- six the classic layout's bottom strip has and one more than the wide
-- layout's five -- which is why the two layouts build their grid differently
-- and share everything else.  See grid.lua.
--
-- ------- everything here is shade 3
--
-- {0,0,0} in the grey ramp and in all 151 species palettes alike, so the
-- chrome stays black under any zone.  Set before every Font call, not once:
-- Font.drawBox fills its interior white and restores the caller's colour, and
-- a leaked white prints the next label white on white wherever the font is a
-- TTF rather than a tile page.

return function(mod)
  local Font = require("src.render.Font")

  local C = {}

  C.BLACK = { 0, 0, 0 }

  -- The filled hand and the hollow one, taken from the engine's own cursor
  -- constants rather than written out here: Theme is where field.theme
  -- restyles every menu's cursor at once, so a skin that redraws the arrow
  -- redraws these with it.  The literals are the fallback for an engine with
  -- no Theme to ask -- they are what Theme itself defaults to
  -- (charmap.asm $ED and $EC).
  local ok, Theme = pcall(require, "src.ui.Theme")
  C.HAND = ok and Theme and Theme.cursor or 0xED
  C.SWAP = ok and Theme and Theme.cursorHollow or 0xEC

  -- <PK> and <MN>: one word the font has no letters for, so PKMN is a pair
  -- of glyph codes everywhere the other three commands are a string.
  C.PKMN = { 0xE1, 0xE2 }

  function C.ink(shade)
    love.graphics.setColor(shade[1], shade[2], shade[3], 1)
  end

  function C.black() C.ink(C.BLACK) end

  function C.white() love.graphics.setColor(1, 1, 1, 1) end

  function C.option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  -- ------- measuring
  --
  -- Through the font's own advances rather than by counting bytes: a page may
  -- set an advance of its own, a TTF page answers with real metrics, and
  -- NIDORAN's male and female signs are one glyph across several bytes.

  function C.width(text)
    local ok, w = pcall(Font.width, text)
    return ok and w or (#tostring(text or "") * 8)
  end

  function C.advance(code)
    local ok, w = pcall(Font.advanceOf, code)
    return ok and w or 8
  end

  function C.codesWidth(codes)
    local w = 0
    for _, code in ipairs(codes or {}) do w = w + C.advance(code) end
    return w
  end

  -- Cut to a pixel budget with a trailing '.', the way the wide layout's own
  -- fitName does, and on a GLYPH boundary rather than a byte one.  The
  -- trailing space or hyphen goes with the cut: THROW ROCK reading "THROW ."
  -- is a worse seven glyphs than "THROW.".
  -- `measure` is how wide the face in question draws a string, so the same
  -- cutting rule serves the tile font and the small one.
  function C.shortenWith(measure, text, pixels)
    text = tostring(text or "")
    if measure(text) <= pixels then return text end
    local ok, spans = pcall(Font.split, text)
    if not ok or #spans == 0 then return text end
    for n = #spans - 1, 1, -1 do
      local cut = text:sub(1, spans[n].to):gsub("[%s%-]+$", "") .. "."
      if measure(cut) <= pixels then return cut end
    end
    return "."
  end

  function C.shorten(text, pixels)
    return C.shortenWith(C.width, text, pixels)
  end

  function C.rightAlign(text, endX)
    return endX - C.width(text)
  end

  -- ------- the type's colour
  --
  -- Behind the word, not in it.  A tile glyph is black on transparent and
  -- comes out black whatever colour is set (src/render/Font.lua:532), so the
  -- type CANNOT be printed in its own colour while it is the game's own font
  -- -- the only way to tint the letters is to stop using that font for them.
  -- A filled chip under the black word colours the same information, keeps
  -- the tile font, and is the shape a type badge has anyway.
  --
  -- These are the familiar type colours rather than darker ones, because the
  -- word on top is black: mid-light is what black reads on.
  local TYPE_CHIP = {
    NORMAL   = { 0xA8, 0xA8, 0x78 }, FIRE     = { 0xF0, 0x80, 0x30 },
    WATER    = { 0x68, 0x90, 0xF0 }, ELECTRIC = { 0xF8, 0xD0, 0x30 },
    GRASS    = { 0x78, 0xC8, 0x50 }, ICE      = { 0x98, 0xD8, 0xD8 },
    FIGHTING = { 0xC0, 0x70, 0x60 }, POISON   = { 0xA0, 0x40, 0xA0 },
    GROUND   = { 0xE0, 0xC0, 0x68 }, FLYING   = { 0xA8, 0x90, 0xF0 },
    PSYCHIC  = { 0xF8, 0x58, 0x88 }, BUG      = { 0xA8, 0xB8, 0x20 },
    ROCK     = { 0xB8, 0xA0, 0x38 }, GHOST    = { 0xA0, 0x90, 0xC0 },
    DRAGON   = { 0xA0, 0x80, 0xF8 },
  }

  -- The id, not the printed name: PSYCHIC_TYPE prints PSYCHIC, and a
  -- translation prints something else again, so keying on what is drawn would
  -- lose the colour in every language but this one.  A type this does not
  -- know -- a mod's -- simply has no chip, and the word stays as it was.
  function C.typeChip(id)
    if type(id) ~= "string" then return nil end
    return TYPE_CHIP[(id:upper():gsub("_TYPE$", ""))]
  end

  function C.fill(shade, x, y, w, h)
    love.graphics.setColor(shade[1] / 255, shade[2] / 255, shade[3] / 255, 1)
    love.graphics.rectangle("fill", x, y, w, h)
    C.black()
  end

  -- ------- the small face, for move names only
  --
  -- The tile font is eight pixels a glyph and cannot be anything else: it is
  -- a tile sheet.  Two columns inside 160 pixels leave a cell seven of them
  -- and Gen 1's longest move names are twelve, so in the game's own font a
  -- 2x2 grid CANNOT print a move name whole.  That is arithmetic about an
  -- 8x8 sheet, not a layout that could be tuned into fitting.
  --
  -- The engine ships exactly one other face: Plain Pixel, the TTF its
  -- translation mode renders through (Font.PLAINPIXEL, CC-BY 4.0, Douglas
  -- Vautour).  Its advance is narrower than eight, so the same cell holds
  -- more of it.  Switching the engine's own TTF mode on is not on the table
  -- -- that is a whole-game font swap, and a battle mod has no business
  -- making one -- so the face is loaded here and used for move names alone.
  --
  -- The size is chosen rather than fixed: the largest one whose twelve
  -- glyphs still fit wins.  A cell that changes width, a font whose metrics
  -- differ, a host that measures differently -- each resizes it instead of
  -- overflowing it.
  local LONGEST = 12          -- SELFDESTRUCT, THUNDERSHOCK, QUICK ATTACK
  local WIDEST = ("W"):rep(LONGEST)
  local smallCache = {}

  function C.small(width)
    if smallCache[width] ~= nil then return smallCache[width] or nil end
    smallCache[width] = false
    local path = Font.PLAINPIXEL or "assets/fonts/plainpixel/PlainPixel-Regular.ttf"
    for size = 15, 8, -1 do
      -- the engine's own call: a pixel-exact 1x rasterization, so the face
      -- lands on the same grid the rest of the frame is drawn on
      local ok, obj = pcall(love.graphics.newFont, path, size, "mono", 1)
      if ok and obj then
        local measured, w = pcall(obj.getWidth, obj, WIDEST)
        if measured and type(w) == "number" and w <= width then
          pcall(function() obj:setFilter("nearest", "nearest") end)
          -- The tile font's baseline sits on row 7 of its 8px cell, so
          -- anchoring this one to the same row is what keeps a small label
          -- and a tile label on one line (src/render/Font.lua's yOffset).
          local base = obj.getBaseline and select(2, pcall(obj.getBaseline, obj))
          local y = (type(base) == "number" and (7 - base))
                    or (obj.getHeight and (8 - obj:getHeight())) or 0
          smallCache[width] = { font = obj, yOffset = y, size = size }
          break
        end
      end
    end
    return smallCache[width] or nil
  end

  function C.smallWidth(small, text)
    local ok, w = pcall(small.font.getWidth, small.font, tostring(text or ""))
    return ok and w or 0
  end

  -- Unlike a tile glyph, a TTF glyph really is drawn in the current colour,
  -- so black is set here rather than assumed.
  function C.drawSmall(small, text, x, y)
    C.black()
    local prev = love.graphics.getFont and love.graphics.getFont()
    love.graphics.setFont(small.font)
    love.graphics.print(tostring(text or ""), x, y + small.yOffset)
    if prev then love.graphics.setFont(prev) end
  end

  -- ------- drawing

  function C.drawCodes(codes, x, y)
    local pen = x
    for _, code in ipairs(codes or {}) do
      Font.drawCode(code, pen, y)
      pen = pen + C.advance(code)
    end
  end

  -- Black around the call, not just before it: drawBox restores whatever
  -- colour the caller held, and the caller here is the overlay hook, which is
  -- handed white.
  function C.box(tx, ty, tw, th)
    C.black()
    Font.drawBox(tx, ty, tw, th)
    C.black()
  end

  -- Split a box into a 2x2 of cells, ruled with the box's OWN border glyphs
  -- so the divider is whatever the border is -- a skin that redraws the frame
  -- redraws the rules with it.
  --
  -- th must be odd, so that the horizontal rule lands on the middle interior
  -- row and leaves one text row above it and one below.  The rules cross at
  -- one cell; the horizontal one has it, because a broken vertical reads as a
  -- divider and a broken horizontal reads as a mistake.
  function C.quarter(tx, ty, tw, th, dividerCol)
    C.black()
    local B = Font.BORDER
    local midRow = ty + math.floor(th / 2)
    for i = 1, tw - 2 do
      Font.drawCode(B.h, (tx + i) * 8, midRow * 8)
    end
    for j = 1, th - 2 do
      local row = ty + j
      if row ~= midRow then
        Font.drawCode(B.v, dividerCol * 8, row * 8)
      end
    end
  end

  -- One button's label, centred in the pixels the cell has left after the
  -- hand's column.  `label` is { text = "FIGHT" } or { codes = C.PKMN }.
  --
  -- `small` is optional: the face from C.small, used when the caller has
  -- decided this grid's labels do not fit the game's own.  A glyph-pair
  -- label is never small -- <PK><MN> exists only as tiles.
  function C.drawLabel(label, x, y, width, small)
    C.black()
    if label.codes then
      local w = C.codesWidth(label.codes)
      C.drawCodes(label.codes, x + math.max(0, math.floor((width - w) / 2)), y)
      return
    end
    if small then
      local text = C.shortenWith(function(t) return C.smallWidth(small, t) end,
                                 label.text, width)
      local w = C.smallWidth(small, text)
      C.drawSmall(small, text, x + math.max(0, math.floor((width - w) / 2)), y)
      return
    end
    local text = C.shorten(label.text, width)
    Font.draw(text, x + math.max(0, math.floor((width - C.width(text)) / 2)), y)
  end

  -- True when this face would print `text` whole in `width`, which is the
  -- question a grid asks before deciding to use it at all.
  function C.smallFits(small, text, width)
    return C.smallWidth(small, text) <= width
  end

  function C.drawHand(code, x, y)
    C.black()
    Font.drawCode(code, x, y)
  end

  return C
end
