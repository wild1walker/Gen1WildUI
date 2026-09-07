-- Party icons that carry a colour, on Gold.
--
-- ------- what is wrong
--
-- Every party icon on Gold is drawn through one palette:
--
--     local pals = self.palettes and self.palettes.partyMenu
--     local colors = pals and pals[1] or nil
--     if colors and GbcPalette.available() then
--       GbcPalette.with(colors, paint)      -- src/ui/gen2/PartyMenu.lua
--
-- and `GbcPalette.with` is a FOUR-SHADE remap: it reads each pixel's red
-- channel as one of four shades and substitutes the palette's entry for it.
-- That is exactly right for the cart's own icons, which are 2bpp grayscale
-- sheets, and it is what makes the whole party list wear `PartyMenuOBPals`
-- the way the hardware does (engine/gfx/color.asm:593-598).
--
-- It is wrong for a mod's art.  A follower sprite carrying three colours of
-- its own arrives with its SHAPE intact and its colours replaced by whichever
-- party-menu shade each one's luminance landed on.  Reported as "it's not
-- using my correct follower sprites in party and box", which is the honest
-- description: the sprites are there and they are the wrong colours.
--
-- ------- and why the cart never needed an escape from it
--
-- Because the cart has no colour icons.  Gold's battle pics DO have the
-- escape -- `pokemon.sprite`'s `trueColor` flag, which `BattleState:drawPic`
-- reads to skip the GBC remap for art that is already coloured -- and the
-- icon path simply never grew one.  So this is the same idea at the other
-- site, decided the same way Red's box decides it: by looking at the file.
--
-- ------- how it is decided
--
-- `colourful` asks one question of an image, once, and remembers it: does any
-- pixel have a red, green and blue that a grey ramp could not have produced?
-- Red's arm asks it in exactly these words (modules/Gen1BillsBox/screen.lua's
-- `scanPath`) and this is that function, moved to where BOTH games' screens
-- can reach the answer.
--
-- A file is a file, so the answer is cached by path rather than per mon and
-- costs one read of a 16x96 sheet on the frame a species first appears.
--
-- ------- and where it is applied
--
-- `PartyMenu.drawIcon` is the only place a Gold party icon is blitted, and
-- every screen that shows one goes through it: the party list, the box this
-- suite adds, and anything else that asks.  One wrap there is the whole fix,
-- and it is why this is a bundle runtime rather than a line inside PARTY MENU
-- -- the box's icons must not depend on whether that feature is switched on.
--
-- Nothing is repainted: the icon is still the engine's own draw, at the
-- engine's own coordinates, with the engine's own frame and held-item marker.
-- The only thing taken away is the palette, and only for a file that brought
-- colours of its own.

local Icons2 = {}

local PATCH_KEY = "__gen1wildColourIcons"

-- Two channels differing by more than a rounding step is a colour; anything
-- inside it is grey, and grey is what the four-shade remap is for.
local TOLERANCE = 0.02

local scanned = {}

function Icons2.colourful(path)
  if type(path) ~= "string" or path == "" then return false end
  local hit = scanned[path]
  if hit ~= nil then return hit end
  hit = false
  pcall(function()
    local Assets = require("src.render.Assets")
    local data = Assets.imageData(path)
    local w, h = data:getDimensions()
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = data:getPixel(x, y)
        if a > 0 and (math.abs(r - g) > TOLERANCE
                      or math.abs(g - b) > TOLERANCE) then
          hit = true
          return
        end
      end
    end
  end)
  scanned[path] = hit
  return hit
end

function Icons2.forget() scanned = {} end

-- The path `iconFor` is about to load, worked out the same way it works it
-- out.  Four lines of duplication, and deliberately those four: wrapping
-- `iconFor` instead would hand back the loaded Image, and an Image is the one
-- thing LOVE will not let this read pixels out of.
local function pathFor(menu, mon)
  if type(menu.iconIdFor) ~= "function" then return nil end
  local okId, iconId = pcall(menu.iconIdFor, menu, mon)
  if not okId then return nil end
  local entry = iconId and menu.icons and menu.icons.icons
    and menu.icons.icons[iconId]
  local path = entry and entry.image
  local okHook, Sprites = pcall(require, "src.pokemon.Sprites")
  if okHook and type(Sprites) == "table"
      and type(Sprites.iconPath) == "function" then
    local okPath, hooked = pcall(Sprites.iconPath,
      menu.game and menu.game.data, mon, path, { name = iconId })
    if okPath then path = hooked end
  end
  return path
end

