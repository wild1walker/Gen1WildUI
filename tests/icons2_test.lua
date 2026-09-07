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
  ok(partySrc:find("local frame = math.floor(self.clock / ICON_FRAME_STEPS) % 2",
                   1, true) ~= nil,
     "every icon takes its frame from one clock, so they all flip together")
  ok(partySrc:find("self:drawIcon(mon, self:iconX(i)", 1, true) ~= nil,
     "and iconX(i) is called immediately before each drawIcon")
  ok(partySrc:find("return index == self.index and 8 or 0", 1, true) ~= nil,
     "where it already decides whether this row is the selected one")

  local src = assert(slurp("runtime/icons2.lua"))
  ok(src:find("menu.gen1wildAnimate = (index == menu.index)", 1, true) ~= nil,
     "so the row is taken from iconX rather than re-derived")
  ok(src:find("if image and not menu.gen1wildAnimate then return image, 0 end",
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
end

io.write(("icons2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
