-- Which frames are pages, and the one that is a page only sometimes.
--
-- The bug, from a phone screenshot of the CONTINUE menu in DARK: a black
-- CONTINUE / NEW GAME box in the top left, a black PLAYER / BADGES / POKeDEX /
-- TIME box under it, and white paper in the corners neither of them reaches.
-- The boxes were themed and the page they sit on was not.
--
-- The title screen owns its frame and is not in Theme.PAGES, quite rightly:
-- for most of its life it is the logo, the mon and the version ribbon, and
-- reversing that would be vandalism.  But `TitleState:draw` opens with a white
-- fill of the whole screen and then `if self.menuOpen then return end`
-- (TitleState.lua:711-715) -- MainMenu's own ClearScreen, which wipes the
-- logo, the mon and the sprites before the border goes down.  From the moment
-- that menu opens there is no art on that screen at all.
--
-- So it is a page WHEN SOMETHING IS STACKED ON IT and a picture when it is
-- alone.  0.24.0 made it a page in both states and three things went wrong on
-- screen; see Theme.COVERED_PAGES for what and why it is not that any more.
--
-- Run:  luajit tests/titlepage_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end
local function load_(path, ...)
  return assert(load(assert(readFile(path)), "@" .. path))(...)
end

package.loaded["src.mods.ManagerState"] = { openOptions = function() end }

-- The art rects live on the shared PaletteFX table so both bundles' copies of
-- theme.lua read the same list (see ART_LIST); a stub is all that needs.
package.loaded["src.render.PaletteFX"] = {}

