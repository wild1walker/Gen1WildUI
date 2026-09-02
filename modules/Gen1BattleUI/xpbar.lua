-- Gen1BattleUI: the XP bar, under the player's Pokemon.
--
-- Gen 2 draws one of these in its own player HUD and Gen 1 does not, so this
-- is the Gen 1 substitute for a thing that already exists a generation later.
-- It was Gen1WildQOL's, one of the four features that mod carries from
-- unxpected-uxp's Quality of Life; it lives here now because it is a battle
-- UI feature and this is the battle UI mod, and because of what that move
-- fixes.
--
-- What it fixes is a bug that had no fix on the other side of it.  Over there
-- the bar wrapped `battle.draw` itself, so it drew after everything inside
-- BattleState:draw -- battle.overlay included, whatever priority anything on
-- that hook carried.  It could not be drawn over.  It clipped itself to x=88
-- instead, which is where the VANILLA move panel ends, and this mod's panel
-- ends at 112: twenty-four pixels of blue line across the PP row, every time
-- a move menu was up.  Raising this mod's hook priority did nothing, because
-- priority was never what decided it.
--
-- Here there is nothing to decide.  The bar and the panel go down in one
-- function, the bar first, so the panel covers it the way it covers anything
-- else underneath -- and a panel that changes width takes the bar's clip with
-- it because there is no clip, only an order.
--
-- The numbers, the level-up fill and the burst are ported as they were.
--
-- ------- and the bar when the HUD is not on this screen
--
-- A voxel mod draws the battle over the map instead of over white paper, and
-- the Dramatic Shape lineage lifts the battle HUDs out of the flat 160x144
-- frame and composites them into the world canvas at the battle's own scale.
-- A bar that stayed behind is then a blue line on a frame the HUD it belongs
-- under has left.
--
-- This path was dropped in the port rather than carried half-way, because the
-- half that decides whether to take it AT ALL is a handshake with the voxel
-- mod -- `snapHUDs`, which reports per frame whether it managed it, and which
-- two of the four forks do not have at all because they leave the HUDs where
-- the engine drew them.  Taken whenever a voxel mod is merely loaded, the path
-- is worse than not having it: the world canvas is window-sized, so the bar
-- lands nowhere near the HUD.
--
-- It is back now with that half in place.  runtime/voxel.lua owns the
-- handshake and answers no unless the HUDs are genuinely on the canvas this
-- frame, and the transform below is read out of the fork's OWN published
-- geometry rather than copied from it.  Everything else -- the guards, the
-- animation, the colour -- is the classic path's, unchanged: only where the
-- rectangle lands moves.

local EXP_X, EXP_Y, EXP_WIDTH = 80, 89, 67
local WIDE_EXP_X, WIDE_EXP_Y, WIDE_EXP_SEGMENTS = 208, 88, 10
local EXP_LEVEL_HOLD_FRAMES = 30
local EXP_BURST_DIAGONALS = { 0, 1, 2, 4, 5, 7, 8, 9 }
local EXP_BLUE = { 50 / 255, 150 / 255, 250 / 255, 1 }
local EXP_BLACK = { 0, 0, 0, 1 }

-- The first tile of "XP:", built here rather than added to the font sheet:
-- the sheet is the game's and a mod that writes into it is a mod every other
-- font mod has to know about.
local XP_TILE_ROWS = {
  "oooooooo",
  "oooooooo",
  "oxxoxoxx",
  "ooxxooxx",
  "ooxxooxx",
  "oxoxxoxx",
  "oooooooo",
  "oooooooo",
}

-- one particle of the level-up burst
local EXP_BURST_TILE_ROWS = {
  "oooooooo",
  "oooxxooo",
  "ooxxxxoo",
  "oxxxxxxo",
  "oxxxxxxo",
  "ooxxxxoo",
  "oooxxooo",
  "oooooooo",
}

