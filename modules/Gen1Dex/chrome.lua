-- Gen1Dex: the parts both screens draw the same way.
--
-- Returns a factory: factory(mod) -> a table of helpers.  Shared rather than
-- duplicated because the two screens have to agree: a header box on the list
-- that sits a pixel off the one on the entry reads as two mods, not one, and
-- the whole argument for the frame is that everything in this set is drawn
-- the same way.
--
-- ------- the shape every screen in this mod has
--
--   rows 0-2    a header box: what you are looking at
--   rows 3-14   the screen
--   rows 15-17  a footer box: what you can do about it
--
-- 96 pixels of body between them, which is a whole number of 16-pixel rows
-- (six) and of 12-pixel rows (eight).  Both boxes are three tiles because
-- Font.drawBox spends the first and last on its border and leaves one row of
-- interior: 24 pixels of box for 8 pixels of text is what a Game Boy text box
-- costs, and paying it twice is what buys the body its hard edges.
--
-- ------- everything here is shade 3
--
-- Which is {0,0,0} in the grey ramp and in all 151 species palettes alike, so
-- the chrome stays black under any zone and a species palette laid over a
-- POKeMON reaches the POKeMON and nothing else.  Shade 1 is the trap: MEWMON
-- paints it {239,156,107}, which is how a grey rule comes out orange.

return function(mod)
  local Font = require("src.render.Font")

  local C = {}

  C.BLACK = { 0, 0, 0 }
  C.HEADER_TH = 3
  C.FOOTER_TY = 15
  C.HEADER_TEXT_Y = 8
  C.FOOTER_TEXT_Y = 128
  C.BODY_TOP = 24               -- first pixel row under the header box
  C.BODY_BOTTOM = 119           -- last pixel row before the footer box
  C.LEFT, C.RIGHT = 8, 152      -- the text margins, on every screen

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

  function C.rule(x, y, w, h)
    love.graphics.rectangle("fill", x, y, w, h or 1)
  end

  -- Cut on a GLYPH boundary, not a byte one: Font.split hands back a span per
  -- glyph with its byte range, and NIDORAN's ♂/♀ is one glyph across several
  -- bytes, so a plain sub() can slice a character in half.
  function C.truncate(text, glyphs)
    local ok, spans = pcall(Font.split, text)
    if not ok or #spans <= glyphs then return text end
    return text:sub(1, spans[glyphs].to)
  end

  -- ------- one arrow, three directions
  --
  -- The header's two page arrows and anything else that has to point are THE
  -- SAME TRIANGLE drawn on whichever axis is asked for: a long edge of 7
  -- tapering to a point over 4.  Drawn rather than printed because the charmap
  -- has a down arrow ($EE) but no left or right twin of it, and a glyph sits
  -- inside an 8x8 cell with its own padding, so it cannot be lined up with a
  -- triangle drawn beside it however the coordinates are nudged.
  local ARROW_LONG, ARROW_SHORT = 7, 4
  C.ARROW_W, C.ARROW_H = ARROW_SHORT, ARROW_LONG

  function C.arrow(x, y, dir, hollow)
    for i = 0, ARROW_SHORT - 1 do
      local span = ARROW_LONG - i * 2
      local whole = not hollow or span <= 2 or i == 0
      if dir == "down" then
        local left = x + i
        if whole then
          love.graphics.rectangle("fill", left, y + i, span, 1)
        else
          love.graphics.rectangle("fill", left, y + i, 1, 1)
          love.graphics.rectangle("fill", left + span - 1, y + i, 1, 1)
        end
      else
        -- the same triangle a quarter turn round: columns instead of rows
        local px = dir == "right" and (x + i) or (x + ARROW_SHORT - 1 - i)
        if whole then
          love.graphics.rectangle("fill", px, y + i, 1, span)
        else
          love.graphics.rectangle("fill", px, y + i, 1, 1)
          love.graphics.rectangle("fill", px, y + i + span - 1, 1, 1)
        end
      end
    end
  end

  -- ------- where you are, in a row of squares
  --
  -- Three pages, or three views: a filled square for the one you are on and a
  -- hollow one for each of the others.  It costs 21 pixels where the words
  -- would cost sixty, which is the whole reason it exists -- the header has a
  -- title in it and the title is the part worth reading.
  local PIP, PIP_GAP = 5, 3

  function C.pipsWidth(count)
    return count * PIP + (count - 1) * PIP_GAP
  end

  function C.pips(x, y, count, active)
    for i = 1, count do
      local px = x + (i - 1) * (PIP + PIP_GAP)
      if i == active then
        love.graphics.rectangle("fill", px, y, PIP, PIP)
      else
        -- a hollow square rather than a smaller one: at five pixels "smaller"
        -- reads as a rendering fault and "outlined" reads as off
        love.graphics.rectangle("fill", px, y, PIP, 1)
        love.graphics.rectangle("fill", px, y + PIP - 1, PIP, 1)
        love.graphics.rectangle("fill", px, y, 1, PIP)
        love.graphics.rectangle("fill", px + PIP - 1, y, 1, PIP)
      end
    end
  end

  -- ------- the two boxes
  --
  -- Drawn white-then-black in that order because Font.drawBox fills its
  -- interior with the CALLER's colour rules but draws its border glyphs in
  -- whatever colour is current, and the glyph pages are black on transparent.
  -- Setting black before the call is what keeps a leaked white from painting
  -- the next label white on white.

  function C.headerBox()
    C.black()
    Font.drawBox(0, 0, 20, C.HEADER_TH)
    C.black()
  end

  function C.footerBox()
    C.black()
    Font.drawBox(0, C.FOOTER_TY, 20, 3)
    C.black()
  end

  -- Clear the whole screen to white first: both screens are opaque and neither
  -- can rely on what the state underneath left in the framebuffer.
  function C.clear()
    C.white()
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    C.black()
  end

  -- ------- fitting a picture into a well
  --
  -- A Gen 1 front sprite is at most 56x56 and the well is exactly that, but
  -- nothing GUARANTEES it: a sprite mod (HGSS_SPRITES, Gold_Silver_Sprites,
  -- the Crystal animation frames) ships whatever art its author drew, and a
  -- 64-pixel one drawn at 1:1 from the top of the well runs eight pixels past
  -- the bottom of it -- through the rule and into the description text under
  -- it.  That is not a hypothetical: it is what the larger sprite packs
  -- actually do.
  --
  -- So scale to fit rather than clip: an oversized sprite comes down by the
  -- tighter of the two ratios, keeping its aspect, and one that already fits
  -- is untouched at 1:1 (never scaled UP -- a 32-pixel sprite blown up to 56
  -- is a blurry 32-pixel sprite).  Then centre what is left in both axes,
  -- because a picture pinned to the floor of a well it does not fill leaves
  -- all of its slack in one stripe above it.
  --
  -- Returns x, y, scale and the DRAWN size, which is what the palette zone and
  -- the true-colour mark both have to be measured from -- not the file's.
  function C.fit(w, h, wellX, wellY, wellW, wellH)
    local scale = math.min(wellW / w, wellH / h, 1)
    local dw, dh = w * scale, h * scale
    return wellX + math.floor((wellW - dw) / 2),
           wellY + math.floor((wellH - dh) / 2),
           scale, dw, dh
  end

  return C
end
