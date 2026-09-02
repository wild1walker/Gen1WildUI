-- Gen1ModernBag: the item icons.
--
-- Returns a factory: factory(mod) -> a table of helpers.
--
-- The same file Gen1ItemInfo carries, and carried rather than depended on for
-- the reason that suite gives everywhere else it copies sixty lines: a Bag
-- that refuses to draw a picture until you also install an item-description
-- mod is a worse trade than a second copy of a loader.  Anything changed here
-- should be changed there.  The assets under assets/items/ are the same set
-- and are built by the same script.
--
-- ------- what an icon is
--
-- A 16x16 PNG under assets/items/, named for the item id in lower case:
-- POTION is potion.png, MAX_ELIXER is max_elixer.png.  Nothing lists them
-- here.  The folder IS the list -- an id with no file is an item with no
-- icon, which is a blank column and not an error -- so adding one is dropping
-- a PNG in, and a mod that adds an item can be given an icon without this
-- file learning its name.
--
-- Sixteen because that is the height of a list row.  Every list in this game
-- puts its rows sixteen pixels apart, the mart's and the item PC's and the
-- bag's alike, and an icon taller than its row overlaps the one above it.
-- The art is Polished Crystal's, which draws items at 24, so
-- tools/make_item_icons.py is what steps it down and where the choice of
-- which of their icons stands for which Gen 1 item is written out.  See
-- CREDITS.md: the icons are that project's work, not this one's.
--
-- ------- the machines are the exception
--
-- Fifty TMs and five HMs, and there is no art for any of them anywhere.  So
-- they are the one thing here drawn rather than sourced: a disc in the colour
-- of the type of the move it teaches -- tm_fire.png, hm_water.png -- which is
-- how every generation since Gen 3 has drawn a machine, and the only thing
-- that tells TM24 from TM25 in a pocket of fifty-five four-letter rows.
--
-- The type is read off the MOVE, through the item's own `machine.move`, and
-- not off a table here.  Same reason main.lua builds a machine's description
-- that way: a mod that retunes what TM26 teaches would leave a hand-written
-- table lying, and this way it cannot.  A machine whose move has a type
-- nothing has drawn falls back to the plain tm.png / hm.png.
--
-- ------- an item may name its own
--
-- `data.items[id].icon`, if it is a string, is a path and it wins.  Which is
-- the same shape `description` has -- the field goes on the ITEM, so anything
-- can read it and anything can set it -- and it means a sprite pack, or a mod
-- that adds an item, can hand its own art to every screen in the suite
-- without this mod being told.  What is here is the fallback, not the rule.

