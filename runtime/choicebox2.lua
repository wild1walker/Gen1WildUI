-- Gold's YES/NO box, routed through Gold's own chrome.
--
-- ------- what was wrong
--
-- Under `UI THEME > DARK` on a Gen 2 boot every box on the screen went black
-- with white ink except one: the YES/NO box, which stayed white. Answer a
-- `yesorno` on a dark page and a lit white rectangle appeared on top of it.
--
-- The cause is that `src/ui/ChoiceBox.lua` is SHARED between the generations
-- and paints like a Gen 1 screen: `Font.drawBox` for the box and `Font.draw`
-- / `Font.drawCode` for the two labels and the cursor. None of those reads
-- `Chrome.DEFAULT_BOX_PALETTE`, which is the one table runtime/theme2.lua
-- rewrites -- so a theme built on that table cannot reach this box, however
-- the frame is judged.
--
-- Its sibling does not have the problem. `src/render/TextBox.lua` is shared
-- too, and its draw splits on generation: on Gold it asks `Chrome.paletteBox`
-- for the box and takes its glyph colours from `Chrome.paletteGlyphs`
-- (src/render/TextBox.lua:660-679). The choice box that stands on top of that
-- text box never got the same fold.
--
-- ------- why this is not "the theme drawing something"
--
-- runtime/theme2.lua promises that a theme cannot move a glyph, and it keeps
-- that promise by never drawing: it swaps four numbers and hands the frame
-- back. This file is not part of that promise and is deliberately a separate
-- one, because it DOES draw.
--
-- What it draws, though, is the same box in the same place out of the same
-- glyphs. `Chrome.paletteBox` is `Font.drawBox` with a palette shader around
-- it (src/ui/gen2/Chrome.lua:152-162) -- the same call, the same border tiles,
-- the same rectangle -- and `Chrome.printThrough` and `Chrome.cursorThrough`
-- are `Font.draw` and `Font.drawCode` with that shader and a paper fill under
-- them. Nothing is laid out again and no geometry is re-derived: `tx`, `ty`,
-- `tw`, `th`, `firstItem` and the label rows are read off the instance the
-- engine built.
--
-- ------- always on, and that is the safer half
--
-- The palette this paints through is the LIVE `Chrome.DEFAULT_BOX_PALETTE` --
-- the table theme2 rewrites in place -- not a colour this file chose. So
-- under `LIGHT` it paints Gold's own four numbers and the box is what it has
-- always been, and under `DARK` it goes with everything else without knowing
-- that themes exist.
--
-- That is why it is installed unconditionally on a Gen 2 boot rather than
-- only while DARK is on. A patch that engages only under one setting is a
-- patch that is exercised only by the players who chose it; this way the
-- ordinary boot is the regression test, and a player who never touches the
-- row has a box drawn by the same code as a player who does.
--
-- ------- the paper fold, which is not the theme's
--
-- `game:textboxPaper()` is Gold's answer to a screen whose BG palette 0 is
-- not white -- the Pokegear's cream, principally -- and a box pushed over
-- such a screen has to sit on that paper rather than paint a band across it.
-- TextBox honours it and so does this, by the same fold: paper in the first
-- three slots, black ink in the fourth. A box on the gear therefore stays
-- cream under DARK, which is what the gear's own page does, and is the
-- engine's decision rather than one taken here.
--
-- ------- when the shader is not there
--
-- `Chrome.paletteBox` degrades to a flat fill and `Chrome.printThrough` to a
-- flat black print when `GbcPalette.available()` is false -- a driverless
-- harness, a build with no shader support. That degrade is the engine's and
-- is the same one every other Gold box takes, so this box is no worse off
-- than the menus around it; it is not a failure mode this file introduces.

local ChoiceBox2 = {}

-- The sentinel the patch leaves on the class, so a hot reload -- or the other
-- half of the pair, if it ever grows a theme -- finds it already done rather
-- than wrapping a wrap.
local PATCH_KEY = "__gen1wildChoiceBoxChrome"

ChoiceBox2.PATCH_KEY = PATCH_KEY