function Icons2.install(context)
  local mod = context.mod

  local ok, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
  if not (ok and type(PartyMenu) == "table"
          and type(PartyMenu.drawIcon) == "function") then
    error("no src.ui.gen2.PartyMenu to draw colour icons through", 0)
  end
  local okGbc, GbcPalette = pcall(require, "src.render.GbcPalette")
  if not (okGbc and type(GbcPalette) == "table"
          and type(GbcPalette.with) == "function") then
    error("no src.render.GbcPalette to step around", 0)
  end

  if rawget(PartyMenu, PATCH_KEY) then return false end

  -- ------- only the one you are hovering walks
  --
  -- `iconFor` picks the frame off the screen's own clock:
  --
  --     local frame = math.floor(self.clock / ICON_FRAME_STEPS) % 2
  --
  -- so EVERY icon in the list flips between its two frames at once, all six
  -- stepping together.  Reported as "the sprites shouldn't play flipping
  -- between back and forth -- only the one I'm hovered over should play the
  -- walk south animation", which is what Red's box and party do: the row under
  -- the cursor animates and the rest stand still.
  --
  -- Which row that is comes from the engine's own call order rather than from
  -- a copy of its loop: `drawIcon` is always reached as
  --
  --     self:drawIcon(mon, self:iconX(i), 4 + (i - 1) * 16 + self:iconBob(i))
  --
  -- and `iconX(index)` already answers "is this the selected row" -- it is the
  -- reason the highlighted icon sits a tile further right.  So the row is
  -- taken there, and `iconFor` reads it back.
  --
  -- `gen1wildAnimate` is also the door for a screen that is NOT the cart's
  -- party list.  Gen1BillsBox's Gold box borrows a PartyMenu purely as an icon
  -- renderer, so it never calls `iconX` at all and would otherwise animate
  -- every cell; it sets the flag itself around the cell it is hovering.
  local baseIconX = PartyMenu.iconX
  if type(baseIconX) == "function" then
    PartyMenu.iconX = function(menu, index)
      menu.gen1wildAnimate = (index == menu.index)
      -- The row itself, for anyone who needs to know WHICH one is being drawn
      -- rather than just whether it is the selected one -- the carry's flash
      -- reads it (modules/Gen1Party/gen2carry.lua).  Recorded off the cart's
      -- own call rather than from a second copy of its loop.
      menu.gen1wildIconRow = index
      return baseIconX(menu, index)
    end
  end

  -- ------- and WHICH two frames the walk is
  --
  -- The other half of the same report -- "it's supposed to be walk south, not
  -- flip back and forth" -- and it is not about which icons animate but about
  -- which cells the animation uses.
  --
  -- Gold's `iconFor` picks `math.floor(clock / 16) % 2` and `drawIcon` quads
  -- it as `frame * 16`, so it always draws the sheet's FIRST TWO 16x16 cells.
  -- That is right for a cart icon, which is a 16x32 sheet holding exactly the
  -- two frames of one pose.  It is wrong for every replacement sheet in this
  -- suite: Gen1Follower's are 16x96, six frames in the overworld order
  --
  --     0 stand south   1 stand north   2 stand side
  --     3 walk  south   4 walk  north   5 walk  side
  --
  -- so cells 0 and 1 are the mon FACING YOU and then FACING AWAY.  Alternating
  -- them turns the POKeMON round and back on the spot, which is the flip.  The
  -- south walk is 0 and 3.
  --
  -- Red already knows this.  `PartyMenu.frameFor`'s fallback is
  --
  --     return alt and ((ih or 0) >= 64 and 3 or 1) or 0
  --
  -- -- a sheet 64 pixels or taller has more than two frames, so its alternate
  -- is cell 3 rather than cell 1.  Gold's icon path never got that rule.  This
  -- is that same line, at the same decision, asking the same question of the
  -- same thing: the sheet's own height.  A 16x32 cart icon is untouched
  -- because 32 is not >= 64.
  --
  -- It belongs in the engine, beside Red's copy, and it is worth moving there;
  -- until then it lives here, where every Gold screen that draws an icon --
  -- the party list, this suite's box, the dex -- goes through one function.
  local TALL_SHEET = 64        -- more than two 16px frames
  local WALK_SOUTH = 3         -- cell 3, the same one Red's fallback picks

  local function walkFrame(image, frame)
    if frame ~= 1 or not image then return frame end
    local ok, height = pcall(image.getHeight, image)
    if not ok or (height or 0) < TALL_SHEET then return frame end
    return WALK_SOUTH
  end

  Icons2.walkFrame = walkFrame

  local baseIconFor = PartyMenu.iconFor
  if type(baseIconFor) == "function" then
    PartyMenu.iconFor = function(menu, mon, ...)
      local image, frame = baseIconFor(menu, mon, ...)
      -- Frame 0 is the one the cart rests on, so a still icon is the icon the
      -- cart would draw between flips rather than a second pose.  It is also
      -- cell 0 on a six-frame sheet -- standing, facing south -- so a still
      -- icon needs nothing from the rule below.
      if image and not menu.gen1wildAnimate then return image, 0 end
      return image, walkFrame(image, frame)
    end
  end

  local base = PartyMenu.drawIcon
  local broken = false

  PartyMenu.drawIcon = function(menu, mon, px, py, ...)
    if broken or not mon then return base(menu, mon, px, py, ...) end
    local okPath, path = pcall(pathFor, menu, mon)
    if not (okPath and Icons2.colourful(path)) then
      return base(menu, mon, px, py, ...)
    end
    -- For the length of ONE icon, and put back on the raising path too:
    -- GbcPalette is shared furniture and every other draw in the frame still
    -- wants it.  Same discipline the arena keeps with `Chrome.paletteFill`.
    local realWith = GbcPalette.with
    GbcPalette.with = function(_colors, body) return body() end
    local drawn, problem = pcall(base, menu, mon, px, py, ...)
    GbcPalette.with = realWith
    if not drawn then
      broken = true
      mod.log:warn("colour party icons are off for this session: %s",
                   tostring(problem))
      return base(menu, mon, px, py, ...)
    end
    return problem
  end
  PartyMenu[PATCH_KEY] = true

  mod.log:info("party icons that carry a colour keep it")
  return true
end

return Icons2