return function(mod)

  local W, H = 16, 16
  local DIR = "assets/items/"

  -- The palette pass repaints the frame through the zone's four shades, and
  -- an icon is not four shades of anything.  Marking the rectangle it landed
  -- in is what exempts it -- the same call Gen1Dex marks a true-colour sprite
  -- with.  Absent on a build without it, which costs the icons their colour
  -- and nothing else.
  local okFX, PaletteFX = pcall(require, "src.render.PaletteFX")
  if not okFX then PaletteFX = nil end

  local C = { W = W, H = H }

  -- ------- the paper an icon sits on
  --
  -- These icons are pictures drawn ON PAPER.  All 106 draw their line work in
  -- pure black on transparency and carry no white at all -- the page is a
  -- POKe BALL's lower half, the white inside a TOWN MAP, the gap in a
  -- BICYCLE's frame -- so the paper is part of the picture rather than a
  -- background it happens to sit on.  On a dark page it has to come from
  -- somewhere, and the somewhere is here: the paper is BAKED INTO THE ART at
  -- load, as the icon's own silhouette.
  --
  -- Grow, flood, keep what the flood could not reach:
  --
  --   1. every opaque pixel grows by one in all eight directions.  That is
  --      the sticker edge, and it is also what CLOSES the outline -- these
  --      outlines are not closed, because on white paper they never had to
  --      be, and a bare flood leaks straight out through the gaps.  (It does:
  --      over the real POKe BALL a plain fill caught six pixels of 256.)
  --   2. flood the outside of the grown shape in from the border.
  --   3. anything the flood could not reach is inside the item.  Paint it
  --      opaque white.
  --
  -- One pixel of growth and not two.  Two closes bigger gaps but swells the
  -- shape until several icons fill their whole cell, which is the square this
  -- is here to stop being.  At one, none of the 106 fills its cell; the
  -- median covers about 70% of it, so every icon keeps a shape of its own.
  --
  -- Baked rather than drawn behind: it is one image and one draw, and the
  -- light page cannot tell (white on white).
  --
  -- THE BAKE IS HALF OF IT, and 0.14.0 shipped only that half.  It gives the
  -- icon paper of its own shape; it says nothing about the rest of the 16x16
  -- CELL, and the cell is what `markTrueColor` hands the renderer.  A marked
  -- rect is re-blitted RAW from the canvas, so whatever the screen cleared
  -- that cell to comes back with it -- and every screen these icons appear on
  -- clears to white.  Black silhouette, white paper, and a white square around
  -- it after all, sourced from the page instead of from a rectangle this file
  -- drew.
  --
  -- So the cell is painted the colour it is going to END UP first, and the
  -- icon goes on top of that.  Both halves: the matte is the cell, the bake is
  -- the paper, and what is left is a sticker on a page.
  local function bakePaper(data)
    local w, h = data:getDimensions()
    if w <= 0 or h <= 0 then return false end

    local function solid(x, y)
      local _, _, _, a = data:getPixel(x, y)
      return a > 0
    end

    -- 1. grow
    local grown = {}
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        if solid(x, y) then
          for dy = -1, 1 do
            for dx = -1, 1 do
              local nx, ny = x + dx, y + dy
              if nx >= 0 and ny >= 0 and nx < w and ny < h then
                grown[ny * w + nx] = true
              end
            end
          end
        end
      end
    end

    -- 2. flood the outside
    local outside, queue, head = {}, {}, 1
    local function push(x, y)
      if x < 0 or y < 0 or x >= w or y >= h then return end
      local key = y * w + x
      if outside[key] or grown[key] then return end
      outside[key] = true
      queue[#queue + 1] = x
      queue[#queue + 1] = y
    end
    for x = 0, w - 1 do push(x, 0); push(x, h - 1) end
    for y = 0, h - 1 do push(0, y); push(w - 1, y) end
    while head < #queue do
      local x, y = queue[head], queue[head + 1]
      head = head + 2
      push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1)
    end

    -- 3. what it could not reach is the item's own paper
    local painted = false
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        if not outside[y * w + x] and not solid(x, y) then
          data:setPixel(x, y, 1, 1, 1, 1)
          painted = true
        end
      end
    end
    return painted
  end

  -- The pixels of a file, or nil.  Two ways in because a mod reaches
  -- love.image directly on one build and through the engine's own resolver on
  -- another; either answers, and neither answering is not fatal -- the icon
  -- loads without its paper and draws the way it did before this existed.
  local function pixelsOf(path)
    if love and love.image and love.image.newImageData then
      local ok, data = pcall(love.image.newImageData, path)
      if ok and data then return data end
    end
    local okAssets, Assets = pcall(require, "src.render.Assets")
    if okAssets and type(Assets) == "table" and Assets.imageData then
      local ok, data = pcall(Assets.imageData, path)
      if ok and data then return data end
    end
    return nil
  end

  -- Every path asked for, hit or miss.  `false` is a file that is not there,
  -- and it is cached as hard as an image is: a pocket of fifty items with no
  -- icon would otherwise ask the filesystem for fifty missing files on every
  -- frame it is open.
  local images = {}

  local function load(path)
    local cached = images[path]
    if cached ~= nil then return cached or nil end
    local image
    -- through the pixels, so the item's own paper is baked in before the
    -- image is made
    local data = pixelsOf(path)
    if data then
      pcall(bakePaper, data)
      local ok, made = pcall(love.graphics.newImage, data)
      if ok and made then image = made end
    end
    if not image then
      local ok, made = pcall(love.graphics.newImage, path)
      if ok and made then image = made end
    end
    if image then
      -- Pixel art inside a 160x144 frame that is integer-scaled afterwards;
      -- anything but nearest turns a 16-pixel icon to soup.
      pcall(image.setFilter, image, "nearest", "nearest")
      images[path] = image
    else
      images[path] = false
    end
    return images[path] or nil
  end

  local function shipped(stem)
    return load(tostring(mod.path) .. "/" .. DIR .. stem .. ".png")
  end

  -- TM or HM off the id, which is what the engine itself does everywhere it
  -- needs to know (BagMenu's unsellable check, ShopMenu's), and the type off
  -- the move the machine carries.
  local function machine(game, def, id)
    local kind = id:find("^HM_") and "hm" or "tm"
    local moves = game and game.data and game.data.moves
    local move = moves and def.machine.move and moves[def.machine.move]
    local element = type(move) == "table" and move.type
    if type(element) == "string" and element ~= "" then
      local typed = shipped(kind .. "_" .. element:lower())
      if typed then return typed end
    end
    return shipped(kind)
  end

  -- for tests/itemicons_test.lua
  C.bakePaper = bakePaper

  -- The icon for an item, or nil.  Nil is an ordinary answer -- a badge has
  -- no icon, and neither does an item a mod added -- and the row is drawn
  -- without one.
  function C.of(game, id)
    if type(id) ~= "string" or id == "" then return nil end
    local items = game and game.data and game.data.items
    local def = items and items[id]

    if type(def) == "table" and type(def.icon) == "string" then
      local own = load(def.icon)
      if own then return own end
    end

    if type(def) == "table" and type(def.machine) == "table" then
      return machine(game, def, id)
    end

    return shipped(id:lower())
  end

  -- What a shade-0 pixel in this cell ENDS UP as: black on a dark page, white
  -- on a light one.  Asked of the theme rather than of its name, so a theme
  -- that grows another answer needs no change here, and absent on a build with
  -- no theme -- which is the white every screen already cleared to.
  local function matte(x, y, w, h)
    local theme = type(mod.theme) == "function" and mod.theme() or nil
    local colour = theme and type(theme.matte) == "function"
      and theme.matte() or nil
    if type(colour) ~= "table" then return end
    love.graphics.setColor(colour[1] / 255, colour[2] / 255, colour[3] / 255, 1)
    love.graphics.rectangle("fill", x, y, w, h)
  end

  -- White before the image or its colours come out multiplied by whatever the
  -- caller last set -- black leaves a silhouette, which is exactly what the
  -- chrome around these rows is drawing in.  Black again on the way out, so a
  -- caller can keep drawing text without knowing this happened.
  -- ------- and the pop-up standing on the list
  --
  -- A marked rectangle re-blits RAW once the pass composes -- AFTER anything
  -- drawn over it in the meantime.  The bag keeps drawing its rows while a
  -- menu is open on top of them (SORT, the item actions, TM/HM), so an icon
  -- under that menu came back on top of it: the icon punched through the
  -- box, with the matte's own dark cell around it.
  --
  -- Draw order cannot reach it, because the re-blit happens after all of it.
  -- So the MARK is what has to go -- and the matte with it, as a pair. A
  -- matte with no mark is a dark rectangle in the middle of a page, and the
  -- palette pass reads those pixels as the page's ink: a hole instead of an
  -- icon. That is the same pairing the party list makes for the same reason.
  --
  -- Both spellings of a box, because the engine has two: Menu.new keeps
  -- tx/ty/tw/th and TextBox keeps boxTx/boxTy/boxTw/boxTh.
  local function boxRect(state)
    local function tiles(tx, ty, tw, th)
      if type(tx) ~= "number" or type(ty) ~= "number" then return nil end
      if type(tw) ~= "number" or type(th) ~= "number" then return nil end
      if tw <= 0 or th <= 0 then return nil end
      return { x = tx * 8, y = ty * 8, w = tw * 8, h = th * 8 }
    end
    return tiles(state.tx, state.ty, state.tw, state.th)
        or tiles(state.boxTx, state.boxTy, state.boxTw, state.boxTh)
  end

  -- Every box a state ABOVE `self` is drawing.  Nothing below it and not
  -- itself: the list is what owns these icons.
  function C.coversOf(game, self)
    local stack = game and game.stack
    local states = type(stack) == "table" and stack.states or nil
    if type(states) ~= "table" then return nil end
    local out, above = nil, false
    for i = 1, #states do
      if states[i] == self then
        above = true
      elseif above and type(states[i]) == "table" then
        local rect = boxRect(states[i])
        if rect then
          out = out or {}
          out[#out + 1] = rect
        end
      end
    end
    return out
  end

  -- Does any of them lie over the cell about to be drawn at x, y?
  function C.covered(covers, x, y)
    if type(covers) ~= "table" then return false end
    for _, r in ipairs(covers) do
      if x < r.x + r.w and r.x < x + W
         and y < r.y + r.h and r.y < y + H then
        return true
      end
    end
    return false
  end

  function C.draw(image, x, y, covered)
    if not image then return end
    if covered then
      -- No matte and no mark: the icon is drawn plainly and the menu above it
      -- paints over it, which is what the player is looking at.
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, x, y)
      love.graphics.setColor(0, 0, 0, 1)
      return
    end
    -- The cell first, then the icon's own paper on top of it (see bakePaper).
    -- Only ever inside a rectangle about to be marked: a dark rectangle
    -- anywhere else is shade-3 pixels, which the theme would map to the
    -- page's INK and put a hole in the page.
    matte(x, y, W, H)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x, y)
    if PaletteFX and PaletteFX.markTrueColor then
      pcall(PaletteFX.markTrueColor, x, y, W, H)
    end
    love.graphics.setColor(0, 0, 0, 1)
  end

  -- Both at once, for the ordinary case.
  function C.drawFor(game, id, x, y, covered)
    local image = C.of(game, id)
    C.draw(image, x, y, covered)
    return image
  end

  return C
end
