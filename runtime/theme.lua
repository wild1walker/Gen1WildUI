-- UI THEME: the same screens, in light or dark.
--
-- ------- what a theme is allowed to touch
--
-- Every full-screen page in this game is drawn in black and white, this
-- suite's own pages included, and it is black and white for a reason: the art
-- is the game's own four DMG shades, the boxes are the game's own border
-- glyphs, and the colour arrives afterwards, from the SGB pass.  A state exposes `sgbPalettes()` returning a list of
-- rectangles with a four-colour palette each; `Renderer:endFrame` blits the
-- finished 160x144 frame once per rectangle through a shader that maps the
-- four shades onto that palette.
--
-- So a theme here is not a repaint.  Nothing is redrawn, no screen is edited,
-- and no feature learns that themes exist.  One hook -- `render.zones`, which
-- is handed the finished zone list on the way to the blit -- swaps the four
-- colours each rectangle carries, and the same pixels come out a different
-- colour.  That is why DARK is cheap and why it cannot break a layout: a
-- theme that cannot move a glyph cannot move a glyph off the screen.
--
-- ------- which frames are "ours"
--
-- The hook sees every frame, including the overworld and every battle, and
-- must answer for the UI only.
--
-- The first version of this file decided by looking at the zone list alone: a
-- frame that opened on ONE WHOLE-SCREEN ZONE OF THE FOUR DMG GREYS was a
-- black-and-white page and everything else was left alone.  That rule was
-- wrong, and wrong in the way that costs the most -- it never fired.  The
-- engine's UI screens do not ask for the greys; they ask for a NAMED palette
-- and let the SGB pass colour them, which is the whole point of the pass:
--
--     OptionsMenu / ListMenu / ManagerState / NamingScreen / TrainerCard
--         PaletteFX.wholeNamed(game.data, "MEWMON")
--     PokedexMenu / DexEntryMenu     ... "BROWNMON"
--     PartyMenu                      ... "GREENBAR", then a zone per party row
--     TownMap                        ... "TOWNMAP"
--
-- None of those is the four greys, so UI THEME declined every screen in the
-- game and DARK did nothing at all.  Every SGB background palette in the pack
-- is built the same way, though -- an off-white paper at colour 0 and a near
-- black at colour 3, with the screen's own hue in the two between -- so the
-- page is not identified by its colours.  It is identified by WHOSE it is:
--
--     the topmost state on the stack that either says what it is
--     (`state.gen1wildTheme`) or is one of the engine UI classes named in
--     `Theme.PAGES` is the page, and the frame is that page's.
--
-- The walk stops early on purpose.  A state that OWNS the frame's zones and
-- is neither of those two things -- the overworld, a battle, the title screen
-- -- ends the search: whatever is under it is not what is on the screen, so
-- the frame is not ours.  An overlay that owns no zones (a text box, a fade)
-- is stepped over, which is what keeps a confirm box on top of the OPTION
-- screen from un-theming it.
--
-- An allowlist rather than a denylist, and of classes rather than names: the
-- suite's replacements keep the engine's own instance and swap only its draw
-- methods, so `getmetatable(state)` is still the engine's class and the match
-- is exact.  A screen this file has not been taught about is left looking
-- exactly as it looks today, which is the failure everyone can live with.
--
-- The old zone-shape rule is kept as a THIRD way in, for a screen from some
-- other mod that really does open on whole-screen greys.  It costs one
-- comparison and it means a mod's page can be themed without this file
-- learning its name.
--
-- ------- what a page is, once it is ours
--
-- Normally the page IS the frame's first zone: the state we found is the one
-- Game asked for palettes, and it returned a whole-screen zone.  When it did
-- not -- a screen that returns nil under some condition, or one that declares
-- no palettes at all and inherits whatever is beneath it -- the theme
-- SYNTHESISES a whole-screen page of the DMG greys instead of transforming a
-- list that belongs to a screen nobody can see.  Every class in `Theme.PAGES`
-- is opaque, so there is nothing behind it to preserve.
--
-- ------- one honest limit
--
-- This works by changing the colours a zone carries, so it works in the
-- display modes that USE them.  ADVANCED is the one it is built for and
-- tested against; SGB, SGB INV and OG RED pass a zone's colours through the
-- same way.  The flat modes -- OG, OG INV, CLASSIC, and a custom ramp -- are
-- the player asking for one palette over the whole game, and
-- `PaletteFX.effectiveColors` replaces every zone's colours to give it to
-- them.  A theme cannot outrank that and should not try: OG INV already IS
-- dark mode for the whole screen.
--
-- ------- the two
--
--   LIGHT     the identity.  The hook returns the list it was handed, by
--             reference, so a light boot is byte-identical to a build with
--             no theme in it at all.  This is the default and stays it.
--   DARK      every zone reversed, lightest for darkest.  Paper black, ink
--             white, and the shades between them swapped in place -- which
--             is the whole of "our UI is black and white, swap the two",
--             and is exactly what the engine's own SGB INV display mode does
--             to the whole game.  Doing it per zone is what keeps it to the
--             menus.  A page whose reversal would not actually be dark falls
--             back to plain black paper; see darkPage.
--
-- There were three.  COLORFUL -- a saturated tint per screen, a band across
-- a header, a card per Pokemon in its own species colour -- was taken out at
-- 0.8.0 rather than finished.  Everything it needed went with it: the tint
-- table, `Theme.band`, `gen1wildThemeZones`, and the party screen's cards.
-- The history has it if it is ever wanted back; carrying a half-built third
-- option in the file that every frame of the game runs through is a worse
-- trade than looking it up.
--
-- ------- what is deliberately NOT themed
--
-- The overworld, battles, the title screen, and anything drawn true-colour
-- (a mon's animated sprite, an item icon) -- the first three because they are
-- pictures rather than pages, the fourth because a `colors == false` zone is
-- the engine's opt-out from the shade shader and painting it would undo the
-- art it was cut out for.

local Theme = {}

-- The four DMG greys, as `src/render/PaletteFX.lua` writes them.  Compared by
-- value rather than by identity: a screen may build its own copy, and two
-- lists of the same four numbers are the same palette.
local GREYS = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 },
                { 0, 0, 0 } }

Theme.ORDER = { "light", "dark" }

Theme.LABELS = {
  light = "LIGHT",
  dark = "DARK",
}

Theme.DEFAULT = "light"

-- ------- the pages
--
-- Two ways a screen is recognised, and it only needs one.
--
-- A screen this suite REGISTERED says so itself: `state.gen1wildTheme` is set
-- on the instance when it is built.  That covers the suite's own menu screens
-- and the test bench, and it costs a feature nothing.
--
-- Everything else is recognised by its class.  The list below is of STATE
-- classes -- things that go on `game.stack.states` -- which is why the bag,
-- the shop, Bill's PC and the prize counter are not in it by name: none of
-- them is a state.  `src/ui/BagMenu.lua` and its neighbours are modules that
-- build a `src.ui.ListMenu` and push THAT, so the one ListMenu entry covers
-- all four.
--
-- Left out deliberately: the screens that are pictures rather than pages --
-- the intro, Oak's speech, the Hall of Fame, the evolution and trade
-- animations, the slots, the surfing minigame -- and PaletteScreen, which is
-- the colour picker itself and has to show colours as they are.  Those, the
-- overworld and a battle are every frame owner in the engine that this list
-- does not name; each was read before being left out.
Theme.PAGES = {
  "src.ui.PokedexMenu",
  "src.ui.DexEntryMenu",
  -- the bag, the shops, the box, the PC and the prize counter all push one
  "src.ui.ListMenu",
  "src.ui.PartyMenu",
  "src.ui.SummaryMenu",
  "src.ui.TrainerCard",
  "src.ui.Diploma",
  "src.ui.TownMap",
  "src.ui.NamingScreen",
  -- Oak's speech, and it is the one entry here that is a PICTURE by the rule
  -- above -- it owns the frame and draws portraits on it.  It is a page
  -- anyway, and asked for as one: a white screen behind Oak, the rival and
  -- the NIDORINO is the one place DARK stayed light all the way through, and
  -- it is the first thing a new game shows.
  --
  -- What makes it safe to reverse is that the pictures on it are exempt from
  -- the reversal already.  A full-colour portrait is `trueColor` and the
  -- engine marks it (OakSpeech.lua:726), so the shade pass never touches it;
  -- runtime/matte.lua then paints the page colour under that mark, which is
  -- what stops the mark's raw re-blit bringing the old white page back inside
  -- it.  Both halves are needed and neither works alone: without the matte
  -- this is a white box on a dark page, and without the page there is nothing
  -- for the matte to match.
  "src.ui.OakSpeech",
  -- The evolution screen, by the same reasoning: it owns the frame and draws
  -- a picture on it, so the old rule left it white -- a black ring round the
  -- mon on a white page, which is the intro's bug on another screen. Its art
  -- is `trueColor` and marked, so the reversal cannot touch it, and the matte
  -- puts the page colour under that mark.
  "src.ui.EvolutionState",
  "src.ui.LeaguePC",
  "src.ui.OptionsMenu",
  "src.mods.ManagerState",
}

-- ------- a page whose middle two colours are a KEY
--
-- Reversing a palette turns all four colours over, which is right when the
-- middle two are steps of a paper-to-ink ramp -- which on almost every screen
-- in this game they are, because almost every screen is ink on paper and uses
-- the two between for a shadow.
--
-- The town map's are not a ramp, they are a legend: colour 1 is the sea and
-- colour 2 is the land.  Turning all four over puts the sea where Kanto is
-- and wraps the coastline in trees, which is what a player reported and what
-- a full reversal will do to any picture that uses its middle colours to mean
-- something.
--
-- It is still a page -- its header is ink on paper and wants inverting like
-- every other page's -- so the ENDS turn over and the two in the middle stay
-- exactly where they are.  Sea stays blue, land stays green, the header goes
-- white on black with the rest of the suite.
Theme.KEYED_PAGES = { "src.ui.TownMap" }

