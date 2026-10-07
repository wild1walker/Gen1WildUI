-- Party icons that carry a colour, on Gold.
--
-- Gold draws every party icon through `GbcPalette.with(palettes.partyMenu[1],
-- paint)` -- a FOUR-SHADE remap that reads each pixel's red channel as one of
-- four shades and substitutes the palette's entry for it.  That is exactly
-- right for the cart's own 2bpp grayscale sheets and wrong for a mod's art: a
-- follower sprite carrying three colours of its own arrives with its shape
-- intact and its colours replaced by whichever party shade each luminance
-- landed on.
--
-- So the assertions are about WHICH draws keep the palette and which step
-- around it -- and, just as much, that stepping around one icon does not
-- leave the palette off for the rest of the frame.
--
-- Run:  luajit tests/icons2_test.lua

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
  local same = actual == expected
  if not same then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

-- ---------------------------------------------------------------- harness

-- Two files: one grey the way every cart icon is, one carrying colours of its
-- own the way a follower sheet does.
local FILES = {
  ["icons/grey.png"] = { { 0.0, 0.0, 0.0, 1 }, { 0.5, 0.5, 0.5, 1 },
                         { 1.0, 1.0, 1.0, 1 } },
  ["icons/follower.png"] = { { 0.0, 0.0, 0.0, 1 }, { 0.9, 0.4, 0.1, 1 },
                             { 1.0, 1.0, 1.0, 1 } },
  -- A colour hiding under a transparent pixel is not a colour anyone sees.
  ["icons/hidden.png"] = { { 0.0, 0.0, 0.0, 1 }, { 0.9, 0.1, 0.1, 0 } },
}
local reads = {}
package.loaded["src.render.Assets"] = {
  imageData = function(path)
    local pixels = FILES[path]
    if not pixels then error("no such file: " .. tostring(path), 0) end
    reads[path] = (reads[path] or 0) + 1
    return {
      getDimensions = function() return #pixels, 1 end,
      getPixel = function(_, x, _y)
        local p = pixels[x + 1]
        return p[1], p[2], p[3], p[4]
      end,
    }
  end,
}

local hookedPath
package.loaded["src.pokemon.Sprites"] = {
  iconPath = function(_data, _mon, path) return hookedPath or path end,
}

