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

  -- One row of the tile font, which is also the row a button's label sits on.
  C.ROW = 8

  -- The small face's real height, for the rectangle a coloured label claims.
  -- Falls back to a tile row, which is what the face is standing in for.
  function C.faceHeight(small)
    local font = type(small) == "table" and small.font or nil
    if font and font.getHeight then
      local ok, h = pcall(font.getHeight, font)
      if ok and type(h) == "number" and h > 0 then return h end
    end
    return C.ROW
  end

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

  -- ------- the type's colour, in the letters
  --
  -- A tile glyph is black pixels on transparent, so setting a colour does
  -- nothing to it: black times any colour is still black
  -- (src/render/Font.lua:532).  The way to colour the letters and keep the
  -- game's own font is a shader that throws the glyph's RGB away and keeps
  -- only its alpha -- the glyph becomes a stencil, and the stencil is filled
  -- with the type's colour.
  --
  -- Guarded and optional, the way the engine guards its own shaders
  -- (src/render/GbcPalette.lua): a host without newShader draws black text
  -- and loses the colour, which is the same picture this mod drew before.
  local TINT = [[
    extern vec3 tint;
    vec4 effect(vec4 colour, Image tex, vec2 tc, vec2 sc) {
      return vec4(tint, Texel(tex, tc).a * colour.a);
    }
  ]]
  local tintShader, tintTried

  local function tinter()
    if tintTried then return tintShader end
    tintTried = true
    if not (love.graphics and love.graphics.newShader) then return nil end
    local ok, made = pcall(love.graphics.newShader, TINT)
    tintShader = ok and made or nil
    return tintShader
  end

  -- These are darker than the familiar type colours, because they are the
  -- LETTERS now rather than a field behind them: ICE and ELECTRIC at their
  -- usual brightness are close to invisible as text on a white box.
  local TYPE_INK = {
    NORMAL   = { 0x6D, 0x6D, 0x4E }, FIRE     = { 0xB4, 0x44, 0x1A },
    WATER    = { 0x2F, 0x4F, 0xB8 }, ELECTRIC = { 0x8A, 0x6D, 0x00 },
    GRASS    = { 0x2E, 0x7D, 0x32 }, ICE      = { 0x17, 0x70, 0x7A },
    FIGHTING = { 0xA0, 0x2C, 0x22 }, POISON   = { 0x7A, 0x2A, 0x7A },
    GROUND   = { 0x8A, 0x6A, 0x20 }, FLYING   = { 0x5A, 0x4F, 0xB0 },
    PSYCHIC  = { 0xB0, 0x2A, 0x55 }, BUG      = { 0x5E, 0x6B, 0x12 },
    ROCK     = { 0x7A, 0x64, 0x20 }, GHOST    = { 0x4A, 0x36, 0x70 },
    DRAGON   = { 0x3F, 0x1F, 0xB0 },
  }

  -- The id, not the printed name: PSYCHIC_TYPE prints PSYCHIC, and a
  -- translation prints something else again, so keying on what is drawn would
  -- lose the colour in every language but this one.  A type this does not
  -- know -- a mod's -- has no ink, and its text stays black.
  -- TYPE_INK is written in bytes, because that is how a colour is read and
  -- how every table it was copied from writes one.  LOVE wants 0..1, and a
  -- byte handed over unconverted is not a wrong colour, it is white: 180
  -- clamps to 1 the same as 26 does.
  local function unit(shade)
    return shade[1] / 255, shade[2] / 255, shade[3] / 255
  end

  -- Set the current colour from one of those byte triples.  Only the TTF
  -- face needs this -- a tile glyph ignores the colour entirely and goes
  -- through C.inked instead.
  function C.inkBytes(shade) love.graphics.setColor(unit(shade)) end

  function C.typeInk(id)
    if type(id) ~= "string" then return nil end
    return TYPE_INK[(id:upper():gsub("_TYPE$", ""))]
  end

  -- ------- the same letters on a DARK box
  --
  -- A type ink is a real RGB colour drawn onto the canvas, and it survived
  -- because a classic battle hands the renderer NO ZONE LIST: with nothing to
  -- colorize, `Renderer:blitCanvas` blits the canvas raw and the letters keep
  -- the colour this file gave them.
  --
  -- UI THEME = DARK ends that.  The theme paints a panel over every box a
  -- battle draws -- which is how the command grid goes dark at all -- and a
  -- panel is a four-shade palette.  Once one covers these letters they are
  -- read as four DMG shades off their RED channel and repainted out of that
  -- palette, so RAZOR LEAF's green and VINE WHIP's green and TACKLE's olive
  -- all come out as whatever shade their red channel happened to land on.
  -- Grey letters, in four slightly different greys.
  --
  -- No palette can carry an arbitrary colour, so the only way to keep one is
  -- to leave the palette pass: `markTrueColor` claims the letters' rectangle
  -- and the renderer re-blits it raw over the shaded pass.  Raw means raw,
  -- which is the whole of why this is three steps rather than one:
  --
  --   1. paint the theme's matte into the rectangle, or the raw re-blit
  --      brings back the WHITE the box cleared to and puts a white label
  --      plate on a black button;
  --   2. draw the letters at FULL STRENGTH -- the table above is deliberately
  --      dark because it was written for black ink on a white box, and those
  --      same inks on a black button are both unreadable and drab;
  --   3. mark the rectangle, so what was just drawn is what is shown.
  --
  -- ADVANCED only, and that is not a limitation to apologise for: a mark is
  -- discarded outside it (`PaletteFX.honorsTrueColor`), so painting the matte
  -- there would put a black plate through the shade pass and make a hole in
  -- the button.  Elsewhere the letters go through the palette as they do
  -- today, which is legible -- just not coloured.
  -- Wound up to full strength, hue untouched.
  --
  -- 0.29.3 mixed these halfway to white, which made them legible and drab:
  -- a GRASS move came out the colour of sage rather than of grass.  Mixing
  -- toward white is the wrong move because it takes the SATURATION out --
  -- every ink converges on the same pale wash, which is exactly the
  -- complaint.
  --
  -- Scaling to the brightest channel does the opposite: the ratios between
  -- the three channels are what the hue IS, so multiplying all three by the
  -- same gain leaves the hue exactly where it was and spends the headroom on
  -- vividness instead.  GRASS's 46/125/50 becomes 94/255/102 -- the green of
  -- the type charts rather than a tint of it -- and the dark end of the
  -- table gains the most, which is where it was needed.
  local function vivid(shade)
    local peak = math.max(shade[1], shade[2], shade[3])
    if peak <= 0 then return { 255, 255, 255 } end
    local gain = 255 / peak
    return { shade[1] * gain, shade[2] * gain, shade[3] * gain }
  end

  -- The colour to lay under the letters, or nil for "nothing to do here".
  -- Three ways to answer nil and each is a whole build that pays nothing: no
  -- theme, LIGHT, or a mode that discards the mark anyway.
  local function mattePaint()
    local theme = type(mod.theme) == "function" and mod.theme() or nil
    if type(theme) ~= "table" or type(theme.read) ~= "function" then
      return nil
    end
    if theme.read() ~= "dark" or type(theme.matte) ~= "function" then
      return nil
    end
    local okFX, PaletteFX = pcall(require, "src.render.PaletteFX")
    if not okFX or type(PaletteFX) ~= "table" then return nil end
    if type(PaletteFX.honorsTrueColor) == "function"
        and not PaletteFX.honorsTrueColor() then
      return nil
    end
    local colour = theme.matte()
    if type(colour) ~= "table" or #colour < 3 then return nil end
    return colour, PaletteFX
  end

  -- Claim `rect` for a coloured label: paint it, and hand back the ink to use
  -- and the call that marks it once the letters are down.  nil, nil when this
  -- build has nothing to claim, and every caller then draws as it always did.
  function C.onDark(shade, rect)
    if not (shade and type(rect) == "table"
            and (rect.w or 0) > 0 and (rect.h or 0) > 0) then
      return nil
    end
    local colour, PaletteFX = mattePaint()
    if not colour then return nil end
    love.graphics.setColor(colour[1] / 255, colour[2] / 255,
                           colour[3] / 255, 1)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    C.white()
    return vivid(shade), function()
      if type(PaletteFX.markTrueColor) == "function" then
        PaletteFX.markTrueColor(rect.x, rect.y, rect.w, rect.h)
      end
    end
  end

  -- Run `draw` with its glyphs stencilled in `shade`.  No shade, or no
  -- shader to do it with, and it draws in black exactly as before.
  function C.inked(shade, draw)
    local shader = shade and tinter()
    if not shader then C.black() return draw() end
    local prev = love.graphics.getShader and love.graphics.getShader() or nil
    love.graphics.setShader(shader)
    pcall(shader.send, shader, "tint", { unit(shade) })
    C.white()                     -- the shader supplies the colour, not this
    local ok, err = pcall(draw)
    love.graphics.setShader(prev)
    C.black()
    if not ok then error(err, 0) end
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
      local lx = x + math.max(0, math.floor((width - w) / 2))
      -- a TTF glyph really is drawn in the current colour, so the small face
      -- needs no shader: setting the ink is enough
      local sy = y + (small.yOffset or 0)
      local ink, mark = label.ink, nil
      local darkInk, done = C.onDark(ink, { x = lx, y = sy, w = w,
                                            h = C.faceHeight(small) })
      if darkInk then ink, mark = darkInk, done end
      if ink then C.inkBytes(ink) else C.black() end
      local prev = love.graphics.getFont and love.graphics.getFont()
      love.graphics.setFont(small.font)
      love.graphics.print(tostring(text), lx, sy)
      if prev then love.graphics.setFont(prev) end
      C.black()
      if mark then mark() end
      return
    end
    local text = C.shorten(label.text, width)
    local w = C.width(text)
    local lx = x + math.max(0, math.floor((width - w) / 2))
    local ink, mark = label.ink, nil
    local darkInk, done = C.onDark(ink, { x = lx, y = y, w = w, h = C.ROW })
    if darkInk then ink, mark = darkInk, done end
    C.inked(ink, function() Font.draw(text, lx, y) end)
    if mark then mark() end
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
