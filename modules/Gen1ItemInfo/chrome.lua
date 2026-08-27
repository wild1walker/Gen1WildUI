-- Gen1ItemInfo: the drawing kit.
--
-- Returns a factory: factory(mod) -> a table of helpers.  The same kit
-- Gen1Dex and Gen1Party carry, trimmed to the parts these screens use and
-- with the one geometry they do not share -- a six-tile text box at the
-- bottom instead of a three-tile footer.  Copied rather than depended on,
-- for the reason Gen1Party gives for copying it from Gen1Dex: a screen that
-- refuses to draw until you also install a Pokédex mod is a worse trade than
-- sixty lines of duplication.  Anything changed here should be changed there.
--
-- ------- the shape every screen in this mod has
--
--   rows 0-2    a header box: what you are looking at, and the number that
--               belongs to it -- money at a mart, stacks used in a PC
--   rows 3-11   the list
--   rows 12-17  the game's own bottom text box: the clerk, the machine, and
--               the description of whatever the cursor is on
--
-- The bottom box is where it has always been.  That is deliberate and it is
-- the whole reason the descriptions fit: the mart already prints its prices
-- and refusals there, the PC already prints "Withdrew POTION.", and a player
-- reads the bottom of a Gen 1 screen for sentences.  Putting the description
-- anywhere else would have made a second place to look.
--
-- What changes above it is the header.  Vanilla floats a nine-tile money box
-- in the top right corner over a list with no title on it and no right
-- margin; this is one box across the width with the title in it, the number
-- right-aligned off the edge, and the list ruled to the same margins the rest
-- of the suite keeps.
--
-- ------- everything here is shade 3
--
-- Which is {0,0,0} in the grey ramp and in all 151 species palettes alike, so
-- the chrome stays black under any zone.  Shade 1 is the trap: MEWMON paints
-- it {239,156,107}, which is how a grey rule comes out orange -- and MEWMON
-- is exactly the palette ListMenu asks for (SET_PAL_GENERIC).

