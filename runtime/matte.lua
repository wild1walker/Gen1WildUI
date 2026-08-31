-- The white box behind true-colour art, on screens this suite does not own.
--
-- ------- what the box is, and why it is only ever ADVANCED
--
-- `PaletteFX.markTrueColor(x, y, w, h)` is the engine's opt-out from the
-- shade pass.  A marked rectangle is spliced onto the end of the frame's zone
-- list as `colors = false` and re-blitted RAW, so a mod's animated sprite or
-- a coloured portrait keeps its own colours instead of being read as four
-- DMG shades and repainted off its red channel.
--
-- Raw means raw.  The page the screen cleared to WHITE is white inside that
-- rectangle too, and it stays white when the theme turns everything around it
-- black.  That is the white box.
--
-- It is an ADVANCED problem and only an ADVANCED problem, which is worth
-- being exact about because it decides when any of this runs at all:
-- `Renderer`'s withTrueColor begins `if not PaletteFX.honorsTrueColor() then
-- return zoneList end`, and for a Gen 1 game `honorsTrueColor` is
-- `PaletteFX.mode == "redpp"` -- ADVANCED, and nothing else.  In SGB, OG RED
-- or any of the flat modes the marks are discarded, the art goes through the
-- shade pass with the rest of the screen, and there is no box to fix.
--
-- ------- why this cannot be fixed from a zone
--
-- The theme's own hook runs on the zone list before the renderer splices the
-- true-colour rects on, and those rects are LAST -- they re-blit their region
-- over whatever the shaded pass drew.  So no zone this suite adds can reach
-- inside one.  The white is not a palette; it is a pixel, and it was put
-- there by the screen when it cleared its page.
--
-- The screens this suite owns fix it themselves: each paints `theme.matte()`
-- into the rectangle before it draws the art into it.  This file is for the
-- ones it does not own -- the trainer card's portrait, the summary screen's
-- Pokemon, the Hall of Fame PC, the diploma -- where there is no line of ours
-- to put that paint on.
--
-- ------- what it does instead
--
-- Wraps the class's `draw` and runs it twice.
--
--   1. once with `markTrueColor` swapped for a recorder, which draws the
--      frame and collects the rectangles instead of marking them;
--   2. the matte, painted into each rectangle;
--   3. once more for real, which redraws the art on top of the matte and
--      marks the rectangles properly this time.
--
-- Twice is the price of not knowing where the art goes until the screen has
-- drawn it, and it is a price worth naming: these are static single-page
-- screens, the second pass is the same work the first did, and it is only
-- paid at all when a theme is on AND the mode is ADVANCED AND the screen
-- actually marked something.  A LIGHT boot, an SGB boot, or a screen with no
-- true-colour art on it never reaches step 1.
--
-- Recording SUPPRESSES the marks rather than duplicating them: the recorder
-- stands in for `markTrueColor` for exactly the length of pass 1, so the real
-- marks are the ones pass 3 makes, and the renderer sees each rectangle once.
--
-- ------- the honest cost
--
-- This patches a method on an engine class, which is a heavier hand than
-- anything else in this bundle -- every other screen here is registered
-- through `mod.content.screens`, or is an instance built by the engine and
-- re-dressed.  There is no seam for "before this state draws", and a screen
-- we do not own has no line of ours in it.  So the patch is kept as small as
-- a patch can be: it calls through in every case it does not handle, it is
-- installed once, and with a LIGHT theme or a mode that is not ADVANCED it is
-- one comparison and a tail call.

--
-- ------- the title screen, which is the same white page by another road
--
-- 0.24.0 tried to make the title screen dark the way every other page in
-- this suite is dark: reverse its palettes, so the paper goes black and the
-- ink goes white.  Three things went wrong on screen and it was backed out
-- in 0.28.0 (see Theme.COVERED_PAGES).  The one that matters here is the
-- third: the mon and the player figure are marked TRUE COLOUR, so their
-- rectangles are re-blitted raw from a canvas whose page is white -- two
-- white boxes on a black screen, which is exactly what a matte is for, and
-- exactly what a matte could not fix here.  `Matte.wrap` draws the screen
-- twice with the paint in between, and `TitleState:draw` OPENS with a white
-- fill of the whole screen: the second pass paints over the matte before it
-- draws anything.
--
-- So the title screen is done the other way round.  Rather than reverse the
-- palette and then repair the raw rectangles, paint the PAGE ITSELF black
-- and leave the palettes alone:
--
--   * the ground is black pixels, which every band already reads as its own
--     colour 3, and the theme pins that colour to black so it is black
--     whatever palette the cart ships (theme.lua, groundZones);
--   * the logo, the ribbon and the mon keep colours 0, 1 and 2 -- their own
--     colours, which is what was asked for;
--   * a true-colour rectangle re-blits a page that is ALREADY BLACK, so
--     there is no white box to repair and nothing has to be drawn twice.
--
-- It works in every display mode rather than only ADVANCED, because it is
-- not a true-colour fix -- it is the page.
--
-- Two details it has to get right:
--
--   The copyright line is BLACK INK, and black ink on a black page is not
--   there.  So the bottom row is left WHITE and the theme reverses that one
--   row on its own -- white letters on black, the same trade every dialogue
--   box in this suite makes.  Everything above it is painted black.
--
--   With the CONTINUE menu open none of this applies.  `TitleState:draw`
--   fills white and returns (MainMenu's own ClearScreen); there is no art on
--   the screen, the frame is an ordinary page, and Theme.COVERED_PAGES
--   reverses it like any other.  Painting a black ground under that would
--   reverse to a WHITE one.
--
-- ------- the shim, and why it is one
--
-- The fill is the first line of `TitleState:draw`.  There is no seam before
-- it and no colour to configure, so `love.graphics.rectangle` stands in for
-- itself for the length of one call: the first full-screen fill is answered
-- with the black page and the white copyright row, the real function is put
-- back the moment that fill is served, and every other rectangle the screen
-- draws goes through untouched.  It is the same shape as the markTrueColor
-- swap above -- narrow, restored on every path including a raise, and doing
-- nothing at all under LIGHT.
--
-- It is also indifferent to who else has wrapped this method.  Wild Green
-- wraps `TitleState.draw` to mark the figure before the draw reads it, and
-- whichever of the two ends up outermost, the fill is still served from
-- inside the other one.

local Matte = {}

-- Engine screens that BOTH mark true colour and are themed pages.  A screen
-- that marks nothing has nothing to matte; a screen the theme leaves alone is
-- still on white paper, where a white box is invisible.
--
-- `src.ui.DexEntryMenu` is here for the build where POKEDEX is switched off:
-- with it on, Gen1Dex registers its own entry screen, that instance carries
-- its own `draw`, and this wrapper is never reached for it.
Matte.SCREENS = {
  "src.ui.TrainerCard",
  "src.ui.SummaryMenu",
  "src.ui.LeaguePC",
  "src.ui.Diploma",
  "src.ui.DexEntryMenu",
}

-- The title screen, and the row its copyright line sits on.  `TitleState`
-- draws that line at y = 136 (drawCopyright, called with 136 on every frame
-- of the Red layout), so row 17 is the copyright and nothing else.
Matte.TITLE = "src.ui.TitleState"
Matte.GROUND_H = 136

function Matte.new(context)
  local self = {}
  local patched = {}

  -- The colour to paint, or nil for "there is nothing to do here".  Three
  -- ways to answer nil, and each of them is a whole build that pays nothing:
  -- no theme, LIGHT, or a mode that discards true-colour marks anyway.
  local function matteColour()
    local theme = context.theme
    if type(theme) ~= "table" or type(theme.read) ~= "function" then
      return nil
    end
    if theme.read() == "light" then return nil end
    local PaletteFX = require("src.render.PaletteFX")
    if type(PaletteFX.honorsTrueColor) == "function"
        and not PaletteFX.honorsTrueColor() then
      return nil
    end
    local colour = theme.matte()
    if type(colour) ~= "table" or #colour < 3 then return nil end
    return colour
  end

  -- Pass 1: draw, and collect the rectangles instead of marking them.
  local function record(base, state, ...)
    local PaletteFX = require("src.render.PaletteFX")
    local real = PaletteFX.markTrueColor
    local seen = {}
    PaletteFX.markTrueColor = function(x, y, w, h)
      if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
        seen[#seen + 1] = { x = x or 0, y = y or 0, w = w, h = h }
      end
    end
    local ok, problem = pcall(base, state, ...)
    PaletteFX.markTrueColor = real
    if not ok then return nil, problem end
    return seen
  end

  local function paint(colour, rect)
    love.graphics.setColor(colour[1] / 255, colour[2] / 255,
                           colour[3] / 255, 1)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(1, 1, 1, 1)
  end

  function self.wrap(base)
    return function(state, ...)
      local colour = matteColour()
      if not colour then return base(state, ...) end

      local rects, problem = record(base, state, ...)
      if not rects then
        -- pass 1 raised part way through: the frame is half drawn, so draw it
        -- again plainly rather than leaving it, and let the screen's own error
        -- surface the way it would have without this wrapper
        context.mod.log:warn("matte stood down: %s", tostring(problem))
        return base(state, ...)
      end
      if not rects[1] then return end     -- nothing marked; pass 1 IS the frame

      for _, rect in ipairs(rects) do paint(colour, rect) end
      return base(state, ...)
    end
  end

  -- DARK, and nothing else -- unlike the matte above this is not a
  -- true-colour repair, so the display mode does not come into it.
  local function darkGround()
    local theme = context.theme
    if type(theme) ~= "table" or type(theme.read) ~= "function" then
      return false
    end
    return theme.read() == "dark"
  end

  -- Serve the screen's opening full-screen fill as a black page with a white
  -- copyright row, once, and then get out of the way.
  local function withBlackPage(base, state, dark, ...)
    local lg = love.graphics
    local real = lg.rectangle
    local painted = false
    lg.rectangle = function(mode, x, y, w, h, ...)
      if not painted and mode == "fill"
          and x == 0 and y == 0 and w == 160 and h == 144 then
        painted = true
        lg.rectangle = real
        lg.setColor(0, 0, 0, 1)
        real("fill", 0, 0, 160, dark and 144 or Matte.GROUND_H)
        if not dark then
          lg.setColor(1, 1, 1, 1)
          real("fill", 0, Matte.GROUND_H, 160, 144 - Matte.GROUND_H)
        end
        -- (1,1,1,1) is what the screen left set before its fill and what the
        -- logo draw on the next line expects to find.
        lg.setColor(1, 1, 1, 1)
        return
      end
      return real(mode, x, y, w, h, ...)
    end

    -- ------- the logo, which carries a margin
    --
    -- A pixel larger than the sheet it was cut from, because its own line
    -- work runs into the last column of that sheet and the pad had nowhere to
    -- grow.  Drawn a pixel up and left, it lands where the bare one would.
    --
    -- ------- and the ball's ring, which goes UNDER the trainer or not at all
    --
    -- The engine draws the figure's three slices and then the ball, so the
    -- ball sits on top of him and his fingers are directly under it.  A ring
    -- drawn with the ball is a white line across the hand.  It has to go down
    -- before the first slice: after the mon, which the ball is also in front
    -- of, and before the trainer, who is in front of the ring.
    --
    -- That moment used to be found by matching the IMAGE -- the first draw
    -- whose texture is the sheet this file swapped onto the state.  Which is
    -- a bet that nothing between here and the draw changes `state.player`,
    -- and on this cart something does: Wild Green re-asserts its own copy
    -- from inside `currentSprite`, which `TitleState:draw` calls after it has
    -- captured `playerImage` but before the slices go down.  Lose that bet and
    -- the first texture that matches is the BALL's own draw, so the ring is
    -- laid there instead -- after the trainer, across the hand, which is what
    -- was reported.
    --
    -- So match the QUAD.  `state.playerQuads` holds the three the engine
    -- built and passes verbatim, and a quad is not the sort of thing a mod
    -- swaps -- it is geometry, not art.  Whatever texture arrives carrying one
    -- of those three, that draw is a slice of the trainer, and the ring
    -- belongs in front of it.
    --
    -- And if none of them is ever seen -- a build that draws the figure whole
    -- rather than in slices, a sprite pack that rebuilt the quads -- the ring
    -- is not drawn at all.  Under the trainer or nowhere: a missing ring is a
    -- ball that looks exactly as it did before any of this, and a ring over
    -- the hand is the bug.
    local realDraw = lg.draw
    local logo, ball = state.__gen1WildLogo, state.__gen1WildBall
    local ballY = state.ballY

    local slices
    if ball and type(ballY) == "number" then
      for _, part in ipairs(state.playerQuads or {}) do
        if part[1] ~= nil then
          slices = slices or {}
          slices[part[1]] = true
        end
      end
    end

    if logo or slices then
      local laid = false
      lg.draw = function(image, a, b, c, ...)
        if logo and image == logo
            and type(a) == "number" and type(b) == "number" then
          return realDraw(image, a - 1, b - 1)
        end
        if slices and not laid and slices[a] and type(b) == "number" then
          laid = true
          realDraw(ball, b - 1, ballY - 1)
        end
        return realDraw(image, a, b, c, ...)
      end
    end

    local ok, problem = pcall(base, state, ...)
    lg.rectangle = real
    lg.draw = realDraw
    return ok, problem, painted
  end

  -- ------- and the logo's own white
  --
  -- Pinning colour 0 to black takes the paper out of the logo and the ribbon,
  -- which is what a black ground needs -- and it takes the WHITE OUT OF THE
  -- ART with it, because the field the logo is printed on and the highlights
  -- inside its letters are the same shade.  A palette cannot tell them apart.
  --
  -- The art can.  This is the item icons' trick, which the player asked for by
  -- name: `Gen1ModernBag/icons.lua` dilates the line work by a pixel, floods
  -- the outside of the grown shape, and paints whatever the flood could not
  -- reach opaque white.  The art keeps paper of its own SHAPE -- a sticker
  -- rather than a box -- and on this logo that comes out as a one-pixel white
  -- edge round the wordmark, 417 pixels of it on a 128x56 sheet.
  --
  -- Then colour 0 can be white again, which is why the theme asks whether
  -- this took (`__gen1WildKeyedArt`) rather than assuming it: a build where
  -- the art cannot be read keeps the pin and keeps its flat logo, which is
  -- worse-looking and still correct.
  --
  -- ------- and why every one of these is loaded from a PATH
  --
  -- 0.31.10 read the pictures back off the GPU instead, so that art another
  -- mod had swapped in could be treated too.  Something in that -- the canvas
  -- bind, the blend mode, the transform, I never established which -- left
  -- the pipeline in a state the rest of the frame did not survive: POKeMON
  -- several times their size, colour zones in the wrong places, hairlines
  -- through everything.  Two releases of it.
  --
  -- Every bake here reads a FILE, through `Assets.imageData`, which touches
  -- no GPU state at all.  It is why the figure and the mon get no pad: those
  -- two are swapped by other mods mid-draw and a path cannot see what they
  -- swapped in.  A worse-looking title that is drawn correctly beats a better
  -- one that is not.
  local PAD = 1
  local keyed = {}

  -- The path a title picture was loaded from, or nil.
  --
  -- ------- why there is no fallback here
  --
  -- The engine has one: TitleState.lua:245-275 reads each of these out of
  -- `field.title` and falls back to a hard-coded path into the player's own
  -- ROM-derived cache when the importer seeded no descriptor.
  -- This mod mirrored that, and it cannot: modkit's MK301 forbids a mod from
  -- naming those trees at all -- "ship your own asset under assets/ or
  -- derive it via assets_transforms" -- and it is a plain string scan over
  -- every shipped file, comments included,
  -- precisely so that the rule cannot be met halfway.  Which is right.  The
  -- engine reads that cache because it is the engine; a mod that hard-codes
  -- a path into it is reaching into somebody's install for a file this
  -- repository has never seen and cannot ship.
  --
  -- So a picture with no descriptor is simply not baked.  Every caller
  -- already handles that: `swap` returns false and leaves the engine's own
  -- image alone, and the copyright line drops `dark` so its row is not
  -- painted black under letters that were never turned over.  The picture is
  -- still on screen -- the engine loaded it -- it just does not get a pad.
  -- `fallback` is for a picture whose file this repository is allowed to
  -- name: assets/logo/pokemon_logo.png ships with the engine.  The four that
  -- used to have one are the four that live in the generated trees, and they
  -- are passed none.
  local function pathOf(entry, fallback)
    if type(entry) == "table" then entry = entry.path end
    if type(entry) == "string" then return entry end
    return fallback
  end

  local function paper(id, x, y)
    local r, g, b, a = id:getPixel(x, y)
    return a > 0 and r > 0.83 and g > 0.83 and b > 0.83
  end

  -- Grow the line work, flood the outside of the grown shape, keep what the
  -- flood could not reach.  One pixel of growth and not two, for the icons'
  -- reason: two swells a shape until it fills the space it was cut out of,
  -- which is the box this is here to stop being.
  -- ------- what counts as line work
  --
  --   * the logo is printed ON paper -- opaque everywhere, near-white where
  --     the paper is -- so its ink is what is NOT paper.
  --   * the figure and the mon are sprites on transparency (`raw2bpp` with
  --     `matte`, `writeCompressedPic` through `matteColor0`), so their ink is
  --     every opaque pixel and the pad is a one-pixel outline.
  local function stickerRect(id, onPaper, rect)
    local w, h = rect.w, rect.h
    local x0, y0 = rect.x, rect.y
    if w <= 0 or h <= 0 then return false end

    local ink = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local _, _, _, a = id:getPixel(x0 + x, y0 + y)
        if a > 0 and not (onPaper and paper(id, x0 + x, y0 + y)) then
          ink[y * w + x] = true
        end
      end
    end
    if not next(ink) then return false end

    local grown = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        if ink[y * w + x] then
          for dy = -PAD, PAD do
            for dx = -PAD, PAD do
              local nx, ny = x + dx, y + dy
              if nx >= 0 and ny >= 0 and nx < w and ny < h then
                grown[ny * w + nx] = true
              end
            end
          end
        end
      end
    end

    local queue, head, outside = {}, 1, {}
    local function push(x, y)
      if x < 0 or y < 0 or x >= w or y >= h then return end
      local key = y * w + x
      if outside[key] or grown[key] then return end
      outside[key] = true
      queue[#queue + 1] = key
    end
    for x = 0, w - 1 do push(x, 0); push(x, h - 1) end
    for y = 0, h - 1 do push(0, y); push(w - 1, y) end
    while head <= #queue do
      local key = queue[head]; head = head + 1
      local x, y = key % w, math.floor(key / w)
      push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
    end

    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local key = y * w + x
        if not ink[key] then
          if outside[key] then
            id:setPixel(x0 + x, y0 + y, 0, 0, 0, 0)
          else
            id:setPixel(x0 + x, y0 + y, 1, 1, 1, 1)
          end
        end
      end
    end
    return true
  end

  -- ------- one sheet, several pictures
  --
  -- The figure is a sheet the title draws in pieces: three full-width slices
  -- with the POKe BALL tucked into the gap at (0,16).  A halo grown across
  -- the whole sheet would grow across that boundary too -- a white pixel off
  -- the ball's edge that belongs to the trainer, landing on screen nowhere
  -- near him.  So the bake runs once per PIECE, inside that piece's
  -- rectangle, with the flood starting at the rectangle's own border.  Pieces
  -- that are contiguous when they land grow no halo along the seam, because
  -- the pixel across it is ink and ink is never repapered.
  local function sticker(id, onPaper, rects)
    if not rects then
      local w, h = id:getDimensions()
      rects = { { x = 0, y = 0, w = w, h = h } }
    end
    local any = false
    for _, rect in ipairs(rects) do
      if stickerRect(id, onPaper, rect) then any = true end
    end
    return any
  end

  -- Every near-white pixel, counters included.  The ribbon is eight pixels of
  -- letters with a pixel between them: pad every letter and the pads meet,
  -- and what comes out is a white plate with words on it, which is the white
  -- box behind WILD GREEN VERSION this whole line of work started from.  And
  -- keying only what the border could reach left the white shut inside an `e`
  -- or an `o` behind, as a scatter of specks through the words.
  local function keyAll(id)
    local w, h = id:getDimensions()
    local any = false
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        if paper(id, x, y) then id:setPixel(x, y, 0, 0, 0, 0); any = true end
      end
    end
    return any
  end

  -- The copyright line, turned over so it reads on a black row.
  --
  -- `RomExtractor` writes both its files with `raw2bpp` and no transparency
  -- (`title/copyright.png` 152x8, `title/gamefreak_inc.png` 72x8), so they
  -- are fully opaque four-shade greys: white paper, dark letters.  Turning
  -- every pixel over gives light letters on black paper, and black paper is
  -- the page, so it disappears into it.
  local function invert(id)
    local w, h = id:getDimensions()
    local any = false
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = id:getPixel(x, y)
        if a > 0 then id:setPixel(x, y, 1 - r, 1 - g, 1 - b, a); any = true end
      end
    end
    return any
  end

  -- A copy, always: Assets.imageData caches, and keying the cached data would
  -- hole the same art everywhere else it is drawn.
  --
  -- `margin` grows the copy by a pixel on every side and pastes the art into
  -- the middle of it, for art whose own line work reaches the edge of its
  -- sheet and leaves the pad nowhere to go.  The ROM's POKeMON logo is
  -- exactly that -- `raw2bpp("PokemonLogoGraphics", 128, 56)` with no
  -- transparency, and the wordmark runs into the last column -- which is what
  -- "a little bit of padding missing on the right side" is.  A bigger sheet
  -- has to be drawn a pixel up and left to land where the bare one would;
  -- `withBlackPage` does that.
  local function keyedImage(path, bake, margin)
    local key = path .. (margin and "+" or "")
    if keyed[key] ~= nil then return keyed[key] or nil end
    keyed[key] = false
    pcall(function()
      local Assets = require("src.render.Assets")
      local src = Assets.imageData(path)
      local w, h = src:getDimensions()
      local pad = margin and 1 or 0
      local id = love.image.newImageData(w + pad * 2, h + pad * 2)
      id:paste(src, pad, pad, 0, 0, w, h)
      if bake(id) then
        local out = love.graphics.newImage(id)
        pcall(out.setFilter, out, "nearest", "nearest")
        keyed[key] = out
      end
    end)
    return keyed[key] or nil
  end

  -- The figure's three slices and the POKe BALL in the gap between them, off
  -- the quads the state built rather than restated here: they are sized from
  -- the sheet, and a sprite pack may ship a taller one.
  local function figureRects(state, id)
    local out, seen = {}, {}
    local function add(quad)
      if not quad or type(quad.getViewport) ~= "function" then return end
      local okQ, qx, qy, qw, qh = pcall(quad.getViewport, quad)
      if not okQ then return end
      local mark = table.concat({ qx, qy, qw, qh }, ",")
      if seen[mark] then return end
      seen[mark] = true
      out[#out + 1] = { x = qx, y = qy, w = qw, h = qh }
    end
    for _, part in ipairs(state.playerQuads or {}) do add(part[1]) end
    add(state.ballQuad)
    if not out[1] then
      local w, h = id:getDimensions()
      out[1] = { x = 0, y = 0, w = w, h = h }
    end
    return out
  end

  -- ------- the POKe BALL, which has nowhere on the sheet to grow into
  --
  -- Its eight-by-eight cell sits at (0,16) in the gap the trainer's middle
  -- slice leaves, and every pixel around it inside the sheet belongs to the
  -- trainer -- so a pad baked in place has nowhere to go.  It is cut out into
  -- an image a pixel larger on every side and substituted for that one draw,
  -- a pixel up and left, so it lands where the bare ball would have.
  --
  -- ------- and no pad underneath it, ONCE IT HAS LANDED
  --
  -- The ball is drawn AFTER the trainer's three slices, so it is on top of
  -- him, and where he is holding it his hand is directly under it.  A pad on
  -- that side is not paper round the art, it is a white line painted across
  -- the hand.
  --
  -- But only once it is in the hand.  `title.asm` throws the ball in from
  -- above and animates `ballY` down to its resting place, and for that whole
  -- fall there is nothing behind it at all -- so an underside with no paper
  -- on it is the ball's bottom edge meeting the black ground directly, which
  -- is the flash a player saw.  Both are baked, and the draw picks: the full
  -- ring while it is falling, the trimmed one when it has landed.
  --
  -- Trimmed per column rather than by cutting the bottom row off: below the
  -- LOWEST pixel of art in each column, which follows the curve of the ball
  -- and takes the two bottom corners with it.  A column with no art in it is
  -- not underneath anything -- it is the pad beside the ball -- and is left
  -- as it is.
  local function ballImage(path, quad, trim)
    if not (quad and type(quad.getViewport) == "function") then return nil end
    local okQ, qx, qy, qw, qh = pcall(quad.getViewport, quad)
    if not (okQ and qw and qh and qw > 0 and qh > 0) then return nil end
    local key = ("%s#ball%d,%d,%d,%d%s")
      :format(path, qx, qy, qw, qh, trim and "-trim" or "")
    if keyed[key] ~= nil then return keyed[key] or nil end
    keyed[key] = false
    pcall(function()
      local Assets = require("src.render.Assets")
      local src = Assets.imageData(path)
      local cw, ch = qw + 2, qh + 2
      local cell = love.image.newImageData(cw, ch)
      cell:paste(src, 1, 1, qx, qy, qw, qh)

      -- where the art ends in each column, read before the pad is grown
      local floor = {}
      for x = 0, cw - 1 do
        for y = 0, ch - 1 do
          local _, _, _, a = cell:getPixel(x, y)
          if a > 0 then floor[x] = y end
        end
      end

      if not sticker(cell, false, nil) then return end
      if trim then
        for x = 0, cw - 1 do
          if floor[x] then
            for y = floor[x] + 1, ch - 1 do cell:setPixel(x, y, 0, 0, 0, 0) end
          end
        end
      end
      local out = love.graphics.newImage(cell)
      pcall(out.setFilter, out, "nearest", "nearest")
      keyed[key] = out
    end)
    return keyed[key] or nil
  end

  -- The four the title prints on its own paper.  The mon and the figure are
  -- marked true colour and never went through a palette at all -- and they
  -- are also the two another mod swaps, which is why neither is here.
  --
  -- The second return says whether the COPYRIGHT pair came through, which is
  -- what decides whether that row can be painted black: light letters or a
  -- light row, never dark letters on a dark one.
  local function keyTitleArt(state)
    if not (love.image and love.image.newImageData) then return nil, false end
    local title = type(state.title) == "table" and state.title or {}
    local put = {}
    local function swap(field, path, bake, margin)
      if not state[field] or not path then return false end
      local image = keyedImage(path, bake, margin)
      if not image then return false end
      put[field] = state[field]
      state[field] = image
      return true
    end
    -- ------- a picture may only be replaced by one of the same size
    --
    -- This is the guard that would have caught 0.31.10 on the first frame.
    -- The title places the mon at `x = 40 + (56 - w) / 2` and `y = 136 - h`,
    -- off the dimensions of whatever it is handed, so a substitute of a
    -- different size is not a different-looking mon, it is a POKeMON across
    -- half the screen on top of the logo.  If the bake does not come back the
    -- same size as the picture it is standing in for, it does not stand in.
    local function sameSize(a, b)
      if not (a and b) then return false end
      local okA, aw, ah = pcall(a.getDimensions, a)
      local okB, bw, bh = pcall(b.getDimensions, b)
      return okA and okB and aw == bw and ah == bh
    end

    swap("logo", pathOf(title.logo, "assets/logo/pokemon_logo.png"),
         function(id) return sticker(id, true, nil) end, true)
    swap("version", pathOf(title.versionRibbon or title.version), keyAll)

    -- ------- the figure, and the ball out of the same sheet
    --
    -- Not in OG RED, where the draw rebuilds the image from `playerPath`
    -- through the OBP tables on every frame and never reads this field.
    --
    -- And from the path the picture ACTUALLY came from.  `state.playerPath`
    -- is the red figure's, because that is what TitleState loaded; Wild Green
    -- swaps `state.player` for its green derived copy and leaves that path
    -- alone, so baking it is what put the red suit back on a green cart in
    -- 0.31.8.  Its recipe names the file it used, and that is the one baked.
    local obp = false
    pcall(function()
      local PaletteFX = require("src.render.PaletteFX")
      obp = type(PaletteFX.usesSpriteObp) == "function"
        and PaletteFX.usesSpriteObp() or false
    end)
    if not obp and state.player then
      local path = state.__gen1WildPlayerPath or state.playerPath
      if path then
        local baked = keyedImage(path, function(id)
          return sticker(id, false, figureRects(state, id))
        end)
        if sameSize(baked, state.player) then
          put.player = state.player
          state.player = baked
          state.__gen1WildBall = ballImage(path, state.ballQuad)
        end
      end
    end

    -- ------- the copyright, all of it or none of it
    --
    -- One line drawn from two files and, on Yellow, three.  Turned over it
    -- reads light, and the row it sits on is painted black to suit -- so a
    -- file that will not turn cannot simply be skipped: its half of the line
    -- would be dark letters on a black row, and the half that did turn would
    -- be light letters on a light one if the row stayed as it was.
    --
    -- So the whole line is baked BEFORE any of it is installed, and the row
    -- goes black only if every file came back.
    local line = {
      { "copyImg", pathOf(title.copyright) },
      { "gfInc", pathOf(title.gamefreakInc) },
      { "nineImg", pathOf(title.nine) },
    }
    local dark, ready = true, {}
    for _, entry in ipairs(line) do
      local field, path = entry[1], entry[2]
      if state[field] then
        local image = path and keyedImage(path, invert) or nil
        if image then ready[field] = image else dark = false end
      end
    end
    if dark then
      for field, image in pairs(ready) do
        put[field] = state[field]
        state[field] = image
      end
    end

    if not next(put) then return nil, false end
    state.__gen1WildLogo = put.logo and state.logo or nil
    return put, dark
  end

  -- ------- the mon
  --
  -- The one piece of title art with no field to swap: cached per species
  -- inside the state and reached only through `currentSprite`.  The bake is
  -- of the FILE that call resolves -- `Sprites.path` with the title kind,
  -- which is where the engine itself gets it -- and it stands in only if it
  -- comes back the same size as what the call returned.
  --
  -- That guard is the whole safety of this.  With Crystal Animated Sprites
  -- installed, `currentSprite` hands back an animation SHEET; the static file
  -- behind it is a different size, the sizes disagree, and nothing is
  -- substituted.  0.31.10 had no guard and drew the sheet.
  local function wrapCurrentSprite(base)
    return function(state, ...)
      local image, trueColor = base(state, ...)
      if not image or type(state) ~= "table"
          or not state.__gen1WildKeyedArt
          or not (love.image and love.image.newImageData) then
        return image, trueColor
      end
      local baked
      pcall(function()
        local species = state.cycleSpecies
          and state.cycleSpecies[state.cycleIndex]
        if not species then return end
        local path = require("src.pokemon.Sprites").path(
          state.game.data, species, "front", { kind = "title" })
        if type(path) ~= "string" then return end
        baked = keyedImage(path, function(id)
          return sticker(id, false, nil)
        end)
      end)
      if not baked then return image, trueColor end
      local okA, aw, ah = pcall(baked.getDimensions, baked)
      local okB, bw, bh = pcall(image.getDimensions, image)
      if not (okA and okB and aw == bw and ah == bh) then
        return image, trueColor
      end
      return baked, trueColor
    end
  end

  function self.wrapTitle(base)
    return function(state, ...)
      if type(state) == "table" then state.__gen1WildDarkGround = nil end
      -- With the menu open there is no art on this screen and the frame is an
      -- ordinary page; the theme reverses it, and a black ground would reverse
      -- to a white one.
      if type(state) ~= "table" or state.menuOpen or not darkGround() then
        return base(state, ...)
      end
      local put, dark = keyTitleArt(state)
      state.__gen1WildKeyedArt = put and true or nil
      -- The ring round the art stops above the copyright: that row is the one
      -- strip this ground leaves light, and the mon's box ends on exactly the
      -- line it starts on, so without this the ring's bottom bar is painted
      -- straight through the words.
      local theme = context.theme
      if type(theme) == "table" and type(theme.clipArt) == "function" then
        pcall(theme.clipArt, Matte.GROUND_H)
      end
      local ok, problem, painted = withBlackPage(base, state, dark, ...)
      if put then
        for field, image in pairs(put) do state[field] = image end
      end
      -- Wild Green marks the figure BEFORE this draw runs, because the draw
      -- reads `self.player` at its top -- and the draw's opening full-screen
      -- fill wipes the skirt that mark painted.  Laying the rings down again
      -- now costs nothing (they are outside the art by construction) and is
      -- the difference between the figure keeping its hairline and not.
      if ok and type(theme) == "table"
          and type(theme.paintSkirts) == "function" then
        pcall(theme.paintSkirts)
      end
      if not ok then
        -- the screen raised part way through with the shim in place: it is
        -- already back, so let the frame be drawn plainly and the screen's own
        -- error surface the way it would have without this wrapper
        context.mod.log:warn("title ground stood down: %s", tostring(problem))
        return base(state, ...)
      end
      state.__gen1WildDarkGround = painted or nil
    end
  end

  function self.installTitle()
    local ok, class = pcall(require, Matte.TITLE)
    if ok and type(class) == "table" and type(class.draw) == "function"
        and not patched[class] then
      patched[class] = true
      class.draw = self.wrapTitle(class.draw)
      if type(class.currentSprite) == "function" then
        class.currentSprite = wrapCurrentSprite(class.currentSprite)
      end
    end
  end

  function self.install()
    for _, path in ipairs(Matte.SCREENS) do
      local ok, class = pcall(require, path)
      if ok and type(class) == "table" and type(class.draw) == "function"
          and not patched[class] then
        patched[class] = true
        class.draw = self.wrap(class.draw)
      end
    end
  end

  return self
end

return Matte