-- The palette binds, recorded: this is the whole question.
local binds
local GbcPalette = {
  with = function(_colors, body) binds[#binds + 1] = "palette"; return body() end,
  available = function() return true end,
}
package.loaded["src.render.GbcPalette"] = GbcPalette

local drawn
local PartyMenu = {}
PartyMenu.iconIdFor = function(_menu, mon) return mon and mon.iconId end
-- The engine's own draw, reduced to the one branch under test.
PartyMenu.drawIcon = function(menu, mon, px, py)
  drawn[#drawn + 1] = { mon = mon, px = px, py = py }
  local colors = menu.palettes and menu.palettes.partyMenu
    and menu.palettes.partyMenu[1]
  local function paint() binds[#binds + 1] = "blit" end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, paint)
  else
    paint()
  end
  return true
end

-- ------- the frame the clock asks for, and the CELL it turns into
--
-- The engine's own pick, reduced to the arithmetic: two frames off the
-- screen's clock (src/ui/gen2/PartyMenu.lua, ICON_FRAME_STEPS = 16).  Which
-- cell of the sheet each of those is, is the thing under test -- so the stub
-- images differ in the one property the rule reads, their height.
local SHEETS = {
  -- a cart icon: 16x32, exactly the two frames of one pose
  cart = { getHeight = function() return 32 end },
  -- Gen1Follower's: 16x96, six frames in the overworld order, so cell 1 is
  -- the mon facing AWAY and cell 3 is its south step
  follower = { getHeight = function() return 96 end },
}
-- A newer engine answers a third value, the icon's `trueColor`, which its
-- drawIcon reads to keep a full-colour icon off the palette shader; the stub
-- answers it for a mon that says so.
PartyMenu.iconFor = function(menu, mon)
  return SHEETS[(mon and mon.sheet) or "cart"],
         math.floor((menu.clock or 0) / 16) % 2,
         mon and mon.trueColor or nil
end

package.loaded["src.ui.gen2.PartyMenu"] = PartyMenu

local Icons2 = chunkOf("runtime/icons2.lua")

local logged = {}
local context = { mod = { log = setmetatable({}, { __index = function()
  return function(_, fmt) logged[#logged + 1] = tostring(fmt) end
end }) } }

eq(Icons2.install(context), true, "the wrap installs")
eq(Icons2.install(context), false, "and only once")

local menu = {
  icons = { icons = {
    GREY = { image = "icons/grey.png" },
    FOLLOWER = { image = "icons/follower.png" },
    HIDDEN = { image = "icons/hidden.png" },
  } },
  palettes = { partyMenu = { { { 0, 0, 0 }, { 90, 90, 90 },
                               { 170, 170, 170 }, { 255, 255, 255 } } } },
  game = { data = {} },
}
-- A real instance, because `pathFor` asks the menu for `iconIdFor` the way
-- `iconFor` does -- a bare table would answer nil and take every icon down
-- the ordinary path without the test noticing.
setmetatable(menu, { __index = PartyMenu })

local function draw(iconId)
  binds, drawn = {}, {}
  PartyMenu.drawIcon(menu, { iconId = iconId }, 8, 24)
end

-- ------------------------------------------------------------ the decision

do
  io.write("a grey icon keeps the cart's palette\n")
  draw("GREY")
  eq(#drawn, 1, "it draws")
  eq(binds[1], "palette",
     "through GbcPalette, which is what makes the whole list wear "
     .. "PartyMenuOBPals the way the hardware does")
  eq(binds[2], "blit", "and then blits")
end

do
  io.write("an icon with colours of its own keeps them\n")
  draw("FOLLOWER")
  eq(#drawn, 1, "it draws")
  eq(binds[1], "blit",
     "with no palette bound at all -- the four-shade remap would replace the "
     .. "three colours the file brought with whichever party shade each "
     .. "luminance landed on")
  eq(#binds, 1, "and nothing else")
end

do
  io.write("a colour under a transparent pixel is not a colour\n")
  draw("HIDDEN")
  eq(binds[1], "palette", "so the icon is still an ordinary grey one")
end

do
  io.write("the palette is put back for the next icon\n")
  -- GbcPalette is shared furniture: every other draw in the frame still wants
  -- it, so stepping around one icon must not leave it off.
  draw("FOLLOWER")
  eq(binds[1], "blit", "the colour icon steps around it")
  draw("GREY")
  eq(binds[1], "palette", "and the very next icon has it back")
  eq(GbcPalette.with ~= nil, true, "with the real function restored")
end

-- ------------------------------------------------------------- the reading

do
  io.write("a file is read once\n")
  reads = {}
  Icons2.forget()
  draw("FOLLOWER")
  draw("FOLLOWER")
  draw("FOLLOWER")
  eq(reads["icons/follower.png"], 1,
     "the answer is a property of the FILE, so it is remembered by path "
     .. "rather than asked again per mon")
end

do
  io.write("the pokemon.icon hook decides which file is read\n")
  -- A skin mod's replacement is the file that ends up on screen, so it is the
  -- file the question has to be asked of.
  Icons2.forget()
  hookedPath = "icons/follower.png"
  draw("GREY")
  eq(binds[1], "blit",
     "a grey icon a mod has replaced with colour art keeps the colour")
  hookedPath = nil
  Icons2.forget()
  draw("GREY")
  eq(binds[1], "palette", "and without the hook it is grey again")
end

do
  io.write("a mon with no icon at all still draws\n")
  Icons2.forget()
  draw("NOSUCH")
  eq(#drawn, 1, "the engine's own draw still runs")
  eq(binds[1], "palette", "on the cart's palette, which is the safe answer")
end

-- Resolved here rather than assumed.  Three test files in this suite have now
-- shipped assertions behind an `ENGINE` that was never a local in them -- nil,
-- so every read behind it was passed over in silence and the suite reported a
-- pass it had not earned.  An assertion that never runs is worse than no
-- assertion, because it looks like one.
local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    for _, name in ipairs({ "gen1recompog", "gen1recomp", "bryanthaboi/gen1recomp" }) do
      candidates[#candidates + 1] = prefix .. "/" .. name
    end
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/ui/gen2/PartyMenu.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
local function slurp(path)
  local handle = io.open(path)
  if not handle then return nil end
  local text = handle:read("*a") handle:close() return text
end
ok(ENGINE ~= nil, "an engine tree is found, so the reads below actually run")

-- ---- only the icon you are hovering walks
--
-- `iconFor` picks the frame off the screen's own clock, so every icon in the
-- list flips together -- "the sprites shouldn't play flipping between back and
-- forth, only the one I'm hovered over should play the walk south animation".
--
-- Which row is selected comes from the engine's own call order rather than a
-- copy of its loop: drawIcon is always reached as
-- `self:drawIcon(mon, self:iconX(i), ...)`, and iconX already answers "is this
-- the selected row" -- it is why the highlighted icon sits a tile right.
if ENGINE then
  local partySrc = assert(slurp(ENGINE .. "/src/ui/gen2/PartyMenu.lua"))
  -- Two engine shapes, both of them one clock: an older one divides by a
  -- fixed ICON_FRAME_STEPS, a newer one by the cart's HP-band speed for
  -- that POKeMON (`iconFrameSteps`).
  ok(partySrc:find("local frame = math.floor(self.clock / ICON_FRAME_STEPS) % 2",
                   1, true) ~= nil
     or partySrc:find("return math.floor(self.clock / PartyMenu.iconFrameSteps(mon)) % 2",
                      1, true) ~= nil,
     "every icon takes its frame from one clock, so they all flip together")
  ok(partySrc:find("self:drawIcon(mon, self:iconX(i)", 1, true) ~= nil,
     "and iconX(i) is called immediately before each drawIcon")
  ok(partySrc:find("return index == self.index and 8 or 0", 1, true) ~= nil,
     "where it already decides whether this row is the selected one")

  local src = assert(slurp("runtime/icons2.lua"))
  ok(src:find("menu.gen1wildAnimate = (index == menu.index)", 1, true) ~= nil,
     "so the row is taken from iconX rather than re-derived")
  ok(src:find("if image and not menu.gen1wildAnimate then return image, 0, ... end",
              1, true) ~= nil,
     "and an unhovered icon rests on frame 0 -- the pose the cart draws "
     .. "between flips, not a second one")

  -- The Gold box borrows a PartyMenu purely as an icon renderer, so it never
  -- reaches iconX and has to name its own hovered cell.
  local boxSrc = assert(slurp("modules/Gen1BillsBox/gen2screen.lua"))
  ok(boxSrc:find("local ok, icons = pcall(PartyMenu.new", 1, true) ~= nil,
     "the Gold box draws its icons through a borrowed PartyMenu")
  ok(boxSrc:find("local selected = self.pane == \"box\" and self.boxSlot == cell",
                 1, true) ~= nil,
     "so it names the hovered grid cell itself")
  ok(boxSrc:find("local selected = self.pane == \"party\" and self.partySlot == row",
                 1, true) ~= nil,
     "and the hovered party row")
  ok(boxSrc:find("self.icons.gen1wildAnimate = selected and true or false",
                 1, true) ~= nil,
     "and hands that one flag to the renderer, in one place")
  -- The POKeMON in your hand is drawn BY the grid, in the cell the cursor is
  -- on, rather than by a second pass over the top of it -- so "the one you are
  -- watching" and "the one in your hand" are the same icon and need no second
  -- rule.  See tests/boxfree_gen2_test.lua.
  ok(boxSrc:find("function Screen:drawHeld", 1, true) == nil,
     "and there is no separate held-POKeMON pass left to disagree with it")
  ok(boxSrc:find("function Screen:monDrawnAt", 1, true) ~= nil,
     "...because monDrawnAt puts the carried POKeMON in the cell instead")

  -- ------- and at the cart's own speed
  --
  -- The box drives the borrowed renderer's clock from its own counter.  That
  -- used to be DOUBLED, to match the Gen 1 box's ANIM_STEPS = 8 -- but Red's
  -- box animates by mirroring one frame, and Gold's icons are a two-pose
  -- walk, so eight steps of Gold's is the walk at double speed.  The box also
  -- draws a party column, so the same POKeMON walked at one speed there and
  -- another in PARTY MENU.
  ok(boxSrc:find("self.icons.clock = self.ticks\n", 1, true) ~= nil
       or boxSrc:find("self.icons.clock = self.ticks end", 1, true) ~= nil,
     "the box hands the renderer its own tick count, undoubled")
  ok(boxSrc:find("self.icons.clock = self.ticks * 2", 1, true) == nil,
     "and nothing doubles it any more")

  -- The cadence, read rather than restated: a fixed 16 on an older engine,
  -- the cart's HP-band speed on a newer one -- the frameset's 8, plus 0x00,
  -- 0x40 or 0x80 by HP colour, plus one (engine/sprite_anims/core.asm).
  local fixed = tonumber(partySrc:match("ICON_FRAME_STEPS%s*=%s*(%d+)"))
  local duration = tonumber(partySrc:match("ICON_FRAME_DURATION%s*=%s*(%d+)"))
  ok(fixed or duration, "the engine's cadence is readable from the source")
  if fixed then
    eq(fixed, 16, "the cart flips a party icon every sixteen steps")
  else
    eq(duration, 8, "the frameset holds each frame eight steps before the "
       .. "HP band's offset")
  end
  -- A wrap would have to be a whole number of every one of those flips -- 16,
  -- or 9, 73 and 137 -- or the walk jumps once a cycle.  No small number is,
  -- so the box's counter does not wrap at all.
  ok(boxSrc:find("self.ticks = self.ticks + 1", 1, true) ~= nil,
     "the box's counter only counts up")
  ok(boxSrc:match("self%.ticks%s*=%s*%(self%.ticks%s*%+%s*1%)%s*%%") == nil,
     "and never wraps, so the walk has no seam to jump at")
end

do
  io.write("a six-frame sheet walks south instead of turning round\n")
  -- Reported as "it's supposed to be walk south not flip back and forth".
  -- Gold's iconFor answers 0 then 1, and drawIcon quads that as `frame * 16`
  -- -- the sheet's first two 16x16 cells.  On a 16x96 follower sheet those
  -- are STAND SOUTH and STAND NORTH, so the POKeMON turns to face you and
  -- away again on the spot.  Red has had the rule for this all along:
  -- PartyMenu.frameFor's fallback is `alt and ((ih or 0) >= 64 and 3 or 1)`.
  local hovered = setmetatable({ gen1wildAnimate = true }, { __index = PartyMenu })

  hovered.clock = 0
  local _, frame = PartyMenu.iconFor(hovered, { sheet = "follower" })
  eq(frame, 0, "a follower sheet rests on cell 0 -- standing, facing south")

  hovered.clock = 16
  _, frame = PartyMenu.iconFor(hovered, { sheet = "follower" })
  eq(frame, 3, "and steps to cell 3, the south walk -- not cell 1, the back")

  -- The cart's own icons must not move: 32 is not >= 64, so the rule does
  -- not fire and the two frames stay the two frames.
  hovered.clock = 0
  _, frame = PartyMenu.iconFor(hovered, { sheet = "cart" })
  eq(frame, 0, "a cart icon still rests on frame 0")
  hovered.clock = 16
  _, frame = PartyMenu.iconFor(hovered, { sheet = "cart" })
  eq(frame, 1, "and still alternates to frame 1, which is its only other one")

  -- An unhovered icon rests, whatever its sheet -- and cell 0 is standing,
  -- facing south, on both shapes, so the two rules agree without talking.
  local still = setmetatable({ clock = 16 }, { __index = PartyMenu })
  _, frame = PartyMenu.iconFor(still, { sheet = "follower" })
  eq(frame, 0, "an unhovered follower icon stands still, facing south")
  _, frame = PartyMenu.iconFor(still, { sheet = "cart" })
  eq(frame, 0, "and so does an unhovered cart icon")

  -- Whatever the engine answers after the frame comes back as it came: a
  -- newer engine's `trueColor` third is what keeps a full-colour icon off
  -- the four-shade remap, and a wrap that kept two values lost it.
  local trueColor
  _, frame, trueColor = PartyMenu.iconFor(still, { sheet = "cart", trueColor = true })
  eq(trueColor, true, "a still icon keeps the engine's third answer")
  _, frame, trueColor = PartyMenu.iconFor(hovered, { sheet = "follower", trueColor = true })
  eq(trueColor, true, "and so does a walking one")
  eq(select("#", PartyMenu.iconFor(still, { sheet = "cart" })), 3,
     "and an answer of nil still comes back in its place")
end

-- ---- the engine's INLINE bind
--
-- Everything above stands the engine's draw up the way it used to be written:
-- `GbcPalette.with(colors, paint)`.  The frame-time pass in 0.3.5x rewrote it
-- -- "GbcPalette.with without the closure: set, draw, restore" -- so the live
-- `drawIcon` calls `GbcPalette.use(colors)`, draws, and puts the previous
-- shader back.  A wrap that swapped `with` alone stopped reaching it, and
-- every colour icon went back through the four-shade remap with nothing to
-- say so.  The same decisions, against that shape.

if ENGINE then
  local partySrc = slurp(ENGINE .. "/src/ui/gen2/PartyMenu.lua") or ""
  local body = partySrc:match("function PartyMenu:drawIcon%(.-\nend\n") or ""
  ok(body:find("GbcPalette.use(colors)", 1, true) ~= nil
     or body:find("GbcPalette.with(", 1, true) ~= nil,
     "the engine's drawIcon binds through `use` or `with`, both of which "
     .. "the wrap now stands down")
end

do
  io.write("the inline bind: a colour icon still keeps its colours\n")
  local shader = nil
  _G.love = _G.love or {}
  love.graphics = love.graphics or {}
  love.graphics.getShader = function() return shader end
  love.graphics.setShader = function(s) shader = s end
  GbcPalette.use = function()
    binds[#binds + 1] = "palette"
    shader = "remap"
    return true
  end

  local Inline = {}
  Inline.iconIdFor = PartyMenu.iconIdFor
  Inline.iconFor = PartyMenu.iconFor
  -- Today's engine, reduced the same way the stub above is.
  Inline.drawIcon = function(menu, mon, px, py)
    drawn[#drawn + 1] = { mon = mon, px = px, py = py }
    local colors = menu.palettes and menu.palettes.partyMenu
      and menu.palettes.partyMenu[1]
    local shaded = colors and GbcPalette.available()
    local previous
    if shaded then
      previous = love.graphics.getShader()
      GbcPalette.use(colors)
    end
    binds[#binds + 1] = shader and ("blit:" .. shader) or "blit"
    if shaded then love.graphics.setShader(previous) end
    return true
  end
  package.loaded["src.ui.gen2.PartyMenu"] = Inline
  local Fresh = chunkOf("runtime/icons2.lua")
  eq(Fresh.install(context), true, "the wrap installs on the inline shape")
  local inlineMenu = setmetatable({
    icons = menu.icons, palettes = menu.palettes, game = menu.game,
  }, { __index = Inline })

  binds, drawn = {}, {}
  Inline.drawIcon(inlineMenu, { iconId = "FOLLOWER" }, 8, 24)
  eq(binds[#binds], "blit",
     "the follower is blitted with no remap bound -- it was `blit:remap` "
     .. "before the wrap learned about `use`")
  eq(shader, nil, "and the caller's shader is back afterwards")

  binds, drawn = {}, {}
  Inline.drawIcon(inlineMenu, { iconId = "GREY" }, 8, 24)
  eq(binds[1], "palette", "a grey icon still binds the cart's palette")
  eq(binds[2], "blit:remap", "and is blitted through it")
  eq(type(GbcPalette.use), "function", "with `use` itself put back")
end

io.write(("icons2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
