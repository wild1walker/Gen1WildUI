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
  function C.shorten(text, pixels)
    text = tostring(text or "")
    if C.width(text) <= pixels then return text end
    local ok, spans = pcall(Font.split, text)
    if not ok or #spans == 0 then return text end
    for n = #spans - 1, 1, -1 do
      local cut = text:sub(1, spans[n].to):gsub("[%s%-]+$", "") .. "."
      if C.width(cut) <= pixels then return cut end
    end
    return "."
  end

  function C.rightAlign(text, endX)
    return endX - C.width(text)
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
  function C.drawLabel(label, x, y, width)
    C.black()
    if label.codes then
      local w = C.codesWidth(label.codes)
      C.drawCodes(label.codes, x + math.max(0, math.floor((width - w) / 2)), y)
      return
    end
    local text = C.shorten(label.text, width)
    Font.draw(text, x + math.max(0, math.floor((width - C.width(text)) / 2)), y)
  end

  function C.drawHand(code, x, y)
    C.black()
    Font.drawCode(code, x, y)
  end

  return C
end
