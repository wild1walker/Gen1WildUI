-- Widescreen Battle Intro
--
-- The into-battle transition opens with the palette flash
-- (BattleTransition_FlashScreenPalettes) for the two circle wipes, then
-- wipes the screen.  The engine draws both phases fullscreen: the wipe as
-- a whole-surface cascade (Renderer:drawBattleWipe) and the flash as a
-- screen-space veil (Renderer.screenVeil).  Older engines drew the flash
-- only inside the centered 160x144 letterbox, so on any window wider than
-- 4:3 it played inside a centered square while the frozen overworld
-- showed around it.
--
-- This mod extends the flash across the whole window.  The engine itself
-- has done this since 0.1.53: BattleTransition:draw hands the flash to the
-- renderer as Renderer.screenVeil, which endFrame paints over the whole
-- surface.  This mod's Renderer.endFrame wrap therefore only fires when the
-- engine drew no veil that frame -- the out-of-battle poison pulse (below)
-- and old-engine or buried-transition flashes -- so it can never
-- double-darken the engine's own fullscreen flash.  The overlay is
-- state-driven: it asks the state stack whether a battle transition is in
-- its flash phase right now (a script runner can push the transition at
-- odd points in the frame, so there is no draw/endFrame pairing to
-- desync), and the shade math mirrors the engine's exactly, so it stays
-- frame-locked to the letterbox square.
--
-- The same overlay also covers the out-of-battle poison tick: every
-- fourth step with a poisoned party member, the overworld draws a dark
-- 0.45-alpha pulse inside the 160x144 canvas (OverworldController:draw,
-- ChangeBGPalColor0_4Frames).  On a widescreen window that pulse hides
-- in the centered square, so the endFrame overlay paints the same black
-- veil over the rest of the window while the pulse is up, using the live
-- poisonFlash counter so it can never desync from the square -- and only
-- over the rest: the in-canvas rect already has the square, so the veil
-- is drawn as the bands around the letterbox to keep the flash uniform.
--
-- The wipe and black-hold phases are left to the engine's own fullscreen
-- cascade untouched.  On a 4:3 window the overlay is the same shade the
-- letterbox square already shows, so vanilla is unchanged there.
--
-- FLASHLESS INTROS (an OPTIONS row): when ON, every battle intro plays the
-- Champion battle's intro -- the outward spiral, which never flashes (the
-- champion fight is a trainer battle, and only the circle wipes flash).
-- The transition.style hook runs for every BattleTransition.new -- engine
-- spawns (OverworldState:pushBattle), scripted battles and the catch
-- tutorial alike -- so one hook covers every trigger.
--
-- BLACK OUTRO (an OPTIONS row, on by default): the way out of a battle.
-- The engine returns to the map through a white fade -- Transition
-- .battleReturn, a white veil held for 10 frames then faded out over 24
-- (the GBFadeInFromWhite the original runs on the way back) -- which on a
-- bright battle screen reads as a white flash.  This mod replaces it with
-- a slow black fade: the battle's last live frame fades OUT to black over
-- 36 frames, the battle closes behind the black, and the map fades UP out
-- of it over the same length.  The engine's white return is pushed but
-- covered, so nothing white ever shows.  lose takes the blackout path
-- (its own warp fade), so it is never touched.

local Renderer = require("src.render.Renderer")
local Game = require("src.core.Game")
local Strings = require("src.core.Strings")

-- the vanilla 3-bit wipe selection (BattleTransition.lua, from
-- battle_transitions.asm GetBattleTransitionID_*): bit 0 trainer, bit 1
-- enemy at least 3 levels above the lead, bit 2 dungeon map
local BIT_STYLES = { [0] = "doublecircle", "spiralin", "circle", "spiralout",
                     "hstripes", "shrink", "vstripes", "split" }

-- the wipe the Champion battle plays: a trainer battle against a stronger
-- foe on a non-dungeon map resolves to bits %011 = spiralout, and the
-- spiral defs never flash
local CHAMPION_STYLE = "spiralout"

