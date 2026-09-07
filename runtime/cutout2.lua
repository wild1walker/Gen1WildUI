-- The white squares around Gold's pictures.
--
-- Returns a factory: factory(context) -> { install }, built by bundle.lua in
-- the place runtime/matte.lua is built on Red, and for the same reason: the
-- theme cannot reach these.
--
-- ------- why Gold needed one after all
--
-- runtime/matte.lua carries a note saying Gold has no equivalent -- "its art
-- is drawn in the picture like everything else, so there is no white box to
-- repair and nothing for a matte to do".  Three screenshots say otherwise: the
-- trainer card's portrait, the eight gym leaders on its BADGES page and the
-- #DEX's pic all sit in a white square on a black page.
--
-- The note was right about the MECHANISM and wrong about the conclusion.  Red
-- re-blits a true-colour rectangle past the shade pass and the white page it
-- was cut out of comes back with it; Gold does none of that.  What Gold has
-- instead is full-colour cart art with the white field BAKED INTO THE PIXELS,
-- drawn raw because there is no palette to remap it through -- `TileSheet:draw`
-- takes `body()` whenever `colors` is nil, and `BattleState:drawPic` skips the
-- remap outright for anything flagged `trueColor`.  A shade substitution has
-- nothing to substitute.  The white is a picture of white.
--
-- So the Gen 2 answer is not to paint a page under the square.  It is to take
-- the square away, which is what was asked for: "can you just cut them out of
-- that square, not replace the color".
--
-- ------- the cut, and why it is a flood fill rather than a colour test
--
-- Every one of these pictures is a figure standing in a field of one colour.
-- Keying that colour out everywhere would punch holes THROUGH the figure --
-- the player's white shorts, a leader's white collar, the highlight in an eye
-- -- so the field is found by flooding inward from the border instead.  White
-- that the edge can reach is the square; white the figure encloses is the
-- shirt, and it stays.
--
-- Guarded to art that is actually a cart pic: fully opaque (anything carrying
-- its own alpha is already cut, or is replacement art whose colour 0 "is not a
-- hole, it is a colour"), few enough colours to be one, and with a field the
-- border can actually see.
--
-- ------- and where it is built
--
-- NEVER inside a draw.  Reading a picture back binds a scratch canvas and the
-- result is a new texture, and doing either with the frame's canvas bound is
-- what broke the battle pics in 0.32.62: "on iOS, the image gets flipped, on
-- android it just crashes".  Same split as the arena's, for the same reason:
--
--   in the draw     a CACHE READ.  A picture it has not seen is remembered as
--                   wanted and the cart's own square is drawn, so the first
--                   frame a screen appears on is exactly the cartridge.
--   on core.update  nothing bound, no transform in effect -- one picture per
--                   frame is read back and cut.  From the next frame it is
--                   there.
--
-- ------- two kinds of picture
--
-- The #DEX draws ONE image and fills a plate behind it.  The trainer card
-- draws its portrait and each leader's face as a BLOCK OF TILE BLITS out of a
-- sheet, and the figure is not contiguous in that sheet -- the tiles are laid
-- out in rows of sixteen -- so cutting the sheet is meaningless.
--
-- A block is therefore cut by RECORDING the blits the engine makes (their
-- image, quad and position: no GL call, nothing created, safe inside a draw),
-- replaying them into a canvas on the update, and cutting that.  The geometry
-- stays the engine's own -- read off the blits rather than re-derived -- so a
-- tile the cart moves moves here too.

local Cutout2 = {}

-- LuaJIT keeps `unpack` global; 5.2 moved it.  Both are answered here so the
-- replay works on either.
local unpack = table.unpack or unpack

-- Big enough for a 7x7 pic and a 5x7 portrait, small enough that a sheet
-- handed here by mistake is refused rather than read back a megapixel at a
-- time.
local MAX_SIDE = 128
-- A cart picture is 2bpp art or a small-palette replacement for one.  A
-- photograph is not a thing to cut a square out of.
local MAX_COLORS = 64

-- ------- the cut itself, on one ImageData
--
-- Pure, and exposed, because it is the whole of the risk: getting it wrong
-- cuts a hole in a picture.
-- `gaps` says what a TRANSPARENT pixel means, and the two callers mean
-- opposite things by it.
--
--   a source image   alpha is somebody else's cut, or replacement art whose
--                    colour 0 "is not a hole, it is a colour".  Refuse it.
--   a replayed block  alpha is where the engine DREW NOTHING, and that is
--                    outside the figure by definition -- so it seeds the
--                    flood fill instead of stopping it.
--
-- That distinction is not academic: `TrainerCard:drawLeaderFace` lays row 0
-- across four columns and rows 1 and 2 across only THREE, so a leader's face
-- is an L, not a rectangle, and the column it never draws is transparent in
-- the replay.  Refusing on alpha meant every one of the eight was refused and
-- the badges page was untouched.
function Cutout2.cut(data, w, h, gaps)
  local dw, dh = w, h
  if type(data.getDimensions) == "function" then
    local ok, gw, gh = pcall(data.getDimensions, data)
    if ok and tonumber(gw) and tonumber(gh) then dw, dh = gw, gh end
  end
  -- DPI scale: a canvas asked for at w x h can come back bigger, and reading
  -- the first w x h of that is a magnified corner.  Measured off what actually
  -- came back rather than off what was asked for.
  if dw < w or dh < h or dw % w ~= 0 or dh % h ~= 0 or dw / w ~= dh / h then
    return nil
  end
  local ratio = dw / w
  local half = math.floor(ratio / 2)

  local px, colors, nColors = {}, {}, 0
  for y = 0, h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x * ratio + half, y * ratio + half)
      if a <= 0.5 then
        if not gaps then return nil end
        px[row + x] = -1          -- nothing was drawn here; outside, always
        goto continue
      end
      local key = math.floor(r * 255 + 0.5) * 65536
                + math.floor(g * 255 + 0.5) * 256
                + math.floor(b * 255 + 0.5)
      px[row + x] = key
      if not colors[key] then
        colors[key] = true
        nColors = nColors + 1
        if nColors > MAX_COLORS then return nil end
      end
      ::continue::
    end
  end
  if nColors < 2 then return nil end

  -- ------- which colour is the FIELD
  --
  -- Whatever is actually AT THE BORDER, by majority.  This used to be "the
  -- lightest by red", on the reasoning that a cart picture stands in its own
  -- colour 0 and colour 0 is the white one -- true of every POKeMON pic and
  -- FALSE of the question mark, whose glyph is LIGHTER than the square it
  -- sits in.  Measured off the screen: field red 57, glyph red 72.
  --
  -- So "lightest" picked the GLYPH as the field, the border could not reach a
  -- single glyph pixel, the flood found nothing, and the cut was refused --
  -- every time, silently, for six releases.  The ? kept its square because
  -- this one line was looking at the wrong end of the palette.
  --
  -- The border is the honest definition and needs no assumption about which
  -- way round the shades run: the field is what surrounds the figure, and what
  -- surrounds the figure is what the edge of the block is made of.
  local edge = {}
  local function tally(i)
    local key = px[i]
    if key and key ~= -1 then edge[key] = (edge[key] or 0) + 1 end
  end
  for x = 0, w - 1 do tally(x); tally((h - 1) * w + x) end
  for y = 0, h - 1 do tally(y * w); tally(y * w + w - 1) end
  local field, fieldCount = nil, 0
  for key, count in pairs(edge) do
    if count > fieldCount then field, fieldCount = key, count end
  end
  if not field then return nil end

  local figure = {}
  for i = 0, w * h - 1 do
    -- -1 is a gap: never part of the figure, so the fill runs straight
    -- through it and out the other side.
    if px[i] ~= field and px[i] ~= -1 then figure[i] = true end
  end

  local outside, qx, qy, head = {}, {}, {}, 1
  local function push(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return end
    local key = y * w + x
    if outside[key] or figure[key] then return end
    outside[key] = true
    qx[#qx + 1], qy[#qy + 1] = x, y
  end
  for x = 0, w - 1 do push(x, 0); push(x, h - 1) end
  for y = 0, h - 1 do push(0, y); push(w - 1, y) end
  while head <= #qx do
    local x, y = qx[head], qy[head]
    head = head + 1
    push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
  end

  local n = 0
  for i = 0, w * h - 1 do if outside[i] then n = n + 1 end end
  -- Nothing the border can reach is not a picture in a square.
  if n == 0 then return nil end

  local out = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    local row = y * w
    for x = 0, w - 1 do
      local r, g, b = data:getPixel(x * ratio + half, y * ratio + half)
      -- Colour is kept even where it is cut, so a host that ignores alpha
      -- shows the picture it always did rather than a black hole.
      out:setPixel(x, y, r, g, b,
        (outside[row + x] or px[row + x] == -1) and 0 or 1)
    end
  end
  return out
end

function Cutout2.new(context)
  local mod = context.mod
  local self = {}

  local function on()
    return mod.options:get("gen2_cutout") ~= false
  end

  -- ------- the queue
  --
  -- `wanted` is weak-keyed so a screen closing lets its pictures go; `queue`
  -- holds a strong reference only until the update that builds it.
  local built = setmetatable({}, { __mode = "k" })
  local wanted = setmetatable({}, { __mode = "k" })
  local queue = {}
  -- Blocks are keyed by a string, not by an image, so they are kept by hand.
  local blocks, blockWanted, blockQueue = {}, {}, {}
  -- What the engine's own draw RETURNED for a block, kept beside the cut.
  -- `drawLeaderFace` hands back the next tile id and the page walks its eight
  -- faces with it, so the cached path has to answer the same number -- and the
  -- only honest source for it is the call that was recorded.  Counting the
  -- tiles here instead is re-deriving the engine's loop, and the first attempt
  -- at it was wrong by three.
  local blockReturn = {}

  local function toImage(data)
    local image = love.graphics.newImage(data)
    if type(image.setFilter) == "function" then
      pcall(image.setFilter, image, "nearest", "nearest")
    end
    return image
  end

  -- ------- one image
  --
  -- The cart's own picture, read back through a canvas the size it says it is.
  local function readImage(image)
    local w, h = image:getDimensions()
    if w < 1 or h < 1 or w > MAX_SIDE or h > MAX_SIDE then return nil end
    -- dpiscale is load-bearing: without it a phone at scale 3 hands back a
    -- canvas three times the size and the read below is a magnified corner.
    local ok, canvas = pcall(love.graphics.newCanvas, w, h, { dpiscale = 1 })
    if not ok then canvas = love.graphics.newCanvas(w, h) end
    local previous = love.graphics.getCanvas()
    love.graphics.push("all")
    -- No transform: this runs between frames, but a host that left one in
    -- place would put the picture somewhere other than 0,0 and the read would
    -- be of an empty canvas.
    love.graphics.origin()
    -- AND NO SHADER.  `push("all")` SAVES the state, it does not clear it, so
    -- whatever was last bound is still bound here -- and on Gold what was last
    -- bound is a GbcPalette remap.  The picture then reads back ALREADY
    -- COLOURED instead of as the four shades it is stored in, `field` picks
    -- the lightest by red out of the wrong palette, and the border flood finds
    -- nothing to cut.
    --
    -- That is the whole of "the ? still has its green background": the plate
    -- was being dropped correctly and the question mark's own field was never
    -- cut, because the readback that decides what to cut was looking at the
    -- green rather than at the shades underneath it.
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, 0, 0)
    love.graphics.setCanvas(previous)
    love.graphics.pop()
    return canvas:newImageData(), w, h
  end

  function self.imageFor(image)
    local hit = built[image]
    if hit ~= nil then return hit or nil end
    if not wanted[image] then
      wanted[image] = true
      queue[#queue + 1] = image
    end
    return nil
  end

  -- Said once, and only the first few.  A cut that is REFUSED looks exactly
  -- like one that never ran -- the picture keeps its square and nothing on
  -- screen says why -- which is what made the #DEX look untouched for two
  -- releases while the arm was working perfectly on every fixture.
  local told = 0
  local function refused(what, why)
    told = told + 1
    if told <= 4 then
      mod.log:warn("%s kept its square: %s", what, why)
    elseif told == 5 then
      mod.log:warn("...and more besides; the cut is refusing most of what it "
        .. "is handed, which is a rule rather than a picture")
    end
  end

  local function buildImage(image)
    built[image] = false
    local data, w, h = readImage(image)
    if not data then
      refused("a picture", "it could not be read back at its own size")
      return
    end
    local cutData = Cutout2.cut(data, w, h)
    if not cutData then
      refused("a picture", "it carries its own alpha, has only one colour, "
        .. "has too many to be cart art, or has no field the border can see")
      return
    end
    built[image] = toImage(cutData)
  end

  -- ------- a block, replayed
  --
  -- The first attempt RECORDED the blits -- image, quad, position -- and
  -- replayed them raw.  That came out GREYSCALE, and the reason is the whole
  -- shape of this problem: `TileSheet:draw` lays its tiles inside
  -- `GbcPalette.with(colors, body)` when the sheet has a palette, so the
  -- source pixels really are the 2bpp shades and the COLOUR is the shader.
  -- Replaying the blits without it draws exactly what is in the file.
  --
  -- So the block is replayed by calling the ENGINE'S OWN DRAW into a canvas
  -- instead: shaders, palettes, colour, flips and geometry are all its own,
  -- and nothing here knows or restates any of them.  It runs on the update,
  -- where binding a canvas is safe, and the wrap calls the base function
  -- directly so there is no recursion back through it.

  function self.blockFor(key)
    local hit = blocks[key]
    if hit ~= nil then return hit or nil end
    return nil
  end

  -- Remember a block to replay later.  Takes the engine's own function and
  -- the arguments it was called with, so the update can make the very same
  -- call.  Returns whether it was taken, which is only false when the block
  -- is already known or already waiting.
  function self.want(key, base, screen, args, ox, oy, w, h)
    if blocks[key] ~= nil or blockWanted[key] then return false end
    blockWanted[key] = true
    blockQueue[#blockQueue + 1] = { key = key, base = base, screen = screen,
      args = args, ox = ox, oy = oy, w = w, h = h }
    return true
  end

  local function buildBlock(job)
    blocks[job.key] = false
    blockWanted[job.key] = nil
    local w, h = job.w, job.h
    if w < 1 or h < 1 or w > MAX_SIDE or h > MAX_SIDE then return end
    local ok, canvas = pcall(love.graphics.newCanvas, w, h, { dpiscale = 1 })
    if not ok then canvas = love.graphics.newCanvas(w, h) end
    local previous = love.graphics.getCanvas()
    love.graphics.push("all")
    love.graphics.origin()
    -- Cleared for the same reason, and it costs nothing here: the replay is
    -- the ENGINE'S own draw, which binds whatever shader each tile wants.
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    -- The engine draws at the block's place on the SCREEN; the canvas holds
    -- only the block, so the screen is slid under it.
    love.graphics.translate(-job.ox, -job.oy)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    -- What the engine returned is what the cached path has to answer: the
    -- leader faces chain a tile id through eight calls.  Read off the call,
    -- never counted here.
    local drewOk, returned = pcall(job.base, job.screen, unpack(job.args))
    love.graphics.setCanvas(previous)
    love.graphics.pop()
    if not drewOk then return end
    if returned ~= nil then blockReturn[job.key] = returned end
    -- `true`: a gap in the replay is where the engine drew nothing, which is
    -- outside the figure rather than a reason to refuse.
    local cutData = Cutout2.cut(canvas:newImageData(), w, h, true)
    if not cutData then
      refused(tostring(job.key), "the replay had no field the border can see, "
        .. "or too many colours to be cart art")
      return
    end
    blocks[job.key] = toImage(cutData)
  end

  -- One picture per frame.  A trainer card asks for nine at once and a
  -- readback is not free; cutting them all on the frame the page opens is a
  -- stutter exactly where it would be noticed.
  function self.buildOne()
    local job = table.remove(blockQueue, 1)
    if job then buildBlock(job); return job.key end
    local image = table.remove(queue, 1)
    if image then wanted[image] = nil; buildImage(image); return image end
    return nil
  end

  function self.queued() return #queue + #blockQueue end
  self.cut = Cutout2.cut
  self.blockReturn = function(key) return blockReturn[key] end

  -- ------- the screens

  local MARK = "__gen1wildCutout2"

  local function installTrainerCard()
    local ok, TrainerCard = pcall(require, "src.ui.gen2.TrainerCard")
    if not (ok and type(TrainerCard) == "table") then return end
    if rawget(TrainerCard, MARK) then return end

    local function overBlock(base, key, ox, oy, w, h)
      return function(screen, ...)
        if not on() then return base(screen, ...) end
        local cut = self.blockFor(key)
        if cut then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(cut, ox, oy)
          return blockReturn[key]
        end
        self.want(key, base, screen, { ... }, ox, oy, w, h)
        return base(screen, ...)
      end
    end

    -- TrainerCard_PrintTopHalfOfCard: the 5x7 portrait at (14,1).  Its size is
    -- read off the screen rather than fixed, because `gfx.portraitWide` and
    -- `portraitTiles` are what the engine lays it out from.
    local basePortrait = TrainerCard.drawPortrait
    if type(basePortrait) == "function" then
      TrainerCard.drawPortrait = function(screen, ...)
        local wide = (screen.gfx and screen.gfx.portraitWide) or 5
        local high = math.floor(((screen.gfx and screen.gfx.portraitTiles)
          or 35) / wide)
        return overBlock(basePortrait, "portrait", 14 * 8, 1 * 8,
                         wide * 8, high * 8)(screen, ...)
      end
    end

    -- The eight leaders, each a 4x3 run of tiles starting at `first`.  Keyed
    -- by that run, so the eight are eight pictures and a leader that moves on
    -- the page keeps its cut.
    local baseFace = TrainerCard.drawLeaderFace
    if type(baseFace) == "function" then
      TrainerCard.drawLeaderFace = function(screen, first, tx, ty, ...)
        if not on() then return baseFace(screen, first, tx, ty, ...) end
        local key = "leader:" .. tostring(first)
        local cut = self.blockFor(key)
        -- The engine's own return is the NEXT tile id and the page chains its
        -- eight faces through it, so a cached draw must answer what the
        -- replayed call answered.  Never counted here: the loop lays four
        -- tiles then two rows of three, and deriving that was wrong by three
        -- on the first attempt.
        if cut and blockReturn[key] ~= nil then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(cut, tx * 8, ty * 8)
          return blockReturn[key]
        end
        -- A face is an L: row 0 is four columns wide and rows 1 and 2 are
        -- three, so the block is four by three and the column the engine never
        -- draws comes back transparent.
        self.want(key, baseFace, screen, { first, tx, ty, ... },
                  tx * 8, ty * 8, 4 * 8, 3 * 8)
        return baseFace(screen, first, tx, ty, ...)
      end
    end

    TrainerCard[MARK] = true
  end

  local function installDex()
    local okGbc, GbcPalette = pcall(require, "src.render.GbcPalette")
    local ok, PokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
    if not (ok and type(PokedexMenu) == "table") then return end
    if rawget(PokedexMenu, MARK) then return end
    local basePic = PokedexMenu.drawPic
    if type(basePic) ~= "function" then return end

    -- ------- the #DEX
    --
    -- THE LISTING IS NOT THE ENTRY, and `ownColors` is the cart's own name for
    -- the difference.  `Pokedex_InitMainScreen` sets wCurPartySpecies to -1, so
    -- the LISTING draws every row through PokedexQuestionMarkPalette -- the
    -- cart really does show a green mon on green there, and that green is
    -- Gold, not a box to be removed.  `Pokedex_InitDexEntryScreen` sets the
    -- real species and the ENTRY gets the mon's own two colours, whose colour
    -- 0 is the white slab this arm exists for.
    --
    -- Cutting both took the cart's green OFF the listing while leaving the
    -- entry's square exactly where it was: precisely backwards.  The listing
    -- is handed straight through now, and only the entry is cut.
    --
    -- On the entry the plate goes FIRST and unconditionally.  It is the
    -- square -- 56x56, the plate's exact size -- and whether a picture can be
    -- found and cut is a separate question that is no longer allowed to gate
    -- it.  That gate is why the question mark kept its green box through three
    -- releases: the one case with nothing to look up was the one case that
    -- returned early.
    PokedexMenu.drawPic = function(screen, row, tx, ty, ownColors, ...)
      if not on() then return basePic(screen, row, tx, ty, ownColors, ...) end

      -- Whichever picture the cart is about to lay, asked its way round: a
      -- SEEN row's own pic, and the question mark for anything else.  Entirely
      -- optional -- nil here means the plate still goes and the cart draws
      -- whatever it was going to draw on top of nothing.
      -- ------- two pictures, and they need OPPOSITE treatment
      --
      -- This is the distinction four releases went round in circles for, and
      -- the report that named it was "you figured out how to remove the
      -- backgrounds on the Pokemon, do it to the ? picture".
      --
      -- A DISCOVERED mon's white box did go, because the box there is the
      -- PLATE and dropping the plate is enough.  The undiscovered entry's
      -- green did not, because there the square is not the plate at all: it is
      -- the QUESTION MARK IMAGE'S OWN FIELD, baked into the picture and
      -- painted green by the question-mark palette.  Dropping the plate
      -- underneath it changes nothing you can see.
      --
      -- So the ? needs its picture cut, and a mon's must never be -- a mon's
      -- pic ANIMATES through a live handle, and a cut is a still, which is
      -- what froze it after the first frame.  0.32.79 fixed the animation by
      -- taking the substitution away from BOTH, which fixed the mon and put
      -- the ? straight back.
      --
      -- The ? is a static placeholder.  Cutting it is safe and is the whole of
      -- what is left to do here.
      local image, isPlaceholder
      if row and row.seen and row.species and type(screen.picFor) == "function" then
        local okPic, got = pcall(screen.picFor, screen, row.species)
        image = okPic and got or nil
      end
      if not image and type(screen.questionMark) == "function" then
        local okMark, mark = pcall(screen.questionMark, screen)
        image = okMark and mark or nil
        isPlaceholder = image ~= nil
      end

      -- ------- and the listing keeps its background, for EVERY picture
      --
      -- `ownColors` is the cart's own name for the two screens, and it decides
      -- this for a POKeMON and for the question mark alike -- "in the list it
      -- needs background, on the page no background, just like our Pokemon".
      --
      -- 0.32.83 made the question mark an exception to that, to reach it on
      -- the listing.  That was a workaround for a cut that could not succeed
      -- (see the field note in `Cutout2.cut`): with the cut fixed the
      -- exception is exactly the thing that takes the listing's green away, so
      -- it is gone and the rule is one line again.
      if not ownColors then
        return basePic(screen, row, tx, ty, ownColors, ...)
      end

      -- ------- the question mark IS cut, now that the cut can find its field
      --
      -- 0.32.82 keyed it instead, because the cut kept being refused.  Keying
      -- drops shade 0 -- the LIGHTEST -- and on this picture the lightest is
      -- the glyph, not the square: it was aimed at the same wrong end as the
      -- refusal, and did nothing visible for the same reason.
      --
      -- With the field taken from the border the cut succeeds, so the ? is cut
      -- like any other picture standing in a square.  Safe to cache: it is a
      -- static placeholder, unlike a POKeMON's pic, which is never cut here.
      local cut = isPlaceholder and self.imageFor(image) or nil

      local px, py = tx * 8, ty * 8
      local realRect = love.graphics.rectangle
      local dropped, sawSquare, rects = false, false, 0
      love.graphics.rectangle = function(mode, x, y, w, h, ...)
        rects = rects + 1
        if mode == "fill" and w == h and w >= 5 * 8 and w <= 7 * 8 then
          sawSquare = true
        end
        if not dropped and mode == "fill" and w == h
            and w >= 5 * 8 and w <= 7 * 8 and x == px and y == py then
          dropped = true
          return
        end
        return realRect(mode, x, y, w, h, ...)
      end
      local realDraw = love.graphics.draw
      if cut then
        love.graphics.draw = function(what, ...)
          if what == image then return realDraw(cut, ...) end
          return realDraw(what, ...)
        end
      end
      local okDraw, err = pcall(basePic, screen, row, tx, ty, ownColors, ...)
      love.graphics.rectangle, love.graphics.draw = realRect, realDraw

      -- ------- said once, because four releases of reasoning have not settled
      -- this and one line from a real cartridge would have
      --
      -- Everything this arm depends on is provable HERE -- it installs on a
      -- Gen 2 boot, the row is on, `ownColors` is true on the entry, and the
      -- plate is suppressed when the whole bundle is driven headlessly.  On
      -- the cartridge the square survives anyway, so one of those is false
      -- there and no amount of reading this end will say which.
      --
      -- So it reports what it actually saw, once per session: whether any
      -- square fill arrived at the pic's corner at all.  "seen=false" means
      -- the plate is not a `love.graphics.rectangle` on that engine and every
      -- fix aimed at one has been aimed at the wrong call; "seen=true,
      -- dropped=true" means it was suppressed and the green is something else
      -- drawing over it.
      if not self.toldDex then
        self.toldDex = true
        mod.log:warn("#DEX plate: wrap ran, ownColors=%s, square fill seen=%s, "
          .. "dropped=%s, rects=%d", tostring(ownColors and true or false),
          tostring(sawSquare), tostring(dropped), rects)
      end
      if not okDraw then error(err, 0) end
      return err
    end

    PokedexMenu[MARK] = true
  end

  -- ------- the SUMMARY page
  --
  -- Three white boxes on one screen, and three different reasons.
  local function installSummary()
    local okSum, SummaryMenu = pcall(require, "src.ui.gen2.SummaryMenu")
    if not (okSum and type(SummaryMenu) == "table") then return end
    if rawget(SummaryMenu, MARK) then return end
    local okGbc, GbcPalette = pcall(require, "src.render.GbcPalette")

    -- 1. THE PIC'S PLATE.  `drawPicBlock` fills a 7x7 block in the palette's
    --    colour 0 before the picture lands, exactly as the #DEX does -- so it
    --    is dropped exactly as the #DEX's is.  The picture itself is left
    --    alone: this one animates (`picAnimFrame`), and a cut is a still.
    local basePic = SummaryMenu.drawPicBlock
    if type(basePic) == "function" then
      SummaryMenu.drawPicBlock = function(screen, image, colors, quad, size)
        if not on() then return basePic(screen, image, colors, quad, size) end
        local realRect = love.graphics.rectangle
        local dropped = false
        love.graphics.rectangle = function(mode, x, y, w, h, ...)
          if not dropped and mode == "fill" and w == h
              and w >= 5 * 8 and w <= 7 * 8 and x == 0 and y == 0 then
            dropped = true
            return
          end
          return realRect(mode, x, y, w, h, ...)
        end
        local okDraw, err = pcall(basePic, screen, image, colors, quad, size)
        love.graphics.rectangle = realRect
        if not okDraw then error(err, 0) end
        return err
      end
    end

    -- 2. THE PAGE INDICATORS.  Three 2x2 swatches drawn from the stats sheet
    --    through their own colour, and the tile's own background is shade 0 --
    --    white -- so each coloured square sits on a white one.
    --
    --    KEYED here, and that is safe for these and not for the #DEX's
    --    question mark: a swatch is a block of colour whose field IS the
    --    lightest shade, which is the assumption the ? broke.  Nothing inside
    --    a swatch is shade 0, so there is no hole to punch.
    local baseSquare = SummaryMenu.drawPageSquare
    if type(baseSquare) == "function" and okGbc and type(GbcPalette) == "table"
        and type(GbcPalette.keyedWith) == "function" then
      SummaryMenu.drawPageSquare = function(screen, tx, ty, large, colors, ...)
        if not on() then
          return baseSquare(screen, tx, ty, large, colors, ...)
        end
        local realWith = GbcPalette.with
        GbcPalette.with = GbcPalette.keyedWith
        local okDraw, err = pcall(baseSquare, screen, tx, ty, large, colors, ...)
        GbcPalette.with = realWith
        if not okDraw then error(err, 0) end
        return err
      end
    end

    -- 3. THE WORDS ON THE COLOURED PAGES.  `drawPlacements` prints every label
    --    and number through `Chrome.printThrough` with the PAGE's palette, and
    --    that fills the cell behind each string with the palette's colour 0.
    --    On the cart that colour is the page's own pink, green or blue, so the
    --    words sit on the page in black.
    --
    --    The theme substitutes its paper and ink into any palette it is handed
    --    -- which is right for a box and wrong here: it turns every label into
    --    white-on-black on a pink page.  runtime/theme2.lua already has the
    --    opt-out this needs, built for the battle HUD, which it describes as
    --    "ink on a PHOTOGRAPH rather than ink in a box".  A coloured page is
    --    the same case, so the page palettes carry the same mark.
    --
    --    THE MARK HAS TO GO ON THE TABLE THE WORDS ACTUALLY TRAVEL IN, and
    --    0.32.86 put it on the wrong one.  `PAGE_PALETTES` is the cart's three
    --    constants, and the only thing that reads them is `drawPageSquare` --
    --    the three little swatches over the page arrows.  Every label and
    --    number on the page below goes through `lowerColors()`, which BUILDS A
    --    FRESH TABLE on each call out of PAGE_TINTS:
    --
    --        return { tint, tint, tint, { 0, 0, 0 } }
    --
    --    A constant marked once cannot reach a table that did not exist yet, so
    --    the mark never applied to a single word: paper went black, ink went
    --    white, and the labels stayed white-on-black boxes on a pink page.
    --    Reported twice -- "the words on the color should just be black font
    --    instead of in a black box with white words".
    --
    --    So the mark is stamped on the RESULT, which is the same one line the
    --    constants get and reaches the same three pages by the seam their words
    --    genuinely use.  It also carries the page's vertical divider and the
    --    exp bar's two caps, which take the same table through `pageTile` and
    --    are line art on the page for exactly the same reason.
    for _, palette in ipairs(SummaryMenu.PAGE_PALETTES or {}) do
      if type(palette) == "table" then palette.gen1wildUnthemed = true end
    end

    local baseLower = SummaryMenu.lowerColors
    if type(baseLower) == "function" then
      SummaryMenu.lowerColors = function(screen, ...)
        local colors = baseLower(screen, ...)
        if type(colors) == "table" then colors.gen1wildUnthemed = true end
        return colors
      end
    end

    SummaryMenu[MARK] = true
  end

  function self.install()
    installTrainerCard()
    installDex()
    installSummary()
    mod.hooks:wrap("core.update", function(nextLink, game, dt)
      if on() then
        local okBuild, problem = pcall(self.buildOne)
        if not okBuild then
          mod.log:warn("a picture could not be cut from its square: %s",
                       tostring(problem))
        end
      end
      return nextLink(game, dt)
    end)
    return true
  end

    return self
end

return Cutout2
