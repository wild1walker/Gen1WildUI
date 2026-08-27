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

  -- Every path asked for, hit or miss.  `false` is a file that is not there,
  -- and it is cached as hard as an image is: a pocket of fifty items with no
  -- icon would otherwise ask the filesystem for fifty missing files on every
  -- frame it is open.
  local images = {}

  local function load(path)
    local cached = images[path]
    if cached ~= nil then return cached or nil end
    local ok, image = pcall(love.graphics.newImage, path)
    if ok and image then
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

  -- The icon for an item, or nil.  Nil is an ordinary answer: SURFBOARD has
  -- no icon, a badge has no icon, and the row is drawn without one.
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

  -- White before the image or its colours come out multiplied by whatever the
  -- caller last set -- black leaves a silhouette, which is exactly what the
  -- chrome around these rows is drawing in.  Black again on the way out, so a
  -- caller can keep drawing text without knowing this happened.
  function C.draw(image, x, y)
    if not image then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x, y)
    if PaletteFX and PaletteFX.markTrueColor then
      pcall(PaletteFX.markTrueColor, x, y, W, H)
    end
    love.graphics.setColor(0, 0, 0, 1)
  end

  -- Both at once, for the ordinary case.
  function C.drawFor(game, id, x, y)
    local image = C.of(game, id)
    C.draw(image, x, y)
    return image
  end

  return C
end