-- BattleTransition_FlashScreenPalettes constants
-- (src/render/BattleTransition.lua): one palette step every FLASH_HOLD
-- frames; the first six steps fade to black (positive strength), the last
-- six back to white (negative), and the two zero steps mean "no flash on
-- screen that frame".
local FLASH_HOLD = 2
local FLASH_STEPS = {
  1 / 3, 2 / 3, 1, 2 / 3, 1 / 3, 0,
  -1 / 3, -2 / 3, -1, -2 / 3, -1 / 3, 0,
}

-- The flash the engine draws at frame t: { shade, alpha }, or nil when the
-- step is a zero-strength pause.
local function flashFor(t)
  local step = math.floor(t / FLASH_HOLD) % #FLASH_STEPS + 1
  local v = FLASH_STEPS[step]
  if v == 0 then return nil end
  return { shade = v > 0 and 0 or 1, alpha = math.abs(v) }
end

-- The overworld's poison-tick pulse (OverworldController:draw, the
-- ChangeBGPalColor0_4Frames port): poisonFlash counts 12..0 and the
-- screen darkens for one 4-frame burst in the middle.  { shade, alpha },
-- or nil when no state is pulsing.  The counter is decremented at the
-- top of the overworld's draw before the rect is painted, so by the time
-- endFrame runs (after every state drew) the value already reflects the
-- pulse that landed this frame -- the veil can never lag the square.
local POISON_SHADE = 0
local POISON_ALPHA = 0.45
local function poisonFlash(state)
  local flash = state and state.poisonFlash
  if not (flash and flash > 0) then return nil end
  if math.floor(flash / 4) % 2 == 1 then
    return { shade = POISON_SHADE, alpha = POISON_ALPHA }
  end
  return nil
end