-- Enough of love.graphics to watch the skirt paint itself.
local fills = {}
love = {
  graphics = {
    setColor = function() end,
    rectangle = function(_, x, y, w, h)
      fills[#fills + 1] = { x = x, y = y, w = w, h = h }
    end,
  },
}

-- The two engine classes this file needs to be able to name.  Resolved by
-- require inside the theme, so standing them in here is enough to be matched
-- by getmetatable, which is how Theme.PAGES works on a real boot.
local TitleState = {}; TitleState.__index = TitleState
package.loaded["src.ui.TitleState"] = TitleState
local HallOfFame = {}; HallOfFame.__index = HallOfFame
-- The town map is a page AND a legend: registered so Theme.KEYED_PAGES can
-- resolve it the way it does on a real boot.
local TownMap = {}; TownMap.__index = TownMap
package.loaded["src.ui.TownMap"] = TownMap

local OptionSet = load_("runtime/optionset.lua")
local Theme = load_("runtime/theme.lua")

local lastMod, lastOptionSet
-- The `render.zones` handler of the theme built most recently.
local lastFrame

-- A DARK title screen is a title with something standing on it: TitleState's
-- own draw clears the art the moment its menu opens, so a covered title is a
-- page (Theme.COVERED_PAGES) and is themed. That is the screen every skirt
-- assertion below is about -- "black to row 135" is a themed screen -- and it
-- is now said out loud, because a skirt hides the seam against a shaded page
-- and is not painted where there is no page to shade.
local function onDarkTitle()
  if not lastFrame then return end
  local title = setmetatable({ sgbPalettes = true }, TitleState)
  local menu = { tx = 0, ty = 0, tw = 13, th = 10 }
  pcall(lastFrame, function(_, zones) return zones end,
        { stack = { states = { title, menu },
                    top = function() return menu end } }, nil)
end

local function themeOver()
  local stored = {}
  local mod = {
    id = "ui",
    options = { define = function() end,
                get = function(_, key) return stored[key] end,
                set = function(_, key, value) stored[key] = value end },
    log = { info = function() end, warn = function() end, error = function() end },
    hooks = { wrap = function(_, name, fn)
      -- Kept so a test can run a frame the way the engine does.  The skirt
      -- reads the live stack through this, because a mark happens while the
      -- frame is still drawing.
      if name == "render.zones" then lastFrame = fn end
    end },
  }
  local optionset = OptionSet.new()
  lastMod, lastOptionSet = mod, optionset
  local theme = Theme.new({ mod = mod, optionset = optionset })
  theme.defineRow()
  theme.write("dark")
  return theme
end

local GREYS = { {255,255,255}, {170,170,170}, {85,85,85}, {0,0,0} }
local LOGO2 = { {255,255,255}, {255,200,100}, {200,100,50}, {0,0,0} }
local MEWMON = { {255,255,255}, {255,180,180}, {200,80,80}, {0,0,0} }

-- PaletteFX.zone takes tile CORNERS, not a width and a height
-- (src/render/PaletteFX.lua:217-221).
local function zone(colors, tx1, ty1, tx2, ty2)
  return { colors = colors, x = tx1 * 8, y = ty1 * 8,
           w = (tx2 - tx1 + 1) * 8, h = (ty2 - ty1 + 1) * 8 }
end

-- TitleState:sgbPalettes with the menu open: three bands across the screen,
-- then a DMG-greys zone per visible titleUiBox (TitleState.lua:68-101).
local function titleZones()
  return {
    zone(LOGO2, 0, 0, 19, 7),
    zone(LOGO2, 0, 8, 19, 9),
    zone(MEWMON, 0, 10, 19, 17),
    zone(GREYS, 0, 0, 12, 9),      -- the CONTINUE menu's box
    zone(GREYS, 4, 7, 19, 16),     -- ContinueInfo's box
  }
end

-- The last zone covering a tile is the one that paints it.
local function paperAt(zones, col, row)
  local px, py, hit = col * 8, row * 8, nil
  for _, z in ipairs(zones) do
    if z.colors and px >= z.x and px < z.x + z.w
       and py >= z.y and py < z.y + z.h then
      hit = z
    end
  end
  return hit and hit.colors[1] or nil
end

local function everyTileDark(zones)
  for row = 0, 17 do
    for col = 0, 19 do
      local paper = paperAt(zones, col, row)
      if not paper or paper[1] > 127 then
        return false, ("tile %d,%d is %s"):format(col, row,
          paper and ("%02x"):format(paper[1]) or "unpainted")
      end
    end
  end
  return true
end

-- ------------------------------------------------------- the menu is up

do
  io.write("the CONTINUE menu is dark all the way into the corners\n")
  local theme = themeOver()
  local title = setmetatable({ sgbPalettes = true }, TitleState)
  -- src/ui/Menu.lua keeps its box in tx/ty/tw/th; ContinueInfo is a plain
  -- state carrying only titleUiBox, and draws its box with Font.drawBox
  local menu = { tx = 0, ty = 0, tw = 13, th = 10 }
  local info = { titleUiBox = { 4, 7, 19, 16 } }

  Theme.recordBox(0, 0, 13, 10)
  Theme.recordBox(4, 7, 16, 10)

  local out = theme.apply({ stack = { states = { title, menu, info } } },
                          titleZones())
  local dark, where = everyTileDark(out)
  ok(dark, "no white is left anywhere on the screen" .. (where and (" -- " .. where) or ""))

  -- The title's three colour bands are replaced by one black page rather
  -- than reversed, because its list does not open on a whole-screen zone
  -- (pageZones).  Nothing is lost by that here: with the menu open there is
  -- no art on the screen for those bands to be colouring.
  eq(#out, 3, "one page, and a panel for each of the two boxes")
  eq(out[1].w, 160, "the page covers the screen")
  eq(out[1].h, 144, "...all of it")
  eq(out[2].x, 0, "the CONTINUE menu's box")
  eq(out[2].w, 104, "...at its own width")
  eq(out[3].x, 32, "and ContinueInfo's, which no state describes")
  eq(out[3].w, 128, "...at the width it drew it")
end

-- --------------------------------------------------- the title is alone

do
  io.write("the title screen on its own is left as the picture it is\n")
  local theme = themeOver()
  local title = setmetatable({ sgbPalettes = true }, TitleState)
  local zones = titleZones()
  local out = theme.apply({ stack = { states = { title } } }, zones)

  eq(out, zones, "the list comes back by reference, untouched")
  eq(out[1].colors[1][1], 255, "the logo band keeps its paper")
  eq(out[3].colors[1][1], 255, "and so does the mon band")
end

-- ------------------------------------------- the ground, painted black

do
  io.write("a painted ground pins the bands' ink and lights the copyright\n")
  -- matte.lua serves TitleState's opening full-screen fill as a black page
  -- with the copyright row left white, and flags the state for the frame it
  -- did it on.  This is the other half: the bands keep colours 0, 1 and 2 --
  -- the logo, the ribbon and the mon keep their own colours, which is the
  -- whole reason this is painted rather than reversed -- and only colour 3,
  -- which is what a black page reads as, is pinned to black.
  local theme = themeOver()
  local title = setmetatable({ sgbPalettes = true,
                               __gen1WildDarkGround = true }, TitleState)
  local zones = {
    zone(LOGO2, 0, 0, 19, 7),
    zone(LOGO2, 0, 8, 19, 9),
    zone(MEWMON, 0, 10, 19, 17),
  }
  local out = theme.apply({ stack = { states = { title } } }, zones)

  eq(#out, 4, "the three bands, and one strip for the copyright row")
  ok(out ~= zones, "and a new list -- the state's own is never written into")
  eq(out[1].colors[2][2], 200, "the logo keeps colour 1 -- its yellow")
  eq(out[1].colors[3][1], 200, "...and colour 2, its drop shadow")
  eq(out[3].colors[2][1], 255, "and the mon keeps its own two as well")

  -- Both ends of the ramp, not just the ink end.  Colour 3 is what the
  -- painted page reads as; colour 0 is the OTHER white on this screen -- the
  -- logo and the ribbon are images with an opaque white field of their own,
  -- and 0.29.0 painted the page black and left two white rectangles exactly
  -- the size of that art.
  eq(out[1].colors[1][1], 0, "colour 0 is pinned black: the art's own paper")
  eq(out[1].colors[4][1], 0, "and colour 3: the page under it")
  eq(out[2].colors[1][1], 0, "the ribbon's white field goes too")
  eq(out[3].colors[1][1], 0, "...on every band, whatever the cart shipped")
  eq(out[3].colors[4][1], 0, "...both ends of it")

  eq(out[4].y, 136, "the strip is the copyright row")
  eq(out[4].h, 8, "...and only that row")
  eq(out[4].w, 160, "...all the way across")
  -- The plain greys, which is the IDENTITY palette: what the shader writes
  -- is what the canvas already holds.  That is the point of it.  matte.lua
  -- paints this row black with the rest of the ground and inverts the
  -- copyright art so its letters are light, and because raw and shaded are
  -- then the same pixels, the true-colour rect over the mon has nothing to
  -- show when the engine's outward scissor rounding spills it a row down.
  --
  -- 0.31.8 reversed this strip over white paper instead.  It looked right
  -- until that spill, which re-blitted the raw paper as a white bar across
  -- the copyright -- and painting the row black to hide it is the black bar
  -- the same player reported the release before.
  eq(out[4].colors[1][1], 255, "colour 0 is white, as drawn")
  eq(out[4].colors[4][1], 0, "and colour 3 black, as drawn: the strip is the "
    .. "identity, so the canvas shows through it either way")
end

do
  io.write("but once the art's paper is keyed out, its white comes back\n")
  -- Pinning colour 0 takes the field off the logo AND the highlight out of
  -- its letters -- the same shade, and a palette cannot tell them apart.
  -- matte.lua keys the border-connected paper to transparency instead, which
  -- the ART can tell apart, and reports that it did.  Then colour 0 is the
  -- highlight and pinning it is what made the logo flat.
  local theme = themeOver()
  local map = setmetatable({ sgbPalettes = true, __gen1WildDarkGround = true,
                             __gen1WildKeyedArt = true }, TitleState)
  local PAPER = { 255, 255, 255 }
  local zones = { { colors = { PAPER, { 255, 200, 100 }, { 200, 100, 50 },
                               { 0, 0, 0 } },
                    x = 0, y = 0, w = 160, h = 144 } }
  local out = theme.apply({ stack = { states = { map } } }, zones)
  eq(out[1].colors[1], PAPER, "colour 0 is left alone: that is the highlight")
  eq(out[1].colors[4][1], 0, "colour 3 is still pinned: that is the ground")
  eq(out[2].y, 136, "and the copyright row still gets its own reversed strip")

end

do
  io.write("and without the paint the picture is left exactly as it was\n")
  -- LIGHT, a build with no matte installed, or a frame the fill was not
  -- found on: the flag is the only thing that arms this, so the two halves
  -- cannot disagree about whether the ground is black.
  local theme = themeOver()
  local title = setmetatable({ sgbPalettes = true }, TitleState)
  local zones = { zone(LOGO2, 0, 0, 19, 7), zone(LOGO2, 0, 8, 19, 9),
                  zone(MEWMON, 0, 10, 19, 17) }
  local out = theme.apply({ stack = { states = { title } } }, zones)
  eq(out, zones, "the list comes back by reference")
end

-- ------------------------------------------------- a page with a legend

do
  io.write("the town map turns its ends over and leaves its legend alone\n")
  -- The bug, from a phone screenshot of LAVENDER TOWN on the map: the sea was
  -- where Kanto is and the coastline was wrapped in trees.  Reversing a
  -- palette turns all four colours over, which is right when the middle two
  -- are steps of a paper-to-ink ramp and wrong when they are a legend --
  -- colour 1 is the sea and colour 2 is the land, and a full turn swaps them.
  local theme = themeOver()
  local map = setmetatable({ sgbPalettes = true }, TownMap)
  local WHITE, SEA = { 255, 255, 255 }, { 90, 150, 240 }
  local LAND, INK = { 60, 190, 90 }, { 0, 0, 0 }
  local zones = { { colors = { WHITE, SEA, LAND, INK },
                    x = 0, y = 0, w = 160, h = 144 } }

  local out = theme.apply({ stack = { states = { map } } }, zones)
  eq(#out, 1, "one page, as it arrived")
  eq(out[1].colors[1][1], 0, "the paper goes black")
  eq(out[1].colors[4][1], 255, "and the ink white, like every other page")
  eq(out[1].colors[2], SEA, "the sea is still the sea")
  eq(out[1].colors[3], LAND, "and the land is still the land")
  ok(out[1].colors ~= zones[1].colors, "on a list of its own, as ever")
end

do
  io.write("and every other page still turns over whole\n")
  -- The middle two are a shadow on an ink-on-paper screen, and leaving them
  -- put would solarise it.  Only a page in KEYED_PAGES keeps them.
  local theme = themeOver()
  local hall = setmetatable({ sgbPalettes = true }, HallOfFame)
  local A, B = { 255, 255, 255 }, { 200, 60, 60 }
  local Cc, D = { 120, 30, 30 }, { 0, 0, 0 }
  local zones = { { colors = { A, B, Cc, D }, x = 0, y = 0, w = 160, h = 144 } }
  -- HallOfFame is not a page, so stand the list up as one the base rule finds
  local out = theme.apply({ stack = { states = { hall } } }, zones)
  eq(out, zones, "a picture is not a page and is not turned at all")

  eq(#Theme.KEYED_PAGES, 1, "one class carries a legend, with a reason beside it")
  eq(Theme.KEYED_PAGES[1], "src.ui.TownMap", "the town map")
  local named = false
  for _, page in ipairs(Theme.PAGES) do
    if page == "src.ui.TownMap" then named = true end
  end
  ok(named, "which is a PAGE as well -- keyed changes the turn, not the rule")
end

-- ------------------------------------- the skirt round true-colour art

do
  io.write("art gets a zone of its own, one pixel proud, black at both ends\n")
  -- The engine rounds a zone's scissor OUTWARD to whole framebuffer pixels,
  -- which is right for two shaded neighbours and wrong for the true-colour
  -- opt-out: that one draws the canvas RAW, so its overlap paints unshaded
  -- canvas over shaded pixels.  Just outside a matte the canvas is the white
  -- page -- and white is what shades TO black -- so every piece of art wore a
  -- one-pixel white rectangle.
  --
  -- No matte colour can fix it: reversing four shades is an involution with
  -- no fixed point.  So the art gets a palette instead, black at both ends,
  -- one pixel larger than the mark, and a black skirt painted in that ring.
  -- Black canvas under a palette that maps black to black is invisible.
  local theme = themeOver()
  local hall = setmetatable({ sgbPalettes = true }, HallOfFame)
  local box = { tx = 0, ty = 12, tw = 20, th = 6 }
  Theme.recordBox(0, 12, 20, 6)
  Theme.recordArt(40, 32, 16, 16)

  local out = theme.apply({ stack = { states = { hall, box } } },
                          { zone(MEWMON, 0, 0, 19, 17) })
  eq(#out, 3, "the picture, the box's panel, and the art's own zone")
  local art = out[#out]
  eq(art.x, 39, "a pixel proud on the left")
  eq(art.y, 31, "...and the top")
  eq(art.w, 18, "two pixels wider than the mark")
  eq(art.h, 18, "...and two taller")
  eq(art.colors[1][1], 0, "paper black, so the white page under the skirt "
    .. "reads black")
  eq(art.colors[4][1], 0, "and ink black, so the skirt itself reads black")
  ok(art == out[#out], "last of ours, so it wins over the panel it sits on -- "
    .. "and the engine splices the true-colour rect after us, so the art "
    .. "itself is still drawn raw")
end

do
  io.write("and it is drained every frame, themed or not\n")
  -- The wrapper cannot be asked to stop, so the one thing that must always
  -- happen is that somebody empties it -- or a LIGHT frame's marks would come
  -- back as zones on the next dark one.
  local theme = themeOver()
  theme.write("light")
  Theme.recordArt(8, 8, 16, 16)
  local zones = { zone(MEWMON, 0, 0, 19, 17) }
  eq(theme.apply({ stack = { states = {} } }, zones), zones,
    "LIGHT hands the list straight back")

  theme.write("dark")
  local hall = setmetatable({ sgbPalettes = true }, HallOfFame)
  local out = theme.apply({ stack = { states = { hall } } },
                          { zone(MEWMON, 0, 0, 19, 17) })
  eq(#out, 1, "and the mark it swallowed does not turn up a frame later")
end

-- ------------------------------- the ring, and what it must not cut

do
  io.write("a skirt only where the engine kept the mark\n")
  do
    -- The engine's own rule, and the whole reason this case exists:
    --
    --     local rects = currentPass and trueColorRects[currentPass]
    --     if not rects or w <= 0 or h <= 0 then return end
    --
    -- No pass current, no rect recorded.  The wrapper used to paint a skirt
    -- anyway -- it asked only whether the WORLD pass was running, and "not
    -- the world" is true of no-pass too -- so a mark made between passes left
    -- a black box with no true-colour rect inside it to be the reason for
    -- one.  That is the box a player reported round the overworld character
    -- on the way into a battle, in DARK, the only theme that paints a skirt
    -- at all.
    local PaletteFX = package.loaded["src.render.PaletteFX"]
    local passes, current = { ui = {}, world = {} }, nil
    PaletteFX.trueColorRects = function(name) return passes[name] or {} end
    PaletteFX.spriteRedrawPassActive = function() return current == "world" end
    PaletteFX.markTrueColor = function(x, y, w, h)
      local rects = current and passes[current]
      if not rects or w <= 0 or h <= 0 then return end
      rects[#rects + 1] = { colors = false, x = x, y = y, w = w, h = h }
    end

    local themed = themeOver()
    themed.install()
    themed.write("dark")
    onDarkTitle()

    local function skirted(pass)
      current = pass
      fills = {}
      PaletteFX.markTrueColor(40, 40, 16, 16)
      return #fills > 0
    end

    ok(skirted("ui"), "a UI-pass mark is skirted, which is what a skirt is for")
    ok(not skirted("world"),
      "a world-pass mark is not -- the world blits raw, with no seam to hide "
      .. "and a character on a lit map to draw a black ring round")
    ok(not skirted(nil),
      "and a mark made between passes is not, because the engine kept no "
      .. "rect for it to belong to")
  end

  io.write("the skirt goes round the outside of the art, not through it\n")
  -- One piece of art is not always one rectangle.  TitleState splits the
  -- mon's mark around the player standing in front of it -- a strip above, a
  -- strip below, a strip each side -- and a strip can be two pixels tall.  A
  -- one-pixel ring on both sides of a two-pixel strip is not a hairline
  -- guard, it is a black bar through the middle of a POKeMON.
  local theme = themeOver()
  theme.install()
  theme.write("dark")
  onDarkTitle()

  -- two rects sharing an edge at x = 40, the way a split mark does
  fills = {}
  Theme.recordArt(24, 32, 16, 16)
  Theme.recordArt(40, 32, 16, 16)
  theme.paintSkirts()

  local function painted(px, py)
    for _, f in ipairs(fills) do
      if px >= f.x and px < f.x + f.w and py >= f.y and py < f.y + f.h then
        return true
      end
    end
    return false
  end

  ok(painted(23, 40), "the outside of the union is skirted on the left")
  ok(painted(56, 40), "...and on the right")
  ok(painted(32, 31), "...and above")
  ok(painted(32, 48), "...and below")
  ok(not painted(39, 40), "but NOT on the shared edge, which is inside its "
    .. "neighbour and would be a black bar through the art")
  ok(not painted(40, 40), "...from either side of it")
  ok(not painted(32, 40), "and never inside a rect at all")

  -- drained, so the next frame starts clean
  theme.apply({ stack = { states = {} } }, {})
end

-- --------------------------------------- the ring stops at the copyright

do
  io.write("the skirt does not reach the copyright line\n")
  -- The title screen is black to row 135 and WHITE from 136: the copyright
  -- is the one strip left light on purpose.  The mon is drawn at
  -- `y = 136 - h` and the figure's box ends on the same line, so the bottom
  -- bar of both their rings lands exactly on row 136 -- a black bar painted
  -- straight through the copyright, which is what a player saw.
  local theme = themeOver()
  theme.install()
  theme.write("dark")
  onDarkTitle()

  fills = {}
  theme.clipArt(136)
  Theme.recordArt(40, 120, 16, 16)      -- a mon whose box ends at 136
  theme.paintSkirts()

  local function painted(px, py)
    for _, f in ipairs(fills) do
      if px >= f.x and px < f.x + f.w and py >= f.y and py < f.y + f.h then
        return true
      end
    end
    return false
  end

  ok(painted(48, 119), "the ring is still painted above the art")
  ok(painted(39, 128), "...and down its sides, as far as the clip")
  ok(not painted(39, 136), "but the sides stop at the copyright row")
  ok(not painted(48, 136), "and the bottom bar is not painted at all")

  -- and the zone half of the skirt is clipped with it, or the row's ink
  -- would be mapped to black even where no bar was painted
  local hall = setmetatable({ sgbPalettes = true }, HallOfFame)
  hall.__gen1WildDarkGround = true
  local out = theme.apply({ stack = { states = { hall } } },
                          { zone(MEWMON, 0, 0, 19, 17) })
  local art = out[#out]
  eq(art.y, 119, "the art zone still opens a pixel proud of the mark")
  eq(art.y + art.h, 136, "and ends on the copyright row rather than over it")
end

do
  io.write("and the clip is taken with the rects, so it is one frame only\n")
  -- Set while the dark title draws and cleared at `render.zones`, the way the
  -- rects are: every other screen is dark all the way down and a ring at the
  -- bottom of it is exactly what is wanted.
  local theme = themeOver()
  theme.install()
  theme.write("dark")
  onDarkTitle()
  theme.clipArt(136)
  theme.apply({ stack = { states = {} } }, {})

  fills = {}
  Theme.recordArt(40, 120, 16, 16)
  theme.paintSkirts()
  local low = false
  for _, f in ipairs(fills) do
    if f.y >= 136 then low = true end
  end
  ok(low, "the next screen's art is skirted all the way round")
  theme.apply({ stack = { states = {} } }, {})
end

-- ---------------------------------------------- pictures stay pictures

do
  io.write("a picture with a box on it themes the box and nothing else\n")
  -- The Hall of Fame, the intro, Oak's speech, the evolution and trade
  -- animations, the slots and the surfing minigame all own a frame and are
  -- all art.  None of them is named in COVERED_PAGES, so a box over one is a
  -- panel and the picture underneath is untouched.
  local theme = themeOver()
  local hall = setmetatable({ sgbPalettes = true }, HallOfFame)
  local box = { tx = 0, ty = 12, tw = 20, th = 6 }
  Theme.recordBox(0, 12, 20, 6)

  local zones = { zone(MEWMON, 0, 0, 19, 17) }
  local out = theme.apply({ stack = { states = { hall, box } } }, zones)

  eq(#out, 2, "the picture's own zone, and one panel")
  eq(out[1].colors[1][1], 255, "the picture is not reversed")
  eq(out[2].y, 96, "the box is")
  eq(out[2].colors[1][1], 0, "...and it is dark")
end

-- -------------------------------------------------- the map is still safe

do
  io.write("and the overworld is still nobody's page\n")
  local theme = themeOver()
  local world = { sgbPalettes = true }          -- no class, no marker
  local start = { tx = 9, ty = 0, tw = 11, th = 18 }
  Theme.recordBox(9, 0, 11, 18)

  local zones = { zone(MEWMON, 0, 0, 19, 17) }
  local out = theme.apply({ stack = { states = { world, start } } }, zones)

  eq(#out, 2, "the map's zone and the menu's panel")
  eq(out[1].colors[1][1], 255, "a map that goes dark is a map you cannot read")
end

-- ----------------------------------------- what the theme reads, and when

do
  io.write("the theme is read once, and again the moment anything writes it\n")
  -- `optionset.read` walks the live game's save, the mod's own option store
  -- and the row's fallbacks.  `self.skirt` asks for it on EVERY true-colour
  -- mark on the frame and then asks `self.matte`, which asks again -- a box
  -- screen with thirty icons was reading the same word off the save sixty
  -- times to draw one screen.
  local theme = themeOver()
  local reads = 0
  local base = lastOptionSet.read
  lastOptionSet.read = function(...)
    reads = reads + 1
    return base(...)
  end

  eq(theme.read(), "dark", "the value is what was written")
  local first = reads
  theme.read(); theme.read(); theme.read()
  eq(reads, first, "and asking three more times costs nothing")

  -- ------- and it is not stale, whoever writes
  --
  -- The OTHER bundle's menu and the test bench both move this row through
  -- `mod.exports.optionWrite`, which never comes through theme.lua at all.  A
  -- cache only this file could clear would leave the skirt drawing yesterday's
  -- colour on the frame the zones had already turned over -- the two
  -- disagreeing inside one frame, which is the shape of every hairline in this
  -- file's history.  So it is kept against `optionset.generation()`, which
  -- every write of every kind bumps.
  lastOptionSet.write(lastMod, "ui_theme", "light")
  eq(theme.read(), "light",
    "a write that went nowhere near this file is seen by the next read")

  lastOptionSet.write(lastMod, "ui_theme", "dark")
  eq(theme.read(), "dark", "...and back")

  -- and the frame boundary clears it too, for a loaded save that brings its
  -- own options along and writes nothing
  theme.forget()
  local before = reads
  theme.read()
  ok(reads > before, "forgetting makes the next read go and look")
end

-- ------------------------------------------------------------ the list

do
  io.write("the covered list names what it means to\n")
  eq(#Theme.COVERED_PAGES, 1, "one class, and a reason written beside it")
  eq(Theme.COVERED_PAGES[1], "src.ui.TitleState", "the title screen")
  for _, path in ipairs(Theme.COVERED_PAGES) do
    local named = false
    for _, page in ipairs(Theme.PAGES) do
      if page == path then named = true end
    end
    ok(not named, path .. " is covered OR a page, never both")
  end
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