-- The four colours this box is to be drawn through: the screen's own paper
-- when it has one, and otherwise the live table the theme rewrites.
--
-- Held by REFERENCE in the second case rather than copied, for the reason
-- theme2.lua rewrites that table in place: a copy taken here would be a
-- snapshot of whatever the palette said on the frame it was taken.
function ChoiceBox2.palette(box, Chrome)
  local game = box and box.game
  if game and type(game.textboxPaper) == "function" then
    local ok, paper = pcall(game.textboxPaper, game)
    if ok and type(paper) == "table" and paper[1] and paper[2] and paper[3] then
      return { paper, paper, paper, { 0, 0, 0 } }
    end
  end
  return Chrome.DEFAULT_BOX_PALETTE
end

-- The engine's own draw, line for line, with the three primitives swapped for
-- their palette-aware peers.  Kept in this shape on purpose: read it beside
-- `ChoiceBox:draw` and every number should be in the same place.
function ChoiceBox2.paint(box, Chrome, Strings, UIVisibility)
  if not UIVisibility.bottomVisible(box, false) then return end
  local tx, ty, tw, th = box.tx, box.ty, box.tw, box.th
  -- Only an ANCHORED box rides the dialogue box's bottom anchor; a bare one
  -- belongs over the screen that pushed it.  The engine's own comment.
  local renderer = box.anchor and box.game and box.game.renderer
  if renderer and renderer.setUIAnchor then
    renderer:setUIAnchor(tx * 8, ty * 8, tw * 8, th * 8, box.anchor)
  end

  local palette = ChoiceBox2.palette(box, Chrome)
  Chrome.paletteBox(tx, ty, tw, th, palette)

  -- TwoOptionMenuStrings rows carry their own labels and a "blank line before
  -- the first item?" flag, which is what `firstItem` is.
  local row = box.firstItem or 1
  Chrome.printThrough(Strings(box.labels[1]), tx + 2, ty + row, palette)
  Chrome.printThrough(Strings(box.labels[2]), tx + 2, ty + row + 2, palette)
  Chrome.cursorThrough(tx + 1, ty + row + (box.index == 1 and 0 or 2), palette)

  love.graphics.setColor(1, 1, 1, 1)
end

-- Does this build carry everything the paint above needs?  Asked before the
-- class is touched, so a build that answers no is left with its own draw
-- rather than a patched one that will fail on its first frame.
function ChoiceBox2.serviceable(ChoiceBox, Chrome)
  if type(ChoiceBox) ~= "table" or type(ChoiceBox.draw) ~= "function" then
    return false, "src.ui.ChoiceBox has no draw to replace"
  end
  if type(Chrome) ~= "table" then
    return false, "no src.ui.gen2.Chrome"
  end
  for _, name in ipairs({ "paletteBox", "printThrough", "cursorThrough" }) do
    if type(Chrome[name]) ~= "function" then
      return false, "src.ui.gen2.Chrome has no " .. name
    end
  end
  return true
end

function ChoiceBox2.install(context)
  local mod = context.mod

  local ok, ChoiceBox = pcall(require, "src.ui.ChoiceBox")
  if not ok then
    error("no src.ui.ChoiceBox to draw through Gold's chrome", 0)
  end
  local okChrome, Chrome = pcall(require, "src.ui.gen2.Chrome")
  if not okChrome then
    error("no src.ui.gen2.Chrome to draw the choice box through", 0)
  end

  if rawget(ChoiceBox, PATCH_KEY) then return false end

  local fine, why = ChoiceBox2.serviceable(ChoiceBox, Chrome)
  if not fine then
    mod.log:warn("the YES/NO box keeps its own colours: %s", tostring(why))
    return false
  end

  local Strings = require("src.core.Strings")
  local UIVisibility = require("src.battle.UIVisibility")

  local base = ChoiceBox.draw
  -- Stood down for the session on the first failure, and the engine's own
  -- draw put back -- the same rule the theme keeps at the same place.  A box
  -- in the wrong colours is a nuisance; a box that raises every frame it is
  -- up is a game that cannot answer a question.
  local broken = false

  ChoiceBox.draw = function(self, ...)
    if broken then return base(self, ...) end
    local painted, problem =
      pcall(ChoiceBox2.paint, self, Chrome, Strings, UIVisibility)
    if painted then return end
    broken = true
    mod.log:warn("the YES/NO box is back on its own colours for this "
                 .. "session: %s", tostring(problem))
    return base(self, ...)
  end
  ChoiceBox[PATCH_KEY] = true

  mod.log:info("the YES/NO box draws through Gold's box palette")
  return true
end

return ChoiceBox2