-- The letterbox square in screen space, computed from the same renderer
-- state Renderer:endFrame uses (fitScale/uiSize + pixel dims).  The
-- overworld's in-canvas rect already darkens the square, so the poison
-- veil only paints the bands around it -- the flash is uniform across the
-- window.  Nil when the renderer can't be read (fall back to a
-- full-window rect); an empty list means the letterbox already covers the
-- window, so there is nothing to add and the engine's rect is the whole
-- flash (the 4:3 / zoomed cases, vanilla unchanged).
local function letterboxBands(self)
  local g = love and love.graphics
  if not (g and g.getDimensions and g.getPixelDimensions) then return nil end
  local ww, wh = g.getDimensions()
  local pw, ph = g.getPixelDimensions()
  local dpiX, dpiY = 1, 1
  if ww > 0 and pw > 0 then dpiX = pw / ww end
  if wh > 0 and ph > 0 then dpiY = ph / wh end
  if not (self and self.fitScale and self.uiSize) then return nil end
  local Sp = self:fitScale()
  local uiw, uih = self:uiSize()
  local vpw, vph = uiw * Sp / dpiX, uih * Sp / dpiY
  local ox = math.floor((pw - uiw * Sp) / 2) / dpiX
  local oy = math.floor((ph - uih * Sp) / 2) / dpiY
  local bands = {}
  if ox > 1e-6 then bands[#bands + 1] = { 0, 0, ox, wh } end
  if oy > 1e-6 then bands[#bands + 1] = { 0, 0, ww, oy } end
  if ww - (ox + vpw) > 1e-6 then
    bands[#bands + 1] = { ox + vpw, 0, ww - ox - vpw, wh }
  end
  if wh - (oy + vph) > 1e-6 then
    bands[#bands + 1] = { 0, oy + vph, ww, wh - oy - vph }
  end
  return bands
end

-- The wipe style for a battle context, with or without the flashless
-- toggle: ON forces every battle to the Champion battle's outward spiral;
-- OFF is the vanilla bits (mirror of BattleTransition.lua's vanillaStyle).
-- Pure, so the headless suite can assert both branches.
local function styleFor(flashless, ctx)
  if flashless then return CHAMPION_STYLE end
  return BIT_STYLES[(ctx.trainer and 1 or 0) + (ctx.stronger and 2 or 0)
                    + (ctx.dungeon and 4 or 0)]
end

-- BATTLE OUTRO timing, frames per half of the edit.  The engine's return
-- fades in from white in 24 frames (Timing.FADE_IN_FROM_WHITE); the black
-- edit is slower on purpose -- the "slow" of the request.
local OUTRO_OUT_FRAMES = 36
local OUTRO_IN_FRAMES = 36

-- Veil alpha t frames into one half of the fade: 0 on the battle's live
-- frame, 1 at the cut, back to 0 when the map is fully up.  Clamped so a
-- caller cannot overshoot a half.
local function outroAlpha(phase, t, frames)
  local a = (phase == "out") and (t / frames) or (1 - t / frames)
  return math.max(0, math.min(1, a))
end

-- Whether an ending gets the black fade: only the endings that end in the
-- engine's white battleReturn.  lose takes the blackout warp (its own
-- transition), and the PAY DAY branch is a false start -- finish() comes
-- back through here a moment later for real.
local function outroWanted(battle)
  if not (battle and battle.game and battle.game.stack) then return false end
  local result = battle.result or "run"
  if result == "lose" then return false end
  if battle.payDay and result == "win" then return false end
  return true
end

-- The fade state.  A state that owns a phase and a number: only the top
-- state updates, so the battle freezes on its last live frame while it
-- fades, and the map draws underneath the fade-in but is frozen too --
-- exactly how the engine's own battleReturn behaves.  It draws nothing
-- itself: the renderer paints the black as a screen-space veil
-- (screenVeil = { 0, a }, the same mechanism the engine uses for its
-- white fade), so it covers the whole window, letterbox and all.
local BattleOutro = {}
BattleOutro.__index = BattleOutro
BattleOutro.isOpaque = false -- the battle (out) / map (in) draws underneath

local function outroFade(game, battle, onMidpoint, outFrames, inFrames)
  return setmetatable({
    game = game, battle = battle, onMidpoint = onMidpoint,
    frames = outFrames, inFrames = inFrames, t = 0, phase = "out",
  }, BattleOutro)
end

function BattleOutro:alpha()
  return outroAlpha(self.phase, self.t, self.frames)
end

function BattleOutro:onStack(state)
  local states = self.game and self.game.stack and self.game.stack.states
  for i = #(states or {}), 1, -1 do
    if states[i] == state then return true end
  end
  return false
end

function BattleOutro:update()
  self.t = self.t + 1
  if self.t < self.frames then return end
  local stack = self.game.stack
  if self.phase == "out" then
    -- The cut, at full black: off the stack first -- BattleState:finish
    -- pops whatever is on top, which while this fade is up is the fade
    -- itself -- then the battle closes behind the black, pushing the
    -- engine's white battleReturn over the map.  Re-push over it so the
    -- map comes up out of black, not out of white.
    self.phase = "in"
    self.t = 0
    self.frames = self.inFrames
    stack:pop()
    if self.onMidpoint then self.onMidpoint() end
    -- Another fade mod may have wrapped BattleState:finish too
    -- (dramatic_shape_brick's voxel battle exit): its wrap runs instead
    -- of the battle closing and pushes its own fade on top -- the battle
    -- would sit under our fade-in and the map would never show.  Pop any
    -- such fades and re-drive the exit until the battle is really gone.
    -- Bounded, so a finish wrap that never leaves cannot wedge the game.
    local drives = 0
    while self:onStack(self.battle) do
      drives = drives + 1
      if drives > 4 then return end -- hostile: end at the cut
      if stack:top() == self.battle then return end -- a false start
      stack:pop()
      if self.onMidpoint then self.onMidpoint() end
    end
    local top = stack:top()
    if top == self.game.overworld then
      -- the battle did not actually leave, or nothing took the screen
      -- (a blackout's own warp owns the exit): end at the cut
      return
    end
    self.engineReturn = top
    stack:push(self)
    return
  end
  -- Fade-in done: the engine's white return never got to update under our
  -- black, so close it out here and hand the map back the way its onDone
  -- would -- the battle's onFinish, which the overworld is waiting on.
  stack:pop()
  local top = stack:top()
  if top == self.engineReturn and top.onDone then
    stack:pop()
    top.onDone()
  end
end

function BattleOutro:draw()
  local a = self:alpha()
  local r = self.game and self.game.renderer
  if r then
    r.screenVeil = { 0, a }
    return
  end
  local g = love and love.graphics
  if g and g.setColor and g.rectangle then
    g.setColor(0, 0, 0, a)
    g.rectangle("fill", 0, 0, 160, 144)
    g.setColor(1, 1, 1, 1)
  end
end

-- An OPTIONS row: an id, a label and an ON/OFF value that flips through
-- the caller-supplied get/set, so the menu and the headless tests share
-- one implementation.  id/label default to the FLASHLESS INTROS row's.
local function toggleRow(getFn, setFn, id, label)
  return {
    id = id or "flashless_intros",
    label = Strings(label or "FLASHLESS INTROS"),
    value = function() return getFn() and Strings("ON") or Strings("OFF") end,
    step = function() setFn(not getFn()) return true end,
  }
end

return function(mod)
  -- The overlay is state-driven: every frame's endFrame asks the state
  -- stack whether a battle transition is in its flash phase right now and
  -- paints the same shade/alpha over the whole window.  There is no
  -- draw/endFrame pairing to desync (a script runner can push the
  -- transition at odd points in the frame, and the flash always matches
  -- the letterbox square the engine draws).  The wrap only paints when the
  -- engine drew no screenVeil that frame (see Renderer.endFrame), so the
  -- engine's own fullscreen flash is never double-darkened.  Returns
  -- { shade, alpha, bands = { {x, y, w, h}, ... } } -- bands set means
  -- the overlay is the poison pulse and only the area outside the
  -- letterbox needs the veil (the canvas rect already has the square).
  local function activeFlash(self)
    local ok, Game = pcall(require, "src.core.Game")
    local stack = ok and Game and Game.stack
    if not (stack and stack.states) then return nil end
    for i = #stack.states, 1, -1 do
      local state = stack.states[i]
      -- a battle transition: wipeLen is its marker (warp fades and the
      -- white flash never carry it)
      if state and state.phase == "flash" and state.wipeLen then
        return flashFor(state.t)
      end
      -- the overworld's poison-tick pulse (poisonFlash is its marker)
      local poison = poisonFlash(state)
      if poison then
        poison.bands = letterboxBands(self)
        return poison
      end
    end
    return nil
  end

  -- Toggles ride options.lua's per-mod bucket (the same store the mod
  -- manager writes) instead of the per-save modData: NEW GAME and CONTINUE
  -- replace the save's modData outright, and an unsaved session lost
  -- toggles on quit.  options.lua survives both, so the flip stays flipped.
  -- `default` is what an absent bucket means: FLASHLESS INTROS starts OFF
  -- (vanilla intros), BLACK OUTRO starts ON (the fade is the point).
  local function optionPair(key, default)
    return {
      get = function()
        local loader = Game.mods
        local bucket = loader and loader.modOptions and loader.modOptions[mod.id]
        if bucket == nil then return default end
        local v = bucket[key]
        if v == nil then return default end
        return v
      end,
      set = function(value)
        local loader = Game.mods
        if not loader then return end
        loader.modOptions = loader.modOptions or {}
        loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
        loader.modOptions[mod.id][key] = value
        -- mirror into the active save's options so a session that saves
        -- keeps it; writeOptions persists options.lua
        if Game.save and Game.save.options then
          Game.save.options.modOptions = Game.save.options.modOptions or {}
          Game.save.options.modOptions[mod.id] =
            Game.save.options.modOptions[mod.id] or {}
          Game.save.options.modOptions[mod.id][key] = value
        end
        if Game.writeOptions then Game:writeOptions() end
      end,
    }
  end

  local FLASHLESS_KEY = "flashless_intros"
  local OUTRO_KEY = "black_outro"
  local flashless = optionPair(FLASHLESS_KEY, false)
  local outro = optionPair(OUTRO_KEY, true)

  -- FLASHLESS INTROS: with the toggle on, every battle intro becomes the
  -- Champion battle's -- the flashless outward spiral.  BattleTransition.new
  -- asks the transition.style hook for the wipe on every battle (engine
  -- spawns and scripted battles alike, the catch tutorial included), so one
  -- wrap covers every trigger; the spiral def has no flash flag, so the
  -- transition opens straight on the wipe.
  mod.hooks:wrap("transition.style", function(next, ctx)
    if flashless.get() then return styleFor(true, ctx) end
    return next(ctx)
  end)

  -- the OPTIONS rows
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    rows = next(game, rows)
    rows[#rows + 1] = toggleRow(flashless.get, flashless.set)
    rows[#rows + 1] = toggleRow(outro.get, outro.set, OUTRO_KEY, "BLACK OUTRO")
    return rows
  end)

  -- BLACK OUTRO: wrap the one place every battle ends.  The battle.ended
  -- event fires AFTER the pop, when the battle screen is already gone --
  -- nothing left to fade -- so finish() itself is wrapped, idempotently
  -- (a hot reload re-runs this file).  lose and the PAY DAY false start
  -- pass through to the engine (outroWanted), and the toggle gates the
  -- rest: ON pushes a fade over the battle's last live frame; the fade
  -- runs the engine finish at full black, then fades the map up out of it.
  local BattleState = require("src.battle.BattleState")
  if not BattleState.wsbBattleOutroHook then
    local inner = BattleState.finish
    function BattleState:finish()
      if self.wsbBattleOutro then return inner(self) end
      if not outro.get() or not outroWanted(self) then return inner(self) end
      self.wsbBattleOutro = true
      local game = self.game
      game.stack:push(outroFade(game, self, function() inner(self) end,
                                OUTRO_OUT_FRAMES, OUTRO_IN_FRAMES))
    end
    BattleState.wsbBattleOutroHook = true
  end

  local originalEndFrame = Renderer.endFrame
  function Renderer.endFrame(self, ...)
    local result = originalEndFrame(self, ...)
    local flash = activeFlash(self)
    -- The engine's own screenVeil already painted the battle flash (and
    -- the post-battle white fade) across the whole window this frame
    -- (Renderer:endFrame).  Painting again would double-darken the flash,
    -- so the overlay fires only when the engine drew no veil -- the poison
    -- pulse, and old-engine / buried-transition flashes.
    if flash and not self.screenVeil then
      local g = love and love.graphics
      if g and g.getDimensions and g.setColor and g.rectangle then
        g.push("all")
        g.setShader()
        g.setColor(flash.shade, flash.shade, flash.shade, flash.alpha)
        if flash.bands then
          -- poison pulse: the overworld's in-canvas rect already darkens
          -- the letterbox square, so only the bands around it are veiled
          for _, band in ipairs(flash.bands) do
            g.rectangle("fill", band[1], band[2], band[3], band[4])
          end
        else
          local ww, wh = g.getDimensions()
          g.rectangle("fill", 0, 0, ww, wh)
        end
        g.pop()
      end
    end
    return result
  end

  -- Script-started battles -- the overworld spawn mod's touch-to-battle
  -- path, scripted trainer fights (the rivals, Jessie & James), the
  -- static-encounter script and the catch tutorial -- route through
  -- OverworldState:pushBattle since engine commit f109530, which pushes the
  -- same BattleTransition (flash + circle wipe for wild spawns, the
  -- vanilla-bit wipes for trainers) and starts the battle music, so they
  -- need no wrap here.  The transition.style hook above still governs their
  -- wipe, FLASHLESS INTROS included.

  -- exposed for the headless test suite
  -- The two option pairs, published so a host can drive these rows from its
  -- own menu instead of the engine's OPTIONS screen. Gen1WildUI does exactly
  -- that: it suppresses the ui.options.rows registration below and rebuilds
  -- the same two rows on its own screen, so the setting has one home rather
  -- than two. Each pair is { get, set } over the same storage the rows above
  -- already use, which is what keeps the two routes in step.
  mod.exports.flashless = flashless
  mod.exports.outro = outro

  mod.exports.flashFor = flashFor
  mod.exports.poisonFlash = poisonFlash
  mod.exports.letterboxBands = letterboxBands
  mod.exports.activeFlash = activeFlash
  mod.exports.styleFor = styleFor
  mod.exports.toggleRow = toggleRow
  mod.exports.outroAlpha = outroAlpha
  mod.exports.outroWanted = outroWanted
  mod.exports.outroFade = outroFade
end