-- ------- a page only while something is standing on it
--
-- The title screen is a picture for most of its life and a page for the rest
-- of it, and the difference is whether the menu is open.
--
-- `TitleState:draw` opens with a white fill of the whole screen and then
-- `if self.menuOpen then return end` (TitleState.lua:711-715) -- MainMenu's
-- own ClearScreen, which wipes the logo, the mon and the sprites before the
-- CONTINUE / NEW GAME border goes down.  So from the moment that menu opens
-- there is no art on that screen at all: it is blank paper with two boxes on
-- it, and it is the first thing a dark-mode boot puts in front of you.
--
-- So the rule is the stack rather than the class: a frame owner named here is
-- a page WHEN SOMETHING IS STACKED ON IT, and a picture when it is alone.
--
-- 0.24.0 made it a page in both states, with a transform that moved its
-- GROUND out from under it and left the midtones alone, so the logo would
-- keep its colours and the ribbon its green.  Three things went wrong on
-- screen and are why that is not here any more: the logo's dark outline is
-- shade 3 and came back white; the mon and the figure flashed white frames,
-- because they are true-colour rectangles marked from two code paths and only
-- one of them can paint under a rectangle; and slivers of those rectangles
-- were left unpainted as lines beside both sprites.  The art on that screen is
-- reachable by a palette and by two different marks on different frames, and
-- darkening it needs those under one roof rather than a transform.
Theme.COVERED_PAGES = {
  "src.ui.TitleState",
}

-- The engine classes above, resolved to the class tables themselves so a
-- state can be matched by `getmetatable`.  Built on the first frame rather
-- than at load, because a mod's require of an engine module is cheap but not
-- free and a LIGHT boot never needs it.  A module that is not present
-- resolves to nothing and simply has no entry.
local function resolve(paths)
  local out = {}
  for _, path in ipairs(paths) do
    local ok, class = pcall(require, path)
    if ok and type(class) == "table" then out[class] = true end
  end
  return out
end

local function pageClasses() return resolve(Theme.PAGES) end
local function coveredClasses() return resolve(Theme.COVERED_PAGES) end
local function keyedClasses() return resolve(Theme.KEYED_PAGES) end

-- ------- the transforms

local function reversed(colors)
  return { colors[4], colors[3], colors[2], colors[1] }
end

-- The same turn, with the legend left alone.  Not cached: it is one page's
-- one zone once a frame, and a cache keyed on the caller's table would have
-- to be invalidated by nothing in particular.
local function endsReversed(colors)
  return { colors[4], colors[2], colors[3], colors[1] }
end

-- Plain black-and-white, swapped: the page a DARK screen falls back to, and
-- the colour a screen's true-colour matte takes under DARK.  File-wide rather
-- than per instance because it is a constant, and because self.matte needs it
-- in scope well before the DARK section that used to own it.
local DARK_PAGE = reversed({ { 255, 255, 255 }, { 170, 170, 170 },
                             { 85, 85, 85 }, { 0, 0, 0 } })

-- Is this the four DMG greys?  By value, and only the four -- a palette that
-- is grey-ish but not those numbers is somebody's deliberate choice.
local function isGreys(colors)
  if type(colors) ~= "table" then return false end
  for i = 1, 4 do
    local c, want = colors[i], GREYS[i]
    if type(c) ~= "table" then return false end
    for channel = 1, 3 do
      if c[channel] ~= want[channel] then return false end
    end
  end
  return true
end

-- A zone that covers the screen.  The engine's UI states all open on one,
-- and it is the paper everything after it sits on -- which is why it has to
-- be the FIRST zone: a whole-screen zone further down the list is a panel
-- laid over a page rather than the page itself.
-- ------- the GB frame, and the GB frame WHEREVER IT WAS PUT
--
-- Two questions, and keeping them apart is the whole of this.
--
-- `isWhole` is the strict one: the frame AT THE ORIGIN.  It is what `basePage`
-- asks, and basePage is a GUESS -- "a list that opens on whole-screen greys is
-- a black-and-white page whoever built it" -- made when no state on the stack
-- claimed to be one.  A guess must stay narrow.
--
-- `wholeAt` is the loose one: the frame at any x, and where.  A classic
-- 160x144 screen drawn over a WIDE battle is CENTRED by the engine before this
-- hook sees it -- Game.lua computes classicOffset = (uiWidth - 160) / 2 and
-- runs centerClassicZones over the zone owner's list -- so a page's own
-- whole-screen zone arrives at x = 72, and demanding x = 0 made every such
-- page fall through to a synthesised zone built at 0: themed at 0..160 while
-- drawn at 72..232, right third left light and a dark strip over the battle
-- beside it.
--
-- ONLY `pageZones` may use the loose one, because it runs AFTER `pageState`
-- has already identified the page.  The question there is "where is this
-- page's frame", not "is this a page at all".
--
-- 0.32.9 widened the strict one instead and shipped.  basePage then accepted a
-- 160-wide band of greys at x = 72 belonging to something that is NOT a page,
-- reversed it, and battles came out greyscale and garbled with no text box and
-- no move menu.  tests/battletheme_test.lua is that case and fails on it.
local function isWhole(zone)
  return type(zone) == "table" and zone.x == 0 and zone.y == 0
    and zone.w == 160 and zone.h == 144
end

local function wholeAt(zone)
  if type(zone) ~= "table" then return nil end
  if type(zone.x) ~= "number" then return nil end
  if zone.y ~= 0 or zone.w ~= 160 or zone.h ~= 144 then return nil end
  return zone.x
end

-- The third way in, kept from this file's first version: a list that opens on
-- whole-screen greys is a black-and-white page whoever built it.  Nothing in
-- the engine returns that shape, but a mod's screen might, and recognising it
-- costs one comparison.  Returns the page's index (always 1) or nil.
local function basePage(zones)
  if type(zones) ~= "table" then return nil end
  local first = zones[1]
  if not isWhole(first) then return nil end
  if not isGreys(first.colors) then return nil end
  return 1
end

