-- Gen1Dex on Crystal: the #DEX entry's picture animates, the way the SUMMARY
-- page's does.
--
-- Returns a factory: factory(mod, DexData) -> { install }.
--
-- ------- what this is
--
-- Crystal's front pics come with an animation -- a sheet of whole pictures and
-- a little scene program that walks them (`engine/gfx/pic_animation.asm`).
-- The engine already drives it in one place, `src/ui/gen2/SummaryMenu.lua`:
--
--     self.picAnim = MonAnimView.start(def, mon, "menu", loader)
--     if anim:step() then self.picAnim = nil end     -- one frame per update
--     local sheet, quad, size = anim:frame()
--
-- `MonAnimView` is a general runner, not the summary's own -- the egg hatch,
-- the evolution and the trade all start one -- so the #DEX simply starts one
-- too.  Nothing about the animation is re-implemented here; this file is the
-- three calls above, on the entry screen, plus the rule for when to start.
--
-- ------- and it is the cartridge's behaviour, not an addition
--
-- Crystal animates the pic when a #DEX entry opens.  Gold and Silver do not,
-- because their caches carry no `anim` row at all -- `MonAnimView.animData`
-- returns nil for them and `start` gives back nil, so on those two carts every
-- line below is a no-op and the static picture is drawn exactly as before.
-- That is why this needs no per-cart branch: the DATA decides.
--
-- ------- when it starts, and when it stops
--
-- Once, on the frame the entry opens, and again whenever the entry is showing
-- a different POKeMON -- which is the cart's rule (`Pokedex_InitDexEntryScreen`
-- runs the animation as it draws) and also the only one that does not restart
-- the picture under someone reading the text.  The runner reports when the
-- scene ends and the animation is dropped there, so the entry settles on the
-- base picture and stays on it.
--
-- The LISTING is left alone.  Its pic changes on every cursor step, so an
-- animation there would be a picture that never finishes starting.
--
-- ------- how the frame reaches the screen
--
-- `PokedexMenu:drawPic` lays ONE image and works out where from its width:
--
--     local tiles = math.floor(image:getWidth() / 8)
--     local pad = PIC_PAD[tiles] or PIC_PAD[7]
--     G.draw(image, (tx + pad[1]) * 8, (ty + pad[2]) * 8)
--
-- so the animation frame is put in that draw's place rather than drawn beside
-- it: the padding, the palette, the plate and the block are all the cart's own
-- arithmetic, untouched.  The swap is refused unless the frame is the SAME
-- SIZE as the still it replaces -- a 6x6 frame dropped into a 7x7 pic's
-- placement would sit a tile off, and the sheet's tile count is the one thing
-- that could differ from the picture's.