return function(mod)
  local Font = mod.ui.Font
  local Theme = mod.ui.Theme

  local C = {}

  C.BLACK = { 0, 0, 0 }

  C.HEADER_TH = 3               -- rows 0-2
  C.HEADER_TEXT_Y = 8
  C.BOX_TY, C.BOX_TH = 12, 6    -- the standard bottom text box
  C.BODY_TOP = 24               -- first pixel row under the header box
  C.BODY_BOTTOM = 95            -- last pixel row before the text box

  -- The margins every screen in the set keeps.  The vanilla mart row has
  -- none: its price column ends on 160, the last pixel of the screen, which
  -- is what makes a ¥2100 look clipped rather than placed.
  C.LEFT, C.RIGHT = 8, 152
  C.CURSOR_X = 8
  C.LABEL_X = 16

  -- ------- and the margins a row with an icon keeps instead
  --
  -- The icon takes the two tiles after the cursor and the label starts a tile
  -- after it, which is the clearance the cursor already has on the other
  -- side.  What that costs is the price column: a name from 40 has 112 pixels
  -- to the right margin, and a ¥2100 and the tile between them take fifty of
  -- them, which leaves eight glyphs and cuts SUPER POTION in half.
  --
  -- So a row with an icon drops its right-hand number to the row's second
  -- line.  There is one -- rows are sixteen pixels apart and a glyph is
  -- eight -- and it is where the game itself puts the number when a list has
  -- an icon-sized gap on the left: the bag prints a name and then its count
  -- underneath (home/list_menu.asm, and ListMenu's own item box).  Nothing is
  -- truncated on any row of any of these screens as a result, which was not
  -- true before the icons and is the point.
  C.ICON_X = 16
  C.ICON_LABEL_X = 40
  C.RIGHT_SUB_Y = 8

  -- And four pixels up, so the picture is centred on the NAME rather than on
  -- the row.
  --
  -- A row is sixteen pixels and so is an icon, so an icon drawn at the row's
  -- own y fills it exactly -- and looks wrong, which is the thing worth
  -- writing down.  The row holds two lines: the name on the top eight pixels
  -- and the number underneath.  A glyph inks rows 0 to 6 of its cell, so the
  -- name's ink is centred on y + 3 while the icon's is centred on y + 7.5,
  -- and the word reads as floating above its own picture.
  --
  -- What a reader pairs is the name and the icon, not the whole cell and the
  -- icon, so the icon is centred on the name: four pixels up puts the two
  -- centres within half a pixel of each other.  Four and not five, which
  -- would be the exact half: the top row of the mart's list starts at
  -- BODY_TOP + 4 and five would put its icon on BODY_TOP - 1, which is the
  -- header box's bottom border.
  --
  -- Icons stay sixteen apart, so the column shifts as a whole and no two of
  -- them come any closer together.
  C.ICON_DY = -4

  -- ------- and the rule between the two columns
  --
  -- The icon and the name are two columns of different kinds of thing, and
  -- the tile between them was doing the whole job of saying so.  A one-pixel
  -- black rule down the middle of that tile says it properly: three pixels of
  -- air on the icon's side, four on the name's, and a picture that can no
  -- longer read as the first letter of the word beside it.
  --
  -- Drawn a row at a time, the full sixteen pixels of the row, so consecutive
  -- rows join into one continuous line and the line stops where the list
  -- does.  A pocket of two items gets two rows of rule, not a rule down an
  -- empty half-screen.
  --
  -- Every row gets one, CANCEL included: it is a column divider, not a
  -- decoration on an item, and a rule with gaps in it where a row happens to
  -- have no picture reads as damage.
  C.ICON_W = 16
  C.ICON_RULE_X = C.ICON_X + C.ICON_W + 3

  -- Four rows of 16 pixels in the 72 the body has, centred in it: the same
  -- four the vanilla mart and PC lists show, at the same pitch, so a player
  -- who knows where the fourth row is still finds it there.
  C.ROWS = 4
  C.ROW_STEP = 16
  C.ROW_TOP = C.BODY_TOP + 4

  function C.ink(shade)
    love.graphics.setColor(shade[1], shade[2], shade[3], 1)
  end

  function C.black() C.ink(C.BLACK) end

  function C.white() love.graphics.setColor(1, 1, 1, 1) end

  function C.rowY(row)
    return C.ROW_TOP + (row - 1) * C.ROW_STEP
  end

  -- The column rule beside one row.  Black, one pixel, the row's full height.
  function C.iconRule(y)
    C.black()
    love.graphics.rectangle("fill", C.ICON_RULE_X, y, 1, C.ROW_STEP)
  end

  -- Right-align a string to a pixel column, and hand back where it starts so
  -- the caller can check what it is about to collide with.
  function C.rightAlign(text, endX)
    local ok, w = pcall(Font.width, text)
    return endX - (ok and w or 0)
  end

  -- Trim to a PIXEL budget rather than a character count: a font mod can ship
  -- variable-width glyphs, and Font.width is what measures them.  Cut on a
  -- glyph boundary, never a byte one -- NIDORAN's ♂/♀ and POKé's é are one
  -- glyph across several bytes, so a plain sub() can slice a character in
  -- half -- and mark the cut with a trailing '.', which is the convention
  -- ListMenu's own fitLabel uses.
  function C.fit(text, budget)
    text = tostring(text or "")
    local ok, spans = pcall(Font.split, text)
    if not ok then return text end
    local fitted = Font.spansFitting(spans, budget)
    if fitted >= #spans then return text end
    fitted = math.max(fitted, 1)
    local out = {}
    for i = 1, fitted - 1 do
      out[#out + 1] = text:sub(spans[i].from, spans[i].to)
    end
    return table.concat(out) .. "."
  end

  -- ------- the boxes
  --
  -- Drawn black-then-black around the call because Font.drawBox fills its
  -- interior with the CALLER's colour rules but draws its border glyphs in
  -- whatever colour is current, and the glyph pages are black on transparent.
  -- Setting black before the call is what keeps a leaked white from painting
  -- the next label white on white.

  function C.clear()
    C.white()
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    C.black()
  end

  -- The header: a title on the left, and optionally a number right-aligned
  -- against the right margin.  Both sit on the box's one interior row.
  function C.header(title, right)
    C.black()
    Font.drawBox(0, 0, 20, C.HEADER_TH)
    C.black()
    if title then Font.draw(title, C.LEFT, C.HEADER_TEXT_Y) end
    if right then
      Font.draw(right, C.rightAlign(right, C.RIGHT), C.HEADER_TEXT_Y)
    end
  end

  -- The bottom text box, with the last two lines of whatever it was given.
  --
  -- Last two, not first two, and that is not an oversight: it is what the
  -- GB's own scrolled box shows, it is what ListMenu already does with a
  -- mart's three-line "%s?\nThat will be\n¥%d. OK?", and matching it is what
  -- keeps a clerk's line reading the way it always has.  It is also the rule
  -- descriptions.lua is written against -- two lines, eighteen glyphs each,
  -- so a description never has a first line to lose.
  function C.textBox(text)
    C.black()
    Font.drawBox(0, C.BOX_TY, 20, C.BOX_TH)
    C.black()
    if not text then return end
    local flat = {}
    for _, page in ipairs(mod.ui.TextBox.paginate(text)) do
      for _, line in ipairs(page) do flat[#flat + 1] = line end
    end
    local y = 112
    for i = math.max(1, #flat - 1), #flat do
      Font.draw(flat[i], C.LEFT, y)
      y = y + 16
    end
  end

  -- ------- the cursor, and the two marks that say there is more
  --
  -- The filled arrow is the engine's own ($ED, and Theme.cursor so a theme
  -- mod's replacement is honoured).  The up and down marks are drawn rather
  -- than printed: the charmap has a down arrow ($EE) and no up twin of it, so
  -- a printed pair would be one glyph and one triangle, sitting at different
  -- heights inside their cells.  Two triangles agree with each other.
  local MARK_W, MARK_H = 7, 4

  function C.cursor(y)
    Font.drawCode(Theme.cursor, C.CURSOR_X, y)
  end

  function C.mark(x, y, up)
    for i = 0, MARK_H - 1 do
      local span = MARK_W - i * 2
      local row = up and (y + MARK_H - 1 - i) or (y + i)
      love.graphics.rectangle("fill", x + i, row, span, 1)
    end
  end

  -- Both marks live in the right margin, clear of the price column: the top
  -- one against the header box's underside, the bottom one against the text
  -- box's top edge.
  C.MARK_X = C.RIGHT + 1
  C.MARK_UP_Y = C.BODY_TOP + 2
  C.MARK_DOWN_Y = C.BODY_BOTTOM - MARK_H - 1

  return C
end