-- ------- panels
--
-- A page is a screen that owns the frame.  A PANEL is a box drawn ON one --
-- the START menu over the map, the bag's two windows, a field-move list, the
-- PC's menu.  None of those owns the frame's palettes: the engine hands the
-- zone list to the topmost state that has any, and a menu box has none, so
-- the map underneath answers for the whole screen and the theme quite
-- correctly declines it.  That is why the START menu stayed white in a dark
-- game, and it is not something the page rule can fix -- inverting the frame
-- to catch the menu would inverting the map with it.
--
-- So a panel is themed by its own rectangle and nothing else.  Two ways to
-- find one, and a screen only needs the first if the second is wrong:
--
--   * `state:gen1wildThemePanels()` returns rects in pixels, for a screen
--     that draws several boxes and knows where they are.
--   * failing that, `tx`/`ty`/`tw`/`th` on the state itself, in tiles.  That
--     is not a guess: `src/ui/Menu.lua` -- every menu box in this game --
--     keeps its box there and computes it in `Menu.new`, and the suite's own
--     windows are built to the same four fields.  Reading them off the object
--     costs nothing and covers screens nobody has taught this file about.
-- ------- the boxes the stack does not describe
--
-- A panel does not draw anything.  It hands the blit four colours FOR A
-- RECTANGLE, and every pixel inside that rectangle is remapped through them
-- -- including pixels that belong to something drawn ON TOP of the panel.
--
-- That is what the half-dark SAVE screen was.  START > SAVE leaves the START
-- menu open behind the save panel (start_sub_menus.asm:641-647), and the
-- menu is a `src/ui/Menu.lua` box eleven tiles wide by eighteen tall -- the
-- full height of the screen, from tile 9 rightwards.  It has tx/ty/tw/th, so
-- it got a panel.  The two boxes drawn over it did not: the save panel is an
-- ad-hoc table pushed on the stack with a `draw` and nothing else
-- (StartMenu.lua's `Font.drawBox(4, 0, 16, 10)`), and `src/render/TextBox.lua`
-- keeps its box in boxTx/boxTy/boxTw/boxTh rather than tx/ty/tw/th.  So the
-- menu's panel repainted the right-hand nine tiles of both of them and left
-- the rest alone: one screen, split down the middle, dark on one side of a
-- line that is not the edge of anything.
--
-- Reading boxTx as well would fix those two and not the next two.  The stack
-- is the wrong place to ask: what is on the screen is not what the states say
-- about themselves, it is what they DREW.
--
-- So ask that instead.  Every box in this game is drawn by `Font.drawBox` --
-- Menu, TextBox, ChoiceBox, ListMenu, the battle's own boxes, an ad-hoc panel
-- in a state's draw function, a mod's window -- so wrapping that one function
-- records every box on the screen, in the order they were drawn, whoever drew
-- them and whether or not they came from a state at all.
--
-- The order is free and it is the half that makes this safe: `src/core/
-- Game.lua` draws every state BEFORE it collects the zone list and raises
-- `render.zones`, so by the time this is asked the frame is complete and the
-- list is in painting order, bottom box first.
local boxes = {}
local boxCount = 0
-- A frame does not contain sixty boxes.  The cap is for the case where the
-- theme has stood down and nothing is draining the list any more: better a
-- stale sixty than a table that grows for the rest of the session.
local BOX_CAP = 60

-- ------- where the box actually landed
--
-- `Font.drawBox` takes tile coordinates, and a caller is free to have moved
-- the world before it calls: the location banner slides in and out under
-- `love.graphics.translate(0, offset)`, and a classic state inside a wide
-- battle is drawn under a centring translate of its own (Game:draw, which
-- shifts that state's zone list by the same amount and tells PaletteFX to
-- shift its true-colour marks with `setMarkOffset`).
--
-- A panel taken from the untranslated rectangle is parked where the box was
-- ABOUT to be rather than where it is.  While the banner sits still the two
-- agree and nothing shows; the moment it slides away the panel stays behind
-- and the box leaves it, so the plaque flashes white on its way out -- which
-- is exactly what a player saw once the resting frames went dark.
--
-- So the recorder asks the transform.  `transformPoint` is the engine's own
-- answer to "where does this land", it is the identity on the frames that do
-- not translate, and it fixes the wide-battle case in the same stroke: those
-- panels were off by the centring offset for as long as this file has
-- existed, because `centerClassicZones` runs before `render.zones` and never
-- saw them.
local function recordBox(tx, ty, tw, th)
  if type(tx) ~= "number" or type(ty) ~= "number" then return end
  if type(tw) ~= "number" or type(th) ~= "number" then return end
  if tw <= 0 or th <= 0 then return end
  if boxCount >= BOX_CAP then return end
  local x, y = tx * 8, ty * 8
  local graphics = love and love.graphics
  if graphics and type(graphics.transformPoint) == "function" then
    local ok, px, py = pcall(graphics.transformPoint, x, y)
    if ok and type(px) == "number" and type(py) == "number" then
      x, y = px, py
    end
  end
  boxCount = boxCount + 1
  boxes[boxCount] = { x = x, y = y, w = tw * 8, h = th * 8 }
end

-- ------- is this rectangle standing on a box the theme is going to take
--
-- Asked of the boxes recorded SO FAR this frame, which is exactly the right
-- set: a screen paints a box before it paints what goes in it, so by the time
-- the art inside it is marked the box is already here.
--
-- Containment rather than overlap.  The question is what the art is standing
-- ON -- what the seam around it will be read through -- and a box that merely
-- clips a corner of it is not that.
local function insideBox(rect)
  if type(rect) ~= "table" then return false end
  for i = 1, boxCount do
    local box = boxes[i]
    if rect.x >= box.x and rect.y >= box.y
       and rect.x + rect.w <= box.x + box.w
       and rect.y + rect.h <= box.y + box.h then
      return true
    end
  end
  return false
end

-- The boxes drawn since the last call, and the list is emptied by asking.
local function takeBoxes()
  if boxCount == 0 then return nil end
  local out = {}
  for i = 1, boxCount do out[i] = boxes[i]; boxes[i] = nil end
  boxCount = 0
  return out
end

-- Wrapped once, and idempotently: `require` hands every mod the same table,
-- so a second bundle carrying this file -- or a hot reload of this one --
-- must not wrap the wrapper.  The marker is the same trick Gen1WildQOL's
-- SELECT handler uses on OverworldController, and for the same reason.
local FONT_MARK = "__gen1WildBoxRecorder"

local function watchBoxes()
  local ok, Font = pcall(require, "src.render.Font")
  if not ok or type(Font) ~= "table" then return false end
  if rawget(Font, FONT_MARK) then return true end
  local base = Font.drawBox
  if type(base) ~= "function" then return false end
  Font.drawBox = function(tx, ty, tw, th, ...)
    recordBox(tx, ty, tw, th)
    return base(tx, ty, tw, th, ...)
  end
  local assigned = pcall(function() Font[FONT_MARK] = true end)
  return assigned and true or false
end

-- ------- the hairline around true-colour art
--
-- `Renderer.scissorClamped` rounds every zone's scissor OUTWARD to whole
-- framebuffer pixels, deliberately: on a fractional DPI a truncated scissor
-- loses up to a pixel a side, two neighbouring SGB zones stop sharing an edge
-- and the letterbox clear shows through as a seam at every boundary.  Letting
-- neighbours overlap by a row instead is harmless when both are SHADED -- the
-- same canvas, drawn twice, differing only in palette across a seam.
--
-- It is not harmless for a `colors == false` zone.  That one draws the canvas
-- RAW, so its overlap paints unshaded canvas over correctly shaded pixels.
-- Just outside a matte the canvas is the white page -- and white is what
-- SHADES TO black -- so on a dark screen every piece of true-colour art wears
-- a one-pixel white rectangle.  Box icons, party icons, bag icons, dex icons,
-- a move's type name: fourteen call sites, one cause.
--
-- ------- why it cannot be painted away
--
-- The ring needs a canvas colour that renders the same raw as it does shaded.
-- Reversing a four-shade palette is an involution with no fixed point --
-- 255 <-> 0, 170 <-> 85 -- so no matte colour satisfies it, and insetting the
-- mark, insetting the matte or growing both only moves which side is wrong.
--
-- ------- so change the palette instead of the paint
--
-- The page's palette is ours.  Give the art a zone of its OWN, one pixel
-- larger than the mark, whose ends are both black; then paint a one-pixel
-- black skirt around the art on the canvas.  In that ring the canvas is black
-- and the zone maps black to black, so raw and shaded agree and the overlap
-- is invisible.  Inside the mark the engine's own true-colour rect is spliced
-- after ours and still wins, so the art is untouched.
--
-- One wrapper on `markTrueColor` does it for every site at once, including
-- ones in other bundles and any added later: the skirt is painted where the
-- art just drew, and the zone is emitted with the panels.  The two halves
-- cannot drift apart because the same call makes both.
--
-- ONLY the UI pass.  A world-pass mark is the follower and the map's
-- characters, and in ADVANCED the world canvas blits raw with no shader over
-- it at all -- there is no seam there to hide, and a black skirt would be a
-- black outline drawn round a character on a lit map.
-- ------- and why the list lives on PaletteFX rather than in this file
--
-- Both bundles carry this file.  `watchArt` wraps `markTrueColor` once and
-- marks the table so the second copy does not wrap the wrapper -- which means
-- the copy that PAINTS the skirt is whichever loaded first, while the copy
-- that emits the zone is whichever won the theme's `render.zones` claim.
-- Those are not always the same copy, and when they differ the skirt is
-- painted by one and the zone is emitted by neither: black paint under a
-- palette that maps black to the page's INK.
--
-- On most of the screen that is invisible, because a dark page's ink is where
-- the art already sits.  It shows in exactly one place -- the title screen's
-- copyright row, the one strip deliberately left light -- as a white hairline
-- along the bottom edge of the figure and the mon, which is what a player
-- saw.  So the rects live on the shared table the wrapper already marks, and
-- either copy reads what either copy wrote.
local ART_CAP = 40
local ART_LIST = "__gen1WildArtRects"

-- ------- and the one row the ring must not reach
--
-- The title screen is black to row 135 and WHITE from 136: the copyright line
-- is the one strip matte.lua leaves light on purpose, and the theme reverses
-- its palette so its ink is black on that white.
--
-- The mon is drawn at `y = 136 - h` and the figure's box ends on the same
-- line, so the bottom bar of both their rings lands exactly on row 136 --
-- a black bar painted straight through the copyright, and an ART_PAGE zone
-- over it that maps that row's ink to black as well.  Both halves of the
-- skirt have to stop at the strip, which is what this bound is.
--
-- It lives beside the rects for the same reason they do: the copy that paints
-- the ring and the copy that emits the zone are not always the same copy, so
-- the bound has to be somewhere both of them can read.  Set while the dark
-- title draws, taken with the rects at `render.zones`, and absent on every
-- other screen -- where the page is dark all the way down and a ring at the
-- bottom of it is exactly what is wanted.
local ART_CLIP = "__gen1WildArtClip"

local function paletteFX()
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if not ok or type(PaletteFX) ~= "table" then return nil end
  return PaletteFX
end

local function artClip()
  local PaletteFX = paletteFX()
  local clip = PaletteFX and rawget(PaletteFX, ART_CLIP) or nil
  return type(clip) == "number" and clip or nil
end

local function setArtClip(y)
  local PaletteFX = paletteFX()
  if not PaletteFX then return false end
  return pcall(function() PaletteFX[ART_CLIP] = y end) and true or false
end

local function artList()
  local PaletteFX = paletteFX()
  if not PaletteFX then return nil end
  local list = rawget(PaletteFX, ART_LIST)
  if type(list) ~= "table" then
    list = {}
    local stored = pcall(function() PaletteFX[ART_LIST] = list end)
    if not stored then return nil end
  end
  return list
end

local function takeArt()
  local clip = artClip()
  if clip then setArtClip(nil) end
  local list = artList()
  if not list or not list[1] then return nil, clip end
  local out = {}
  for i = 1, #list do out[i] = list[i]; list[i] = nil end
  return out, clip
end

-- ------- the ring, minus wherever other art already is
--
-- Four bars rather than one filled rect, because the art is already down
-- inside the rectangle and must not be painted over.
--
-- And each bar minus every OTHER marked rect on the frame, because one piece
-- of art is not always one rectangle.  `TitleState.markVisibleTrueColor`
-- splits the mon's mark around the player standing in front of it -- a strip
-- above, a strip below, a strip each side -- and a strip can be two pixels
-- tall.  A one-pixel ring on both sides of a two-pixel strip is not a
-- hairline guard, it is a black bar through the middle of a POKeMON, which is
-- what a player saw.
--
-- Adjacent rects touch without overlapping, so a ring pixel on a shared edge
-- lies inside its neighbour and is skipped.  What survives is the outside of
-- the UNION, which is the only boundary the engine's outward scissor rounding
-- can spill across in the first place.
local function insideAny(px, py, rects, skip)
  for _, r in ipairs(rects) do
    if r ~= skip and px >= r.x and px < r.x + r.w
        and py >= r.y and py < r.y + r.h then
      return true
    end
  end
  return false
end

-- One one-pixel bar, drawn as the runs of it that no other rect covers.
local function paintBar(x, y, length, horizontal, rects, skip, clip)
  if clip then
    if y >= clip then return end
    if not horizontal then length = math.min(length, clip - y) end
    if length <= 0 then return end
  end
  local run = nil
  local function flush(stop)
    if not run then return end
    if horizontal then
      love.graphics.rectangle("fill", run, y, stop - run, 1)
    else
      love.graphics.rectangle("fill", x, run, 1, stop - run)
    end
    run = nil
  end
  for step = 0, length - 1 do
    local px = horizontal and (x + step) or x
    local py = horizontal and y or (y + step)
    if insideAny(px, py, rects, skip) then
      flush(horizontal and px or py)
    elseif not run then
      run = horizontal and px or py
    end
  end
  flush(horizontal and (x + length) or (y + length))
end

local function paintSkirt(colour, rect, rects, clip)
  local x, y, w, h = rect.x, rect.y, rect.w, rect.h
  love.graphics.setColor(colour[1] / 255, colour[2] / 255, colour[3] / 255, 1)
  paintBar(x - 1, y - 1, w + 2, true, rects, rect, clip)
  paintBar(x - 1, y + h, w + 2, true, rects, rect, clip)
  paintBar(x - 1, y, h, false, rects, rect, clip)
  paintBar(x + w, y, h, false, rects, rect, clip)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------- the one mark that is not a page's art: a sprite's own cell
--
-- `SpriteRenderer:draw` reports a trueColor rect for every sprite whose art
-- is full colour -- `PaletteFX.markTrueColor(x, y, frameWidth, drawHeight)`,
-- the whole 16-wide cell, transparent pixels and all -- and it does it in
-- whichever pass happens to be current.  On the map that is the world pass
-- and the rect is doing its job.
--
-- Once per battle it is not.  The battle transition is a state on the stack,
-- so it draws under the UI pass, and what it draws is `self.world:draw()` --
-- the whole overworld, sprites included, onto the UI canvas.  Every character
-- on screen reports its cell into the UI list from inside the wipe, and two
-- things then happen to that rectangle that were never meant for a sprite:
-- the renderer splices it onto the UI zone list and re-blits the cell RAW, so
-- the map showing through the sprite's transparent pixels keeps its DMG
-- shades while the map around it is colourised, and this theme paints its
-- one-pixel ring round the edge of it.  A pale square with a black outline,
-- over the character, for as long as the wipe runs, in DARK -- the only theme
-- that paints a ring -- and in ADVANCED, the only mode that splices the rect.
--
-- Four fixes went at the mark this looked like: the follower's own rect,
-- rounded outward, then skirted where it had not landed, then reported in the
-- wrong pass.  All three were real and none of them was this one, because
-- this mark is not the follower's -- it is the engine's, for every sprite on
-- the map, and no mod-side gate on a mod's own call could ever reach it.
--
-- So it is gated here, where every mark passes through: a sprite cell
-- reported outside the world pass is dropped before the engine sees it.  That
-- costs the sprite its true colours for the second the wipe lasts -- it goes
-- through the palette pass like the map it is standing on, which is what the
-- rest of the frame is doing anyway -- and buys back the box.  Nothing
-- changes on the map itself: there the pass IS the world pass and the mark
-- goes through untouched.
--
-- An engine with no pass to report keeps the old behaviour rather than
-- silently losing marks it has always kept.
local SPRITE_DEPTH = "__gen1WildSpriteDepth"
local SPRITE_MARK = "__gen1WildSpriteWatch"

local function spriteDepth()
  local PaletteFX = paletteFX()
  local n = PaletteFX and rawget(PaletteFX, SPRITE_DEPTH) or nil
  return type(n) == "number" and n or 0
end

local function setSpriteDepth(n)
  local PaletteFX = paletteFX()
  if not PaletteFX then return end
  pcall(function() PaletteFX[SPRITE_DEPTH] = n end)
end

local function inWorldPass()
  local PaletteFX = paletteFX()
  if not PaletteFX then return true end
  if type(PaletteFX.spriteRedrawPassActive) ~= "function" then return true end
  local ok, world = pcall(PaletteFX.spriteRedrawPassActive)
  if not ok then return true end
  return world and true or false
end

-- The rule itself, without the engine: a sprite cell reported in a pass that
-- is not the world's is not a page's art and must not become a zone.
local function dropsSpriteMark(depth, world)
  return (tonumber(depth) or 0) > 0 and not world
end

-- The counter lives on PaletteFX for the reason the rects do: both bundles
-- carry this file, only the copy that loads first wraps anything, and the
-- copy that reads has to be able to see what the copy that wrote put there.
local function watchSprites()
  local ok, SpriteRenderer = pcall(require, "src.render.SpriteRenderer")
  if not ok or type(SpriteRenderer) ~= "table" then return false end
  if rawget(SpriteRenderer, SPRITE_MARK) then return true end
  local wrapped = false
  for _, name in ipairs({ "draw", "drawTile" }) do
    local base = rawget(SpriteRenderer, name)
    if type(base) == "function" then
      SpriteRenderer[name] = function(...)
        local prev = spriteDepth()
        setSpriteDepth(prev + 1)
        local a, b, c = base(...)
        setSpriteDepth(prev)
        return a, b, c
      end
      wrapped = true
    end
  end
  if wrapped then
    pcall(function() SpriteRenderer[SPRITE_MARK] = true end)
  end
  return wrapped
end

local MARK_MARK = "__gen1WildArtSkirt"

local function watchArt(skirt, shaded)
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if not ok or type(PaletteFX) ~= "table" then return false end
  if rawget(PaletteFX, MARK_MARK) then return true end
  local base = PaletteFX.markTrueColor
  if type(base) ~= "function" then return false end
  PaletteFX.markTrueColor = function(x, y, w, h)
    -- A sprite's own cell, reported from inside the battle wipe: not a page's
    -- art, never a zone, never a ring.  See SPRITE_DEPTH above.
    if dropsSpriteMark(spriteDepth(), inWorldPass()) then return end
    -- ------- a skirt only where a mark actually landed
    --
    -- This used to decide for itself whether the mark was one to skirt, by
    -- asking whether the world pass was running -- the world blits raw, has
    -- no seam to hide, and a skirt there is a black outline drawn round a
    -- character on a lit map.  That test was right about the world and blind
    -- to a third case:
    --
    --     local rects = currentPass and trueColorRects[currentPass]
    --     if not rects or w <= 0 or h <= 0 then return end
    --
    -- With NO pass current -- setPass(nil), which the engine does around the
    -- upright pass and while it composes -- markTrueColor drops the mark on
    -- the floor.  It is not the world pass, so the old test waved it through
    -- and painted a skirt anyway: a black box with no true-colour rect inside
    -- it to be the reason for one.  Reported as a black box round the
    -- overworld character on the way into a battle, in DARK, which is the
    -- only theme that paints a skirt at all.
    --
    -- So the question is not asked any more, it is OBSERVED.  Call the engine
    -- first and skirt the rect only if the engine kept one -- and skirt the
    -- rect IT kept, not the one passed in, because a UI-pass mark is shifted
    -- by markOffsetX on the way in and the skirt was being painted at the
    -- unshifted x on any wide layout.
    --
    -- Now a skirt cannot exist without the mark it belongs to, whichever pass
    -- is running and whether or not there is one.
    local list = type(PaletteFX.trueColorRects) == "function"
      and PaletteFX.trueColorRects("ui") or nil
    local before = type(list) == "table" and #list or nil
    local result = base(x, y, w, h)
    if before and #list > before then
      local landed = list[#list]
      -- ------- two jobs, and only one of them is the ring
      --
      -- RECORDING where the art is, and PAINTING a one-pixel ring round it,
      -- used to be the same `if`: no skirt colour, no entry in the list. They
      -- are not the same question.
      --
      -- The list is what `withArt` turns into the frame's ART_PAGE zone, and
      -- every screen with true-colour art on it needs that zone whether or not
      -- it is a page. A battle is the case that proves it: it is deliberately
      -- not a page, so gating the list on the skirt dropped its art zone
      -- entirely and the whole battle came back unthemed.
      --
      -- The ring is the narrower job. It hides the seam where a raw-blitted
      -- mark meets a SHADED page, so it is painted only where there is a page
      -- to shade -- on a screen the theme leaves alone it is the only thing
      -- you can see, which is the black box round Oak and the NIDORINO.
      local ours = artList()
      if ours and #ours < ART_CAP then
        local rect = { x = landed.x, y = landed.y, w = landed.w, h = landed.h }
        ours[#ours + 1] = rect
        local colour = shaded(rect) and skirt() or nil
        if colour then paintSkirt(colour, rect, ours, artClip()) end
      end
    end
    return result
  end
  local assigned = pcall(function() PaletteFX[MARK_MARK] = true end)
  return assigned and true or false
end

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w
     and a.y < b.y + b.h and b.y < a.y + a.h
end

local function sameRect(a, b)
  return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local function tiles(tx, ty, tw, th)
  if type(tx) ~= "number" or type(ty) ~= "number" then return nil end
  if type(tw) ~= "number" or type(th) ~= "number" then return nil end
  if tw <= 0 or th <= 0 then return nil end
  return { x = tx * 8, y = ty * 8, w = tw * 8, h = th * 8 }
end

-- Two spellings of the same four numbers, because the engine has two.
-- `src/ui/Menu.lua` computes tx/ty/tw/th in Menu.new and `src/ui/ChoiceBox.lua`
-- takes the same names; `src/render/TextBox.lua` keeps its box in
-- boxTx/boxTy/boxTw/boxTh (TextBox.lua:123-126).  Reading only the first set
-- is why dialogue stayed white on a dark map while the YES/NO beside it went
-- dark -- the ChoiceBox spells it one way and the box under it the other, and
-- the box under it was the first thing drawn, so the drawn-box closure had
-- nothing earlier to hang it on either.
--
-- This does not reach into a battle.  A battle draws its own dialogue and its
-- own command box directly (BattleState.lua:6546-6547) rather than pushing a
-- TextBox state, so there is no TextBox above it to find.  The one that is --
-- the nickname prompt after a catch -- already had its YES/NO themed and its
-- box not, which is the same split this fixes.
local function panelRect(state)
  return tiles(state.tx, state.ty, state.tw, state.th)
      or tiles(state.boxTx, state.boxTy, state.boxTw, state.boxTh)
end

local function panelsOf(state)
  if type(state.gen1wildThemePanels) == "function" then
    local ok, got = pcall(state.gen1wildThemePanels, state)
    if ok and type(got) == "table" then return got end
    return nil
  end
  local one = panelRect(state)
  return one and { one } or nil
end

-- Rec. 709, the same weighting tests/runtime_test.lua measures the tints
-- against.  Used for one question only: is this actually dark?
local function luma(c)
  return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

function Theme.new(context)
  local mod = context.mod
  local optionset = context.optionset
  local KEY = "ui_theme"

  local self = {}

  local classes                         -- built on the first frame
  local covered
  local keyed
  local reversals = setmetatable({}, { __mode = "k" })

  -- ------- read once a frame, not once a mark
  --
  -- `optionset.read` walks the live game's save, the mod's own option store
  -- and the row's fallbacks -- a dozen table lookups behind two pcalls.  That
  -- is nothing to do once and this is not asked once: `self.skirt` asks it for
  -- EVERY true-colour mark on the frame and then asks `self.matte`, which
  -- asks it again.  A box screen with thirty icons was reading the same word
  -- off the save sixty times to draw one screen.
  --
  -- Kept against `optionset.generation()`, a number every write of every kind
  -- bumps.  Not against `self.write` alone: the OTHER bundle's menu and the
  -- test bench both move this row through `mod.exports.optionWrite`, which
  -- never comes through this file, and a cache that only this file could
  -- clear would have left the skirt drawing yesterday's colour on the frame
  -- the zones already turned over -- the two disagreeing inside one frame,
  -- which is the shape of every hairline in this file's history.
  --
  -- And thrown away at the top of the `render.zones` hook as well, once a
  -- frame: a loaded save brings its own options with it and writes nothing.
  local answer, answerAt

  function self.read()
    local now = optionset.generation and optionset.generation() or nil
    if answer and answerAt == now then return answer end
    local value = optionset.read(mod, KEY)
    if not Theme.LABELS[value] then value = Theme.DEFAULT end
    answer, answerAt = value, now
    return value
  end

  -- Called by the hook below, and by tests standing in for a frame boundary.
  function self.forget()
    answer, answerAt = nil, nil
  end

  function self.write(value, game)
    if not Theme.LABELS[value] then return end
    self.forget()
    return optionset.write(mod, KEY, value, game)
  end

  -- The palette a tint name stands for, for a screen that wants to colour its
  -- own rows.  runtime/menu.lua cannot require this file -- a mod's require
  -- does not reach into its own folder -- so the instance carries the lookup
  -- rather than the table being read directly.
  function self.label(value)
    return Theme.LABELS[value or self.read()] or Theme.LABELS[Theme.DEFAULT]
  end

  function self.step(direction, game)
    local current = self.read()
    local at = 1
    for index, name in ipairs(Theme.ORDER) do
      if name == current then at = index end
    end
    local next_ = Theme.ORDER[((at - 1 + (direction or 1)) % #Theme.ORDER) + 1]
    self.write(next_, game)
    return next_
  end

  -- The row the bundle owns, folded into the same schema every feature's rows
  -- go into, so it is stored, read and remembered like any other -- including
  -- across a sealed cart's option reset, which runtime/settings.lua handles by
  -- key and needs no teaching about this one.
  function self.defineRow()
    optionset.own({
      key = KEY,
      type = "choice",
      label = "UI THEME",
      choices = {
        { Theme.LABELS.light, "light" },
        { Theme.LABELS.dark, "dark" },
      },
      default = Theme.DEFAULT,
    })
  end

  -- ------- finding the page
  --
  -- Top of the stack downwards.  The first state that says what it is, or is
  -- a class in Theme.PAGES, is the page: returned with its tint name and
  -- whether it is one of ours.  The first state that owns the frame's zones
  -- and is NEITHER ends the walk with nothing -- that is the overworld, a
  -- battle, the title screen, and the frame is not a page.  A state that owns
  -- no zones and is not a page (a text box, a fade, the start menu) is
  -- stepped over, so a confirm box on top of the OPTION screen leaves the
  -- OPTION screen themed.
  --
  -- `sgbPalettes` is the same test src/core/Game.lua uses to pick the zone
  -- list in the first place, so "owns the zones" here means exactly what it
  -- means there.
  -- ------- the one class in Theme.PAGES that is not always a page
  --
  -- `src.ui.ListMenu` is in Theme.PAGES because most of what it opens IS a
  -- page: the shop's list, the PC's, the prize counter's, every one of them a
  -- screen of its own.  The BAG's is not, and the engine says so twice in the
  -- same three lines (ListMenu.lua:132-137):
  --
  --     self.itemBox = opts.itemBox or opts.messageBox or false
  --     if self.itemBox then
  --       self.isOpaque = false
  --       -- keep RunDefaultPaletteCommand's last palette: ItemMenuLoop never
  --       -- sets its own
  --       self.sgbPalettes = false
  --
  -- `isOpaque = false` is "what is behind me is still on screen" and
  -- `sgbPalettes = false` is "I brought no palette; keep the one that is up".
  -- Together they describe a BOX ON somebody else's screen, which is a panel
  -- and not a page -- the same thing the START menu is on the map.
  --
  -- Treating it as a page synthesised a whole-screen palette and handed the
  -- frame underneath to it.  Open the bag in a battle and that frame is the
  -- fight: `BattleState:sgbPalettes` returns nil for the classic layout, so
  -- the theme is given NO zone list, which is the engine's "blit this frame in
  -- the colours it was drawn in".  A page over it turned that into four
  -- greys over the whole screen -- the backdrop, the POKeMON, all of it --
  -- reported as the item menu making the battle black and white.
  --
  -- Stepped over instead, so the walk carries on down to whatever really does
  -- own the frame.  Nothing is lost by it: the bag's own windows are themed
  -- as PANELS on that frame, which is how the START menu over the map has
  -- always been done, and the map or the battle behind keeps its colours.
  local function overlayState(state)
    return state.sgbPalettes == false and state.isOpaque == false
  end

  -- The game the current frame belongs to; see the `render.zones` wrap.
  local frameGame = nil

  local function pageState(game)
    local states = game and game.stack and game.stack.states
    if type(states) ~= "table" then return nil end
    for i = #states, 1, -1 do
      local state = states[i]
      if type(state) == "table" then
        if state.gen1wildTheme ~= nil then return state, i end
        classes = classes or pageClasses()
        if classes[getmetatable(state)] and not overlayState(state) then
          return state, i
        end
        if state.sgbPalettes then
          -- A picture with something standing on it is a page after all; see
          -- Theme.COVERED_PAGES.  Alone, it is the picture it looks like.
          covered = covered or coveredClasses()
          if i < #states and covered[getmetatable(state)] then
            return state, i
          end
          -- owns the frame and is not a page: the frame is not ours, but
          -- anything stacked ON it still might be, so say where it sits
          return nil, i
        end
      end
    end
    return nil
  end

  -- Whether this frame has a themed page on it at all, asked of the LIVE
  -- stack.  Both things that paint over a true-colour mark turn on this, for
  -- the same reason: a skirt hides the seam against a shaded page, and a matte
  -- replaces the white a shaded page would otherwise leave inside the mark.
  -- With no page there is no shading, the screen is still on its own white
  -- paper, and either one would be painting a box onto a picture.
  local function onThemedPage()
    return pageState(frameGame) ~= nil
  end

  -- Published for runtime/matte.lua, which has to ask the same question about
  -- a screen that is NOT itself a page: Oak's speech keeps drawing its
  -- portrait underneath the naming screen, and the naming screen is a page.
  self.onPage = onThemedPage

  -- ------- and the narrower question the SKIRT actually has
  --
  -- The ring is not about pages.  It hides the hairline a raw-blitted rect
  -- leaves along its own edge: `Renderer:blitCanvas` scissors each zone and
  -- rounds outward, so on a fractional-DPI display -- a phone -- the raw
  -- re-blit bleeds a sliver of whatever the canvas holds just outside the
  -- mark.  Inside a box that box's PAPER is what bleeds, and on a dark screen
  -- that is a white hairline down the side of every icon and every coloured
  -- label.  Painting the ring the page's own colour first is what makes the
  -- bleed invisible.
  --
  -- So the question is "is this art standing on something the theme shades",
  -- and a page is only one of the two ways to be.  The other is a PANEL: on a
  -- frame that is not a page every box drawn on it is taken and themed --
  -- a battle's move box, the bag's item window over a fight -- and the art
  -- inside one of those has exactly the same seam for exactly the same
  -- reason.
  --
  -- Gating on the page alone was right for as long as the bag's item window
  -- WAS a page.  It stopped being one in 1.26.2, and the hairline came back
  -- down the right-hand side of every item icon; the same hairline was beside
  -- the coloured move type in every battle, where there had never been a page
  -- to turn it off.
  --
  -- What must NOT get a ring is art on a screen the theme leaves alone: the
  -- intro's portraits on white paper, a character on the map. Neither is
  -- inside a box, so neither is reached -- which is the whole of why the test
  -- is containment in a box rather than "is anything themed on this frame".
  local function shadedUnder(rect)
    if onThemedPage() then return true end
    return insideBox(rect)
  end

  -- Every panel on the stack ABOVE whatever owns the frame, bottom up so a
  -- menu over a menu paints in the order the two were drawn.
  --
  -- Above the owner, and only above: a page IS the owner and is themed as a
  -- page, so painting its own box again would be a second coat of the same
  -- colour at best and a box over its own content at worst.  What is left
  -- above the owner is exactly the overlays -- the START menu on the map, the
  -- bag's windows, a field-move list, a battle's command box.
  -- `everyBox` is a frame whose owner is NOT a page -- the map, a battle, the
  -- title, any of the pictures.  Nothing on such a frame is themed by the page
  -- path, so there is no half-and-half to protect against and no owner's
  -- palette to double-coat: every box drawn on it is ours to take, and the
  -- closure's seed is the whole recorded list rather than the rects a state
  -- described.
  --
  -- Which is also the only way to reach a box nothing owns.  The location
  -- banner is a `Font.drawBox` from an overlay hook with no state behind it,
  -- so there is no rectangle for a state to describe and nothing earlier in
  -- the frame for the closure to hang it on -- it stayed white over a dark map
  -- for as long as panels came only from the stack.
  --
  -- Safe because the owners this covers draw no boxes of their own that are
  -- not UI.  The map is tiles; a battle's boxes ARE its command grid, its
  -- dialogue and its HP frames, which is what 0.27.0 already takes on the
  -- classic layout -- so the wide layout, which has a zone list and therefore
  -- never reached that path, now agrees with it.
  --
  -- A page is the other case and keeps the closure: its own boxes are already
  -- inside the page's own colours, and taking them again would be a second
  -- coat over its content.
  local function panelZones(game, ownerAt, drawn, everyBox)
    local states = game and game.stack and game.stack.states
    if type(states) ~= "table" then return nil end
    local rects
    for index = (ownerAt or 0) + 1, #states do
      local state = states[index]
      if type(state) == "table" then
        local found = panelsOf(state)
        if found then
          for _, rect in ipairs(found) do
            if type(rect) == "table" and type(rect.w) == "number"
                and type(rect.h) == "number" and rect.w > 0 and rect.h > 0 then
              rects = rects or {}
              rects[#rects + 1] = { x = rect.x or 0, y = rect.y or 0,
                                    w = rect.w, h = rect.h }
            end
          end
        end
      end
    end
    if everyBox and drawn then
      rects = rects or {}
      for _, box in ipairs(drawn) do
        -- A box a state already described is the same rectangle twice; the
        -- colours are identical either way, but one panel per box is what the
        -- list should say.
        local said = false
        for _, rect in ipairs(rects) do
          if sameRect(box, rect) then said = true break end
        end
        if not said then
          rects[#rects + 1] = { x = box.x, y = box.y, w = box.w, h = box.h }
        end
      end
      -- taken whole, so the closure below has nothing left to decide
      drawn = nil
    end
    if not rects then return nil end

    -- ------- and everything drawn over one of them
    --
    -- A panel remaps its whole rectangle, so a box drawn on top of a panel is
    -- remapped by it whether or not anything asked for that.  There are only
    -- two honest answers to that and one of them is not painting the panel at
    -- all: either the box on top is themed too, or the box underneath must
    -- not be.  This takes the first -- the box on top IS a panel, it just did
    -- not come from a state that says so.
    --
    -- Only forwards, and that is the whole of the safety.  `drawn` is in
    -- painting order, so a box that comes AFTER a panel is a box drawn OVER
    -- it; one that comes before is underneath and was already covered.  A
    -- battle draws its own boxes and then a menu is stacked on top of it: the
    -- battle's boxes are earlier in the list than the menu's, so the menu's
    -- panel never reaches back and repaints the battle.  Nothing here can
    -- theme a screen that was not already being themed one box at a time.
    --
    -- Transitive, and free: the scan decides each box in order and only ever
    -- looks at boxes it has already decided, so a dialogue over a panel over
    -- the map brings its own YES/NO with it in the same pass.
    if drawn then
      local seeded, taken = {}, {}
      for i, box in ipairs(drawn) do
        for _, rect in ipairs(rects) do
          -- The state said this box and then drew it; it is already a panel,
          -- and it is where the closure starts.
          if sameRect(box, rect) then seeded[i] = true; taken[i] = true break end
        end
      end
      for j = 1, #drawn do
        if not seeded[j] then
          for i = 1, j - 1 do
            if seeded[i] and overlaps(drawn[i], drawn[j]) then
              seeded[j] = true
              break
            end
          end
        end
      end
      for j, box in ipairs(drawn) do
        if seeded[j] and not taken[j] then rects[#rects + 1] = box end
      end
    end

    local out = {}
    for _, rect in ipairs(rects) do
      out[#out + 1] = { colors = DARK_PAGE, x = rect.x, y = rect.y,
                        w = rect.w, h = rect.h }
    end
    return out
  end

  -- The list to theme, for a page we have found.
  --
  -- Usually the one we were handed: nothing above this state owns zones (the
  -- walk would have stopped), so if it has palettes of its own these are
  -- them.  When it has none -- a screen that returns nil under some
  -- condition, or one that declares no palettes and inherits from whatever is
  -- beneath it -- a page is made instead.  Every class in Theme.PAGES is
  -- opaque, so the list that came up from below is colouring a screen nobody
  -- can see and is the wrong thing to transform.
  -- `wholeAt` rather than `isWhole`, and only here: pageState has already
  -- said this state IS the page, so what is left to ask is where its frame
  -- was put -- x = 72 when the engine centred it over a wide battle.
  local function pageZones(zones, state)
    if state.sgbPalettes and type(zones) == "table"
        and wholeAt(zones[1]) and type(zones[1].colors) == "table" then
      return zones
    end
    -- ------- and a list that is somebody else's ART
    --
    -- `colors = false` is the true-colour opt-out: a RAW blit, so the pixels
    -- underneath reach the screen untouched.  A battle declares one -- that is
    -- how its backdrop and its POKeMON keep their colours -- and it owns the
    -- frame while it does.
    --
    -- Open the bag in a battle and the frame is still the battle's: a
    -- ListMenu has no palettes of its own, so the list handed in here belongs
    -- to the fight underneath.  Synthesising a whole-screen page over it threw
    -- that raw list away and read the battle through four greys instead --
    -- reported as the bag turning everything behind it black and white.
    --
    -- A page that brought no palettes must not paint over art it did not draw.
    -- Its own boxes are themed as PANELS either way, which is what makes the
    -- item list and the FIGHT grid dark while the fight behind them keeps its
    -- colours -- and `dark` already leaves a raw zone alone, because art is
    -- not inverted.
    if type(zones) == "table" and zones[1] and zones[1].colors == false then
      return zones
    end
    -- Synthesised at the same x the list it stands in for was centred to, so
    -- a page that declares no palettes over a wide battle is themed where it
    -- is drawn.  Falling back to 0 is right for every frame the engine did
    -- not centre, which is every classic one.
    local x = (type(zones) == "table" and wholeAt(zones[1])) or 0
    return { { colors = GREYS, x = x, y = 0, w = 160, h = 144 } }
  end

  -- ------- the matte
  --
  -- What a shade-0 pixel ENDS UP as, for the one thing a palette swap cannot
  -- reach: art drawn in true colour.
  --
  -- `PaletteFX.markTrueColor` is the engine's opt-out -- a marked rectangle is
  -- blitted raw so an animated sprite or a coloured item icon keeps its own
  -- colours instead of being read as four shades.  Raw means RAW: the page
  -- the screen cleared to white is white inside that rectangle too, and stays
  -- white when everything around it goes black.  That is the white box behind
  -- every icon in a dark party menu, box and Pokedex.
  --
  -- A screen fixes it by painting the rectangle this colour before it draws
  -- the art into it.  Only ever inside a rectangle it is about to mark: a
  -- black rectangle anywhere else is shade-3 pixels, which the theme would
  -- then map to the page's INK and put a hole in the page.
  --
  -- The hint is a tint name, or a ramp for a screen that knows the exact
  -- palette covering that spot -- a party icon sits on its Pokemon's card, not
  -- on the page.  Under LIGHT it is white, which is what every screen drew
  -- before this existed, so the call costs a build with no theme nothing.
  local MATTE_WHITE = { 255, 255, 255 }

  function self.matte()
    if self.read() == "light" then return MATTE_WHITE end
    return DARK_PAGE[1]
  end

  local function reverse(colors)
    local cached = reversals[colors]
    if not cached then
      cached = reversed(colors)
      reversals[colors] = cached
    end
    return cached
  end

  -- ---- DARK
  --
  -- Every zone, not only the page.  A menu's zone list is the page plus the
  -- panels inside it -- a species colour behind each party icon, the HP bar's
  -- own green -- and leaving those alone would put a white-grounded icon on a
  -- black page, which is a hole rather than an icon.  Reversing them puts the
  -- icon's paper on the page's black and reads it light-on-dark in its own
  -- colour, which is what the engine's SGB INV mode does and is why that mode
  -- holds together at all.

  -- ------- a theme never writes into the list it was handed
  --
  -- The zone tables belong to the state that built them, and this hook has no
  -- way to know whether that state built them fresh this frame or is handing
  -- back a list it keeps.  Every screen in this suite builds fresh; a screen
  -- somebody adds later might not, and a cached list written into is a screen
  -- that flickers -- reversed on one frame, reversed back on the next, and
  -- unfindable from the symptom.
  --
  -- So a themed frame is a NEW list of NEW zones.  It costs a handful of small
  -- tables per frame and buys a transform that is a pure function of its
  -- input, which is the only version of this that can be reasoned about.
  local function restyled(zones, colourOf)
    local out = {}
    for index, zone in ipairs(zones) do
      if type(zone) ~= "table" then
        out[index] = zone
      else
        local copy = {}
        for key, value in pairs(zone) do copy[key] = value end
        copy.colors = colourOf(index, zone)
        out[index] = copy
      end
    end
    return out
  end

  -- ------- the title screen's black ground
  --
  -- The one page in the game that is a PICTURE, and the only one this suite
  -- darkens by painting rather than by reversing.  matte.lua paints its page
  -- black (and leaves the copyright row white) before the art goes down; this
  -- is the other half of that, and the two are kept in step by a flag the
  -- painter sets on the state for exactly the frame it painted.
  --
  -- The ART colours are left as they are, which is the whole point: the
  -- logo's yellow, its grey drop shadow and the ribbon's green are colours 1
  -- and 2 and are not touched.  BOTH ENDS OF THE RAMP are pinned to black:
  --
  --   colour 3, because that is what the painted page reads as, and pinning
  --   it means the ground is black whatever palette the cart ships rather
  --   than "whatever this band's darkest colour happened to be";
  --
  --   colour 0, because the page is not the only white on this screen.  The
  --   logo and the version ribbon are drawn from images that carry their own
  --   OPAQUE WHITE FIELD -- `love.graphics.draw(self.logo, 16, 8)` paints
  --   that field over whatever the page was -- so 0.29.0 painted the page
  --   black and got two white rectangles, one around POKeMON and one around
  --   WILD GREEN VERSION, exactly the size of the art.  Every shade-0 pixel
  --   on this screen is paper: the page under the art, and the art's own
  --   paper.  Pinning colour 0 makes both of them black and leaves the
  --   letters alone.
  --
  -- The paint in matte.lua is still needed and is not made redundant by
  -- this: a true-colour rectangle re-blits RAW and never reaches the shader
  -- at all, so what is under the mon and the player figure has to actually
  -- BE black pixels.  The palette handles the shaded paper; the paint
  -- handles the raw.
  --
  -- ------- and the copyright row, which is the page's own palette
  --
  -- Not reversed, and that is a bug a player reported three times running.
  --
  -- matte.lua leaves this one strip LIGHT on the canvas -- it is the only
  -- part of the title ground that is not painted black -- and 0.31.8 turned
  -- it over in the palette on top of that, so it read dark with light
  -- letters.  Which it did, until the true-colour rect over the mon reached
  -- it: the engine rounds a `colors == false` scissor OUTWARD, that rect
  -- re-blits the canvas RAW, and raw down there was the white paper.  A white
  -- bar across the copyright.  Painting the row black to hide it is the OTHER
  -- report -- a black bar through the words -- and clipping the ring so it
  -- paints nothing there just lets the white back through.  There is no third
  -- answer while raw and shaded disagree about this row.
  --
  -- So they are made to agree, the cheap way: the plain greys, which is the
  -- IDENTITY palette.  What the shader writes is what the canvas already
  -- holds, the spill has nothing left to show, and the strip reads the way
  -- the cartridge drew it -- dark letters on light paper, at the foot of a
  -- black screen.
  local COPYRIGHT_ROW = 17
  local BLACK = { 0, 0, 0 }

  local function darkGroundState(game)
    local stack = game and game.stack
    local states = stack and stack.states
    if type(states) ~= "table" then return nil end
    for i = #states, 1, -1 do
      local state = states[i]
      if type(state) == "table" and state.__gen1WildDarkGround then
        return state
      end
    end
    return nil
  end

  -- Both ends black, so a black skirt reads black and the white page under it
  -- reads black too.  The middles are never sampled -- the only canvas inside
  -- this zone and outside the art's own rect is the skirt, which is flat
  -- black -- so they are the plain greys rather than a decision.
  local ART_PAGE = { BLACK, { 85, 85, 85 }, { 170, 170, 170 }, BLACK }

  -- Appended after the panels so it wins over them, and before the engine
  -- splices the true-colour rects so those still win inside the art itself.
  local function withArt(list, art, clip)
    if not (art and art[1]) then return list end
    local out = {}
    for _, zone in ipairs(list or {}) do out[#out + 1] = zone end
    for _, rect in ipairs(art) do
      local y, h = rect.y - 1, rect.h + 2
      if clip then h = math.min(h, clip - y) end
      if h > 0 then
        out[#out + 1] = { colors = ART_PAGE,
                          x = rect.x - 1, y = y, w = rect.w + 2, h = h }
      end
    end
    return out
  end

  -- `keyed` is matte.lua reporting that it took the logo's and the ribbon's
  -- own paper out to transparency.  When it has, colour 0 is the ART's white
  -- -- the highlight inside a letter -- and pinning it would take that white
  -- with it, which is what left the logo flat.  When it has not, the paper is
  -- still there and the pin is what keeps it off the page.
  local function groundZones(zones, keyed)
    local out = restyled(zones, function(_, zone)
      local colors = zone.colors
      if type(colors) ~= "table" then return colors end
      return { keyed and colors[1] or BLACK, colors[2], colors[3], BLACK }
    end)
    out[#out + 1] = { colors = GREYS,
                      x = 0, y = COPYRIGHT_ROW * 8, w = 160, h = 8 }
    return out
  end

  -- The page's own reversal, when that really is dark, and plain black-on-
  -- white when it is not.
  --
  -- Every SGB background palette in the pack is an off-white paper at colour
  -- 0 and a near-black at colour 3, with the screen's hue in the two between,
  -- so reversing one gives exactly what DARK is for: black paper, white ink,
  -- and the Pokedex still faintly red where the Pokedex was red.  Reversing
  -- is the right answer often enough to be the rule.
  --
  -- It is not always the right answer.  A page whose darkest colour is not
  -- dark -- the suite's own settings screens open on the player's outfit ramp
  -- -- reverses into a washed pastel, which is a different light mode rather
  -- than a dark one.  So the reversal has to PROVE it is dark (paper below
  -- luma 96, ink above 160) or the page falls back to the plain black one.
  -- Measured rather than listed, so a palette added later is judged on what
  -- it is instead of on whether somebody remembered to name it here.
  local function darkPage(colors, flip)
    flip = flip or reverse
    local flipped = flip(colors)
    if luma(flipped[1]) <= 96 and luma(flipped[4]) >= 160 then return flipped end
    -- The fallback has to keep the promise the flip was chosen for: a keyed
    -- page whose ends do not prove dark still gets the plain black page, but
    -- its legend is carried through rather than flattened into two greys.
    if flip == endsReversed then
      return { DARK_PAGE[1], colors[2], colors[3], DARK_PAGE[4] }
    end
    return DARK_PAGE
  end

  local function dark(zones, pageAt, keyed)
    local flip = keyed and endsReversed or reverse
    return restyled(zones, function(index, zone)
      -- `colors == false` is the true-colour opt-out and is a rectangle, not
      -- a palette: an animated mon sprite, an item icon.  It is art, and art
      -- is not inverted.
      if type(zone.colors) ~= "table" then return zone.colors end
      if index == pageAt then return darkPage(zone.colors, flip) end
      return flip(zone.colors)
    end)
  end

  -- The hook itself.  `next` first, so a mod downstream that builds zones of
  -- its own has already built them and is themed with everything else.
  --
  -- Three outcomes, and two of them return the caller's own list by
  -- reference: LIGHT, and a frame that is not a page.  That matters more than
  -- it looks -- this runs on every frame of the overworld and every frame of
  -- every battle, and on those frames it must cost a table lookup and a walk
  -- down a stack that is usually two states deep.
  -- ------- what the last frame actually saw
  --
  -- Not a feature: the bench's SPRITE PROBE reads this so a screenshot can
  -- say whether a box that stayed white was never RECORDED or was recorded
  -- and never PANELLED.  Those are two different bugs in two different files
  -- and they look identical on a phone.  Three integers a frame, written
  -- whether or not anyone is looking, because the alternative is a flag that
  -- has to be plumbed from a different mod before the numbers start.
  local seen = { boxes = 0, panels = 0, zones = 0 }

  -- ------- for the one wrapper that marks BEFORE it draws
  --
  -- Wild Green marks the title figure and then calls `TitleState:draw`,
  -- because that same call reads `self.player` at its top and the mark has to
  -- name a rectangle the art is about to land in.  `TitleState:draw` OPENS
  -- with a full-screen fill -- so the skirt that mark painted is wiped a line
  -- later, and the figure kept its hairline along the bottom edge while the
  -- mon, whose mark is emitted from inside that draw, did not.
  --
  -- Painting the ring again after the screen has finished is safe by
  -- construction: the ring is entirely outside the rectangle the art occupies,
  -- so a second coat cannot touch the art, and black over black costs a frame
  -- nothing. The rects are still in the list because `takeArt` does not run
  -- until `render.zones`, which is after every state has drawn.
  function self.paintSkirts()
    local colour = self.skirt and self.skirt() or nil
    if not colour then return end
    local list = artList() or {}
    local clip = artClip()
    for _, rect in ipairs(list) do paintSkirt(colour, rect, list, clip) end
  end

  -- matte.lua, naming the row its black ground stops at, on every frame it
  -- paints one.  Taken with the rects at `render.zones`, so a screen that
  -- does not set it has no clip.
  function self.clipArt(y)
    setArtClip(type(y) == "number" and y or nil)
  end

  function self.probe()
    return seen.boxes, seen.panels, seen.zones
  end

  -- The last frame that carried true-colour rects: how many, and what the
  -- theme read itself as while it did.  "light" here is the bug reproducing.
  function self.artProbe()
    return seen.art or 0, seen.artWord or "-", seen.artPage and true or false
  end

  function self.apply(game, zones)
    -- Drained on every frame, before the LIGHT return: the recorder is a
    -- wrapper on an engine function and cannot be asked to stop, so the one
    -- thing that must always happen is that somebody empties it.
    local drawn = takeBoxes()
    local art, artStop = takeArt()
    -- ------- the one question a screenshot cannot answer
    --
    -- A black ring round every true-colour icon on a LIGHT page was reported
    -- on Bill's PC, and every path in this file says it cannot happen: the
    -- skirt that paints that ring and the zone that darkens it are both
    -- behind `self.read() == "dark"`, and a light frame returns the caller's
    -- list untouched a few lines below.  One of those two things is not true
    -- in the running game, and reading the file harder has not found which.
    --
    -- So the frame says so itself: how many rects arrived, and what the theme
    -- called itself when they did.  Kept from the last frame that had any, so
    -- it survives walking to the bench to read it.
    -- Both halves from the SAME frame, which the first cut of this got wrong:
    -- the count was the CURRENT frame's and the word was the last frame that
    -- had any, so read on the bench -- which draws no true-colour art -- it
    -- always said "0", and the word beside it came from somewhere else
    -- entirely.  A snapshot of the last frame that carried rects is the only
    -- reading that means anything, because the screen being asked about is
    -- never the screen being read on.
    local count = art and #art or 0
    if count > 0 then
      -- "BARE" until something below claims the frame as a page.  That is the
      -- third thing worth knowing: rects on a DARK frame that is not a page
      -- are the Bill's PC case -- the ring is correct for a dark page and the
      -- page never went dark -- and rects on a LIGHT frame are a leak in the
      -- gate.  The word alone cannot tell those two apart.
      seen.art, seen.artWord, seen.artPage = count, self.read(), false
    end
    seen.boxes = drawn and #drawn or 0
    seen.panels = 0
    seen.zones = (type(zones) == "table" and #zones) or 0
    if self.read() ~= "dark" then return zones end

    -- The title screen with its ground already painted black.  Answered
    -- before pageState, because with the menu CLOSED it is not a page at all
    -- and would otherwise fall through untouched.
    local ground = darkGroundState(game)
    if type(zones) == "table" and zones[1] and ground then
      if count > 0 then seen.artPage = true end
      return withArt(groundZones(zones, ground.__gen1WildKeyedArt), art, artStop)
    end

    local state, ownerAt = pageState(game)
    local out, page
    if state then
      keyed = keyed or keyedClasses()
      out = dark(pageZones(zones, state), 1,
                 keyed[getmetatable(state)] and true or false)
      page = true
    elseif basePage(zones) then
      -- no page state, but the list itself says it is a page
      out = dark(zones, 1)
      ownerAt = ownerAt or 0
      page = true
    else
      out = zones
      page = false
    end
    if count > 0 then seen.artPage = page and true or false end

    -- Panels last, because they are drawn last: a menu box over a map is on
    -- top of the map, and the zone that colours it has to be on top of the
    -- zones that colour the map.  This is also the ONE path that can theme a
    -- frame that is not a page at all -- which is the whole point, because
    -- the START menu has never been one.
    local bare = type(out) ~= "table" or not out[1]
    local panels = panelZones(game, ownerAt, drawn, not page)
    seen.panels = panels and #panels or 0
    if not panels then return withArt(out, art, artStop) end

    -- ------- a frame that arrived with no zones of its own
    --
    -- `Renderer:blitCanvas` opens with
    --
    --     local shader = zoneList and zoneList[1] and PaletteFX.shader() or nil
    --     if not shader then ... draw the canvas RAW ...
    --
    -- so an EMPTY list is not "colour nothing", it is "run no shader at all
    -- and blit this frame in the colours it was drawn in".  A battle is
    -- exactly that: `BattleState:sgbPalettes` returns nil for every layout but
    -- the wide one (BattleState.lua:173-176).
    --
    -- 0.26.0 stopped adding panels to such a frame, because appending one
    -- turns the shader ON for the whole screen and every pixel no zone covers
    -- -- which is the entire battle -- goes through the palette pass.  That
    -- was the battle going black and white the moment a box opened over it,
    -- and standing down was the right answer to have shipped that day.
    --
    -- It is not the right answer, and the engine says so in its own comment
    -- one screen further down the same function:
    --
    --     a colors == false zone is the trueColor opt-out: its rect draws
    --     with no shader at all
    --
    -- So a whole-screen `colors = false` zone reproduces exactly what an empty
    -- list did -- the frame blitted raw, in the colours it was drawn in -- and
    -- leaves the panels after it free to theme their own rectangles.  The
    -- battle keeps its backdrop and its POKeMON; the boxes on it go dark.
    --
    -- Every box on such a frame is taken, not just the ones a state described
    -- (see panelZones' `bare`).  On a frame where nothing is themed there is
    -- no half-and-half to avoid: it is every box or none, and the battle's
    -- own command grid, its dialogue and its YES / NO are all the same UI.
    if bare then
      local spread = { { colors = false, x = 0, y = 0, w = 160, h = 144 } }
      for _, zone in ipairs(panels) do spread[#spread + 1] = zone end
      return withArt(spread, art, artStop)
    end

    local spread = {}
    for _, zone in ipairs(out or {}) do spread[#spread + 1] = zone end
    for _, zone in ipairs(panels) do spread[#spread + 1] = zone end
    return withArt(spread, art, artStop)
  end

  function self.install()
    self.defineRow()
    -- The box recorder, before the hook that reads it.  Absent on a build
    -- whose Font is not where it has always been, which costs the panels
    -- nothing they had before this: the stack's own tx/ty/tw/th still
    -- answers, and the boxes it cannot describe stay as they were.
    if not watchBoxes() then
      mod.log:info("boxes are not being watched; panels fall back to the stack")
    end
    -- The skirt round true-colour art, for the hairline the engine's outward
    -- scissor rounding leaves.  Its colour is asked for on every mark rather
    -- than captured here, so switching the theme mid-game takes effect on the
    -- next frame like everything else -- and answering nil is what turns the
    -- whole thing off under LIGHT, or in a mode that discards the marks and
    -- would read a black skirt as a hole in the page.
    -- Resolved once.  This closure runs for EVERY true-colour mark on the
    -- frame, and a `pcall(require)` a mark is a pcall and a table lookup to
    -- fetch a module that cannot change after load.  What still has to be
    -- asked each time is `honorsTrueColor`, which follows the display mode.
    local skirtFX
    do
      local okFX, found = pcall(require, "src.render.PaletteFX")
      if okFX and type(found) == "table" then skirtFX = found end
    end

    self.skirt = function()
      if not skirtFX then return nil end
      if self.read() ~= "dark" then return nil end
      if type(skirtFX.honorsTrueColor) == "function"
          and not skirtFX.honorsTrueColor() then
        return nil
      end
      local colour = self.matte()
      if type(colour) ~= "table" or #colour < 3 then return nil end
      return colour
    end
    if not watchSprites() then
      mod.log:info("sprite cells are not being watched; a character can wear "
        .. "a pale box on the way into a battle")
    end
    if not watchArt(self.skirt, shadedUnder) then
      mod.log:info("true-colour marks are not being watched; art keeps its "
        .. "hairline on a fractional-DPI display")
    end
    -- Guarded, and reported once.
    --
    -- This runs on every frame of every screen, and it is the only thing in
    -- the bundle that does.  A theme is decoration: if it raises, the right
    -- outcome is the frame it was handed, drawn in the colours it already
    -- had -- not a crash in the middle of somebody's game over a tint.
    --
    -- Once, because a per-frame failure is a per-frame log line, and a log
    -- nobody can scroll is a log nobody can read.  After the first the theme
    -- stands down for the rest of the session, which also means the cost of
    -- a broken theme is one pcall per frame rather than one error per frame.
    local broken = false
    mod.hooks:wrap("render.zones", function(nextLink, game, zones)
      -- the frame boundary, and it is here rather than inside `apply` so a
      -- theme that has stood down still forgets what it read
      self.forget()
      -- Kept for `self.skirt`, which runs while the frame is still DRAWING
      -- and so cannot be handed the game the way this hook is.  The object
      -- does not change from frame to frame -- only its stack does, and the
      -- stack is what gets read, live, at the moment of the mark.
      frameGame = game
      zones = nextLink(game, zones)
      if broken then return zones end
      local ok, out = pcall(self.apply, game, zones)
      if ok then return out end
      broken = true
      mod.log:warn("UI THEME stood down for this session: %s", tostring(out))
      return zones
    end)
  end

  return self
end

-- For the tests, which have no engine to require classes out of.
Theme.isGreys = isGreys
Theme.isWhole = isWhole
Theme.wholeAt = wholeAt
Theme.basePage = basePage
Theme.luma = luma
Theme.reversed = reversed
Theme.overlaps = overlaps
Theme.recordBox = recordBox
Theme.dropsSpriteMark = dropsSpriteMark

-- The rect half of the skirt, without the paint: tests/titlepage_test.lua
-- drives the zone this produces, and painting needs a window.
function Theme.recordArt(x, y, w, h)
  local list = artList()
  if not list or #list >= ART_CAP then return end
  list[#list + 1] = { x = x, y = y, w = w, h = h }
end
Theme.takeBoxes = takeBoxes

return Theme