return function(mod, DexData)
  local self = {}

  local MARK = "__gen1DexGen2Anim"

  local function engineModule(name)
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" then return module end
    return nil
  end

  function self.install()
    local PokedexMenu = engineModule("src.ui.gen2.PokedexMenu")
    local MonAnimView = engineModule("src.render.MonAnimView")
    local Assets = engineModule("src.render.Assets")
    if not (PokedexMenu and MonAnimView and Assets) then
      mod.log:warn("no PokedexMenu/MonAnimView; the #DEX picture stays still")
      return false
    end
    if rawget(PokedexMenu, MARK) then return true end
    if type(MonAnimView.start) ~= "function" then
      mod.log:warn("src.render.MonAnimView has no start(); the #DEX picture "
        .. "stays still")
      return false
    end
    local baseUpdate = PokedexMenu.update
    local basePic = PokedexMenu.drawPic
    if type(baseUpdate) ~= "function" or type(basePic) ~= "function" then
      mod.log:warn("src.ui.gen2.PokedexMenu has no update/drawPic; the #DEX "
        .. "picture stays still")
      return false
    end

    local function enabled()
      return mod.options:get("dex_anim") ~= false
    end

    -- The same cache the screen loads its own pictures through, so an
    -- animation sheet is read once and shares the entry's own lifetime.
    local function loader(screen)
      return function(path)
        if type(path) ~= "string" then return nil end
        screen.picCache = screen.picCache or {}
        local cached = screen.picCache[path]
        if cached == nil then
          local ok, image = pcall(Assets.image, path)
          cached = ok and image or false
          screen.picCache[path] = cached
        end
        return cached or nil
      end
    end

    -- Reported once and stood down from, the way the theme is: this runs on
    -- every frame of the entry, and a broken animation should cost the
    -- movement rather than the #DEX.
    local broken = false

    local function startFor(screen, row)
      screen.gen1dexAnim = nil
      if not (row and row.seen and row.species) then return end
      local def = screen.pokemon and screen.pokemon[row.species]
      if type(def) ~= "table" then return end
      -- `mon` is nil: it is only read for UNOWN's letter, and the #DEX draws
      -- the form the player FIRST saw rather than a live mon's.  Letter A's
      -- animation is what `def.anim` already is, which is the same picture
      -- `picFor` falls back to.
      local ok, anim = pcall(MonAnimView.start, def, nil, "menu", loader(screen))
      screen.gen1dexAnim = ok and anim or nil
    end

    -- `PokedexMenu:update(_dt)` takes the delta and nothing else, so there is
    -- no varargs to forward -- and one could not be reached from inside the
    -- closure below in any case.
    PokedexMenu.update = function(screen, dt)
      if broken or not enabled() then return baseUpdate(screen, dt) end
      local ok, problem = pcall(function()
        -- Read BEFORE the cart's update, so opening the entry is noticed on
        -- the frame the press lands rather than one later.
        local before = screen.view
        local result = baseUpdate(screen, dt)
        local row = screen.current and screen:current() or nil
        local key = screen.view == "entry" and row and row.species or nil
        if key ~= screen.gen1dexAnimKey or before ~= screen.view then
          screen.gen1dexAnimKey = key
          if key then startFor(screen, row) else screen.gen1dexAnim = nil end
        end
        -- One scene command per update, which is what AnimateFrontpic's own
        -- loop does; the runner says when the scene has ended.
        local anim = screen.gen1dexAnim
        if anim and anim.step then
          local doneOk, finished = pcall(anim.step, anim)
          if not doneOk or finished then screen.gen1dexAnim = nil end
        end
        return result
      end)
      if not ok then
        broken = true
        screen.gen1dexAnim = nil
        mod.log:warn("the #DEX animation stood down for this session: %s",
                     tostring(problem))
        return baseUpdate(screen, dt)
      end
      return problem
    end

    PokedexMenu.drawPic = function(screen, row, tx, ty, ownColors, ...)
      -- The ENTRY only: `ownColors` is the cart's own name for it, and the
      -- listing's pic changes on every cursor step.
      local anim = (not broken) and enabled() and ownColors and screen.gen1dexAnim
      if not anim then return basePic(screen, row, tx, ty, ownColors, ...) end
      local okFrame, sheet, quad, size = pcall(anim.frame, anim)
      if not (okFrame and sheet and quad) then
        return basePic(screen, row, tx, ty, ownColors, ...)
      end
      local still = row and row.species and screen.picFor
        and select(2, pcall(screen.picFor, screen, row.species)) or nil
      -- Same size or nothing: the placement is worked out from the still's
      -- width, so a frame of another size would sit a tile off.
      if not (still and still.getWidth and size == still:getWidth()) then
        return basePic(screen, row, tx, ty, ownColors, ...)
      end

      local realDraw = love.graphics.draw
      love.graphics.draw = function(what, ...)
        if what == still then return realDraw(sheet, quad, ...) end
        return realDraw(what, ...)
      end
      local okDraw, err = pcall(basePic, screen, row, tx, ty, ownColors, ...)
      love.graphics.draw = realDraw
      if not okDraw then error(err, 0) end
      return err
    end

    PokedexMenu[MARK] = true
    mod.log:info("the #DEX entry's picture animates on Crystal")
    return true
  end

  return self
end