return function(mod, C, panelRect)
  -- nil when no voxel mod is installed, which is the ordinary case, and nil
  -- on a tree built before runtime/voxel.lua existed.  Every use is guarded.
  local voxel = mod.voxel
  local Font = require("src.render.Font")
  local Growth = require("src.pokemon.Growth")
  local HudTiles = require("src.render.HudTiles")
  local PaletteFX = require("src.render.PaletteFX")

  local XP = {}

  -- Per-battle animation state, weak-keyed so a finished battle is collected
  -- rather than held alive by the bar that was drawn on it.  Seeded lazily on
  -- the first frame it is asked for: animatedExpPixels already treats a state
  -- with no expMon as "start here", so there is nothing for a battle.started
  -- subscription to do that the first draw does not.
  local states = setmetatable({}, { __mode = "k" })

  local function stateFor(battle)
    local state = states[battle]
    if not state then
      state = {}
      states[battle] = state
    end
    return state
  end

  -- ------- is there a HUD to draw under
  --
  -- The engine clears the player HUD the moment the mon goes down -- name,
  -- level and HP bar all disappear behind "<NAME> fainted!" -- while
  -- battle.player is still a table and every other guard is still false.  Without
  -- this the bar carries on being drawn into the empty space the HUD was
  -- cleared from: a blue stripe over nothing until the battle moves on.
  --
  -- The HP check behind the flag covers the frame between HP reaching zero
  -- and the flag being set.
  -- ------- and not while something is standing on the battle
  --
  -- `battle.overlay` fires whenever the battle DRAWS, and the battle keeps
  -- drawing while another state is on top of it -- that is how the level-up
  -- stat window (PrintStatsBox, a state of its own) appears over the fight
  -- rather than over nothing.
  --
  -- For most of what this mod draws that costs nothing: the state above draws
  -- second and covers it.  The bar is the exception, because the wide bar's
  -- fill is marked trueColor and a trueColor rect is spliced onto the pass's
  -- zone list and RE-BLITS ITS REGION RAW after the pass is composed.  The
  -- battle and everything pushed over it share one pass and one canvas, so
  -- that strip comes back over whatever was drawn on top of it in the
  -- meantime.  Reported as the XP bar showing through the level-up window,
  -- with a wide battle in the screenshots -- which is the layout that marks
  -- one.
  --
  -- Asked of the STACK rather than of any flag the battle keeps, because what
  -- matters is not what the battle is doing, it is whether anybody is standing
  -- in front of it.  A stack that cannot be read leaves the bar drawn: this is
  -- a guard against covering something, not a licence to blank the HUD if the
  -- shape of the game is not what is expected here.
  local function onTop(battle)
    local stack = battle.game and battle.game.stack
    if type(stack) ~= "table" or type(stack.top) ~= "function" then
      return true
    end
    local ok, top = pcall(stack.top, stack)
    if not ok or top == nil then return true end
    return top == battle
  end

  local function playerHudVisible(battle)
    local player = battle and battle.player
    if type(player) ~= "table" then return false end
    if player.fainted then return false end
    local mon = player.mon
    if type(mon) == "table" and (tonumber(mon.hp) or 1) <= 0 then return false end
    return true
  end

  -- ------- how full it is
  --
  -- The bar is progress towards the NEXT level, so it is read from the growth
  -- curve rather than from anything the battle keeps: exp at this level, exp
  -- at the next, and where between them this mon is.  At the cap there is no
  -- next level and the bar is simply full.
  local function expPixels(battle)
    local mon = battle.player and battle.player.mon
    local def = mon and battle.data.pokemon[mon.species]
    if not def then return 0 end
    local cap = battle.data.constants and battle.data.constants.levelCap or 100
    if mon.level >= cap then return EXP_WIDTH end
    local current = Growth.expForLevel(def.growthRate, mon.level,
                                       battle.data.growth_rates)
    local nextLevel = Growth.expForLevel(def.growthRate, mon.level + 1,
                                         battle.data.growth_rates)
    local needed = nextLevel - current
    if needed <= 0 then return 0 end
    local progress = math.max(0, math.min(needed, mon.exp - current))
    return math.floor(progress * EXP_WIDTH / needed)
  end

  -- The bar moves a pixel a frame towards where it should be, and a level-up
  -- is a sequence rather than a jump: fill to full, hold, burst, empty, fill
  -- to the new remainder.  Several levels at once run the cycle once each,
  -- which is what makes a big EXP award read as several levels instead of one
  -- fast slide.
  local function animatedExpPixels(battle, state)
    local mon = battle.player and battle.player.mon
    local target = expPixels(battle)
    if state.expMon ~= mon or state.expPixels == nil then
      state.expMon = mon
      state.expPixels = target
      state.expLevel = mon and mon.level
      state.expPhase = nil
      state.expLevelCycles = 0
      state.expBurstFrame = nil
      state.expFrame = battle.frame
      return target
    end
    -- One step per battle frame, not per draw: a frame drawn twice must not
    -- advance the bar twice.
    if state.expFrame == battle.frame then return state.expPixels end
    state.expFrame = battle.frame

    local level = mon and mon.level or state.expLevel
    if level and state.expLevel and level > state.expLevel then
      state.expLevelCycles = (state.expLevelCycles or 0) + level - state.expLevel
      state.expLevel = level
      if not state.expPhase then state.expPhase = "fill_level" end
    elseif level and level ~= state.expLevel then
      state.expLevel = level
    end

    if state.expPhase == "fill_level" then
      state.expPixels = math.min(EXP_WIDTH, state.expPixels + 1)
      if state.expPixels == EXP_WIDTH then
        state.expPhase = "hold_level"
        state.expHoldFrames = EXP_LEVEL_HOLD_FRAMES
        state.expBurstFrame = 0
      end
    elseif state.expPhase == "hold_level" then
      if state.expBurstFrame then
        if state.expBurstFrame < #EXP_BURST_DIAGONALS - 1 then
          state.expBurstFrame = state.expBurstFrame + 1
        else
          state.expBurstFrame = nil
        end
      end
      if state.expHoldFrames > 0 then
        state.expHoldFrames = state.expHoldFrames - 1
      else
        state.expLevelCycles = math.max(0, (state.expLevelCycles or 1) - 1)
        local cap = battle.data.constants and battle.data.constants.levelCap or 100
        state.expBurstFrame = nil
        if state.expLevelCycles > 0 then
          state.expPixels = 0
          state.expPhase = "fill_level"
        elseif mon and mon.level >= cap then
          state.expPhase = nil
          state.expPixels = EXP_WIDTH
        else
          state.expPixels = 0
          state.expPhase = "after_level"
        end
      end
    elseif state.expPhase == "after_level" then
      state.expPixels = math.min(target, state.expPixels + 1)
      if state.expPixels >= target then state.expPhase = nil end
    elseif state.expPixels < target then
      state.expPixels = math.min(target, state.expPixels + 1)
    elseif state.expPixels > target then
      state.expPixels = math.max(target, state.expPixels - 1)
    end
    return state.expPixels
  end

  -- ------- what colour
  --
  -- On a colourised mode the bar is Gen 2's blue.  Otherwise it takes the
  -- shade the palette pass would give that spot anyway, so a monochrome or
  -- retinted boot gets a bar that belongs to the picture it is on rather than
  -- a blue line laid across it.
  local function paletteExpColor(battle)
    local colors = battle.zoneColorsAt and battle:zoneColorsAt(EXP_X, EXP_Y)
    if not colors then return EXP_BLACK end
    local bgp = battle.activeBgp and battle:activeBgp()
    colors = PaletteFX.effectiveColors(PaletteFX.permute(colors, bgp))
    local color = colors and colors[3]
    if not color then return EXP_BLACK end
    return { color[1] / 255, color[2] / 255, color[3] / 255, 1 }
  end

  -- ------- the glyph
  --
  -- Built once into an image and drawn, with the per-pixel rectangles kept as
  -- the fallback: a headless host has no love.image to build ImageData with,
  -- and a test that cannot draw the glyph at all cannot check it is there.
  local xpTileImage
  local function drawXpTile(x, y)
    local g = love.graphics
    if xpTileImage == nil then
      xpTileImage = false
      if love.image and love.image.newImageData and g.newImage then
        local data = love.image.newImageData(8, 8)
        for py, row in ipairs(XP_TILE_ROWS) do
          for px = 1, 8 do
            if row:sub(px, px) == "x" then
              data:setPixel(px - 1, py - 1, 0, 0, 0, 1)
            end
          end
        end
        xpTileImage = g.newImage(data)
        xpTileImage:setFilter("nearest", "nearest")
      end
    end
    if xpTileImage then
      g.setColor(1, 1, 1, 1)
      g.draw(xpTileImage, x, y)
      return
    end
    g.setColor(0, 0, 0, 1)
    for py, row in ipairs(XP_TILE_ROWS) do
      for px = 1, 8 do
        if row:sub(px, px) == "x" then
          g.rectangle("fill", x + px - 1, y + py - 1, 1, 1)
        end
      end
    end
  end

  -- Eight particles thrown out from the end of a full bar, on the frame it
  -- fills: four on the axes at 2px a frame, four on the diagonals at a
  -- hand-picked sequence, which is how the original reads.
  -- `minX` is the move panel's right edge when one is up -- see clearOfPanel.
  -- The burst is thrown from the bar's left end, which is the end that runs
  -- under the panel, so most of it lands there.  Dropped dot by dot rather
  -- than as a whole: a dot is `scale` square and either clears the edge or
  -- does not, so there is nothing to round.
  local function drawExpBurst(frame, centerX, centerY, scale, color, mark, minX)
    if frame == nil then return end
    local g = love.graphics
    local radius = frame * 2 * scale
    local diagonal = EXP_BURST_DIAGONALS[frame + 1] * scale

    local function particle(dx, dy)
      local x = centerX + dx - 4 * scale
      local y = centerY + dy - 4 * scale
      for py, row in ipairs(EXP_BURST_TILE_ROWS) do
        for px = 1, 8 do
          if row:sub(px, px) == "x" then
            local dotX = x + (px - 1) * scale
            local dotY = y + (py - 1) * scale
            if not (minX and dotX < minX) then
              g.rectangle("fill", dotX, dotY, scale, scale)
              if mark then PaletteFX.markTrueColor(dotX, dotY, scale, scale) end
            end
          end
        end
      end
    end

    g.setShader()
    g.setColor(color[1], color[2], color[3], color[4])
    particle(radius, 0)
    particle(diagonal, diagonal)
    particle(0, radius)
    particle(-diagonal, diagonal)
    particle(-radius, 0)
    particle(-diagonal, -diagonal)
    particle(0, -radius)
    particle(diagonal, -diagonal)
  end

  -- ------- the wide layout's own bar
  --
  -- The wide HUD has room the classic one does not, so the bar gets a box and
  -- a label rather than a bare two-pixel line: "XP:" then ten cells of the
  -- engine's own HP-bar tiles, which fill in eighths exactly the way the HP
  -- bar above it does.
  local function drawWideExpBar(px, color, sx, sy)
    local g = love.graphics
    sx, sy = sx or 0, sy or 0
    g.setShader()
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 184 + sx, 88 + sy, 120, 16)

    local border = Font.BORDER
    Font.drawCode(border.v, 184 + sx, 88 + sy)
    Font.drawCode(border.v, 296 + sx, 88 + sy)
    Font.drawCode(border.bl, 184 + sx, 96 + sy)
    Font.drawCode(border.br, 296 + sx, 96 + sy)
    for x = 192, 288, 8 do Font.drawCode(border.h, x + sx, 96 + sy) end

    g.setColor(0, 0, 0, 1)
    drawXpTile(192 + sx, WIDE_EXP_Y + sy)
    HudTiles.tile(0x62, 200 + sx, WIDE_EXP_Y + sy)

    local fill = math.floor(px * WIDE_EXP_SEGMENTS * 8 / EXP_WIDTH)
    for i = 0, WIDE_EXP_SEGMENTS - 1 do
      local segment = math.min(8, math.max(0, fill - i * 8))
      HudTiles.tile(segment >= 8 and 0x6B or 0x63 + segment,
        WIDE_EXP_X + i * 8 + sx, WIDE_EXP_Y + sy)
    end
    HudTiles.tile(HudTiles.capTile(),
      WIDE_EXP_X + WIDE_EXP_SEGMENTS * 8 + sx, WIDE_EXP_Y + sy)
    if fill > 0 then
      g.setColor(color[1], color[2], color[3], color[4])
      g.rectangle("fill", WIDE_EXP_X + sx, WIDE_EXP_Y + 3 + sy, fill, 2)
      PaletteFX.markTrueColor(WIDE_EXP_X + sx, WIDE_EXP_Y + 3 + sy, fill, 2)
    end
  end

  -- ------- the bar on the voxel mod's world canvas
  --
  -- Same bar, same arithmetic, one coordinate change: every GB point goes
  -- through `toWorld`, and every LENGTH is multiplied by the scale the HUD was
  -- snapped at -- which is the HUD's own and not the battle's, because the
  -- fork gives the HUD a scale of its own (its HUD SCALE row) and the bar has
  -- to sit under the numbers rather than under the zoom.
  --
  -- Nothing here marks true colour.  The zone list belongs to the 160x144
  -- pass, and this canvas is not in it -- it reaches the screen a pixel to a
  -- pixel.  A mark taken here would not exempt this rectangle from anything;
  -- it would re-blit a region of the FRAME, at these coordinates, which is
  -- somewhere else entirely.
  --
  -- The canvas is put back even when the paint raises, so a bar that fails on
  -- one frame cannot leave the rest of the battle drawing into the world
  -- image.  The error still travels: this mod's overlay link reports it.
  local function drawSnappedExpBar(state, px, color, sx, sy, shot, toWorld,
                                   scale)
    local g = love.graphics
    local previous = g.getCanvas and g.getCanvas() or nil
    if g.setCanvas then g.setCanvas(shot.canvas) end
    local ok, problem = pcall(function()
      local x, y = toWorld(EXP_X + EXP_WIDTH - px + sx, EXP_Y + sy)
      g.setShader()
      g.setColor(color[1], color[2], color[3], color[4])
      g.rectangle("fill", x, y, px * scale, 2 * scale)
      -- The burst takes no shake here for the same reason it takes none in
      -- the classic path: it is thrown from where the bar ENDS, which is a
      -- fixed point of the HUD, not from where the bar is standing this frame.
      local bx, by = toWorld(EXP_X, EXP_Y + 1)
      drawExpBurst(state.expBurstFrame, bx, by, scale, color, false)
    end)
    if g.setCanvas then g.setCanvas(previous) end
    if not ok then error(problem, 0) end
  end

  -- ------- and out from under this mod's own move panel
  --
  -- The panel is drawn after the bar and covers it, and that covering is the
  -- whole reason the bar lives in this file rather than in the mod it came
  -- from.  It settles the PIXELS.  It does not settle the MARK.
  --
  -- `PaletteFX.markTrueColor` splices a rect onto the pass's zone list and
  -- RE-BLITS ITS REGION RAW once the pass is composed -- after everything
  -- drawn over it in the meantime.  So a marked strip lying under the panel
  -- comes back on top of it, and both halves of the mark do:
  --
  --   * the bar's own two rows, 89 and 90, as a blue line across the panel's
  --     PP row -- which is printed at y=88 and is three rows tall.
  --   * under DARK, the theme's one-pixel skirt around every UI-pass mark
  --     (runtime/theme.lua, watchArt), whose top edge is row 88 exactly: a
  --     dark line along the top of the PP line, which is what it looks like.
  --
  -- Drawing later cannot fix that and neither can any order -- the re-blit is
  -- after all of them -- so the mark has to not be there.  The bar stops where
  -- the panel starts.
  --
  -- `onTop` does not cover this: it asks whether another STATE is standing on
  -- the battle, and the move menu is not one.  It is this mod, drawing inside
  -- the battle, over itself.
  --
  -- Asked of Grid.panelRect, which is this exact question and already had to
  -- exist -- it was written for a neighbouring mod asking it from outside,
  -- and the neighbour is this file now.  nil means no panel of ours is up,
  -- and then there is nothing to clip to: MOVE PANEL off, a phase with no
  -- panel, a battle this mod does not own.
  --
  -- Both panels start at x=0, so this only ever trims the bar's LEFT end,
  -- which is the end that runs under them.  A panel that started further in
  -- would be over-clipped rather than mis-marked, and for a mark that is the
  -- safe direction to be wrong in.
  -- The panel's right edge when one is up and it lies across these rows, and
  -- NIL when there is nothing to clip to.  Nil rather than the caller's own x,
  -- because the burst reaches left of where it is thrown and "no panel" has to
  -- be distinguishable from "a panel that happens to end here".
  local function panelEdge(battle, y, height)
    if type(panelRect) ~= "function" then return nil end
    local ok, panel = pcall(panelRect, battle)
    if not ok or type(panel) ~= "table" then return nil end
    if type(panel.x) ~= "number" or type(panel.y) ~= "number"
       or type(panel.w) ~= "number" or type(panel.h) ~= "number" then
      return nil
    end
    if y + height <= panel.y or y >= panel.y + panel.h then return nil end
    return panel.x + panel.w
  end

  -- ------- the shake
  --
  -- battle.overlay runs after BattleState:draw has popped the shake it pushed
  -- around the HUDs, so a bar drawn here does not inherit it and has to be
  -- moved by hand or it stands still while the HUD it belongs to rattles.
  -- The last clause is the engine's own fallback for a shake with no explicit
  -- offset (BattleState's `fx.shake`).
  local function shakeOf(battle)
    local fx = battle.fx
    local sx = fx and fx.shakeX or 0
    local sy = fx and fx.shakeY or 0
    if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
      sx = battle.frame % 4 < 2 and 2 or -2
    end
    return sx, sy
  end

  -- ------- draw
  --
  -- Called from this mod's own battle.overlay link, BEFORE the button grid,
  -- which is the whole reason the bar is in this file: the panel goes down on
  -- top of it and covers exactly as much of it as the panel is wide.  There
  -- is no clip here and there is not meant to be one.
  -- Every reason there is not to draw, in one place, so a case can ask the
  -- question without a canvas to answer it on.
  function XP.wouldDraw(battle)
    if not C.option("xp_bar", true) then return false end
    if type(battle) ~= "table" or not battle.isBattle then return false end
    if battle.blankForAskName then return false end
    -- Safari has no mon of yours in the fight, the old man demo's player is a
    -- placeholder, showPlayerBack is the send-out before the HUD exists, and
    -- a sliding intro has not put the HUD in place yet.
    if not battle.player or battle.safari or battle.demo
       or battle.showPlayerBack then return false end
    if (battle.introSlide or 0) ~= 0 then return false end
    if not playerHudVisible(battle) then return false end
    if not onTop(battle) then return false end
    return true
  end

  function XP.draw(battle)
    if not XP.wouldDraw(battle) then return end

    local colorMode = PaletteFX.mode
    local blue = colorMode == "ogred" or colorMode == "gbc"
      or colorMode == "redpp"
    local color = blue and EXP_BLUE or paletteExpColor(battle)

    local state = stateFor(battle)
    local px = animatedExpPixels(battle, state)
    local sx, sy = shakeOf(battle)

    -- Set only while the HUDs really are on the voxel mod's canvas: not with
    -- no voxel mod, not under a fork that leaves them in the frame, and not
    -- on a platform where the fork declined.  Every one of those is the
    -- classic path below, unchanged.
    local shot = voxel and voxel.snappedShot(battle) or nil
    if shot then
      -- Asked before the wide branch and not inside it, because a snapped
      -- battle is never wide: the fork pins the layout to OG while it is
      -- drawing the battle in 3D (its own forceOG), so the two cannot meet.
      if px <= 0 then return end
      local toWorld, scale = voxel.hudTransform(shot, "player")
      if not toWorld then
        -- The fork snapped the HUDs but does not publish where it put them.
        -- Nothing here can be guessed -- a bar in the wrong place on a
        -- window-sized canvas is the loudest failure this file has -- so it
        -- stands down for the frame and the battle simply has no XP bar.
        return
      end
      drawSnappedExpBar(state, px, color, sx, sy, shot, toWorld, scale)
      return
    end

    if battle:wideLayout() then
      drawWideExpBar(px, color, sx, sy)
      drawExpBurst(state.expBurstFrame,
        WIDE_EXP_X + WIDE_EXP_SEGMENTS * 8, WIDE_EXP_Y + 4,
        1, color, true)
      return
    end

    if px <= 0 then return end
    -- Anchored on the RIGHT: the bar grows leftwards out from under the HP
    -- numbers, which is where Gen 2 puts its own.
    local x = EXP_X + EXP_WIDTH - px + sx
    local y = EXP_Y + sy
    -- The panel is a menu and does not shake, so the edge is taken as it is
    -- drawn rather than as the bar is moved.
    local edge = panelEdge(battle, y, 2)
    local left = (edge and edge > x) and edge or x
    local width = px - (left - x)
    if width <= 0 then return end
    love.graphics.setShader()
    love.graphics.setColor(color[1], color[2], color[3], color[4])
    love.graphics.rectangle("fill", left, y, width, 2)
    -- Exempt from the palette pass, or a colourised boot quantises the blue
    -- back into the zone's own four shades.  The rect MARKED is the rect
    -- DRAWN, always: a mark over ground this bar did not paint re-blits
    -- whatever is there raw, which is the same bug pointed the other way.
    PaletteFX.markTrueColor(left, y, width, 2)
    -- The same edge, asked on the bar's own rows: the burst is thrown from one
    -- pixel under them and the panel is forty rows tall, so a panel lying
    -- across the bar lies across the burst too.
    drawExpBurst(state.expBurstFrame, EXP_X, EXP_Y + 1, 1, color, true, edge)
  end

  -- Published for the same reason the geometry is: a mod that wants to know
  -- how far along the bar is should read it rather than recompute the curve.
  XP.pixels = expPixels

  return XP
end
