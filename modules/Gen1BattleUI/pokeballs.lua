-- Gen1BattleUI: the ball you threw is the ball you see.
--
-- Ported from Pokeball Colors by Mister Miracle (MIT, mod id
-- pokeball_colors), cut down to the five balls Red, Blue and Yellow
-- actually have.  What that mod carries and this does not is its whole
-- other-mods surface -- the registerColors and registerColorResolver
-- registries, the colours it keeps for Custom Poke Balls, Too Many Balls
-- and Snag Quest, the Gold heal machine, and the mart-stocking dev
-- toggle.  A ball from a mod is that mod's business and Pokeball Colors
-- is where it is answered; this is the battle UI mod colouring the balls
-- the battle UI already draws.  Which is also why the deference below
-- exists: with that mod installed, this file stands down whole.
--
-- ------- what is wrong without it
--
-- Under COLORS = ADVANCED every OAM sprite in a battle is coloured from
-- the SGB zone under it, and the ball is a sprite like any other: the
-- toss, the wobbles and the resting caught ball come out in whatever
-- palette the background happens to be using, so a GREAT BALL and an
-- ULTRA BALL throw the same colour as each other and as the grass behind
-- them.  There is one funnel where that is decided --
-- BattleState:animSpriteColors(s, px, py), which drawAnimLayer builds
-- its colorFn from for the playing animation and for the resting
-- lockedBall alike -- and a wrap of it is the whole battle half of this
-- file.
--
-- ------- three colours out of a two-tone sprite
--
-- The ball tiles use all three opaque DMG indices: 1 is the bottom
-- crescent and the centre dot, 2 the upper body mass, 3 the perimeter
-- outline.  Vanilla's rOBP0 shade map ({0,3,3}) collapses 2 and 3 onto
-- one shade, so on hardware the ball is two-tone and the outline is
-- simply the body's darkest edge.  A wrap REPLACES that return, so it is
-- not bound by the map and can hand back three distinct colours.
--
-- The band along the seam is not any of those three regions, though --
-- those pixels are index 2, indistinguishable from the body.  So the
-- band comes with re-indexed art: a copy of the generated sheet in which
-- the seam pixels of six tiles become index 3 and the outline ring
-- becomes 2.  Painted { accent, body, line } that is the band; painted
-- { accent, body, body } it is pixel-identical to vanilla, which is what
-- a ball with no `line` and a player with the band off both get.
--
-- The copy is rebuilt at runtime from the player's OWN extracted sheet.
-- This art is ROM-derived and the engine is built so Nintendo's graphics
-- come out of the player's cartridge and are never redistributed; what
-- ships here is the pixel-role table (BAND_TILES) and nothing else.
--
-- The substitution is made at AnimPlayer:sheetImage rather than by
-- patching the battle_anims registry: a `tilesheet:0` patch would be
-- global -- every colour mode, and BLOCKBALL_ANIM, SOFTBOILED and the
-- spiral-ball emitters all draw from these same tiles -- and would
-- collide with any other mod patching that record.
--
-- ------- and at the Pokemon Center
--
-- The heal machine lights one ball per party member and paints them all
-- the same.  The engine records nothing about what caught a Pokemon, so
-- this does: `pokemon.caught` carries the live mon table and the ball id
-- (BattleState.lua:5261), and the machine reads it back off the party.
-- Never overwritten once set, so a Pokemon caught while some other mod
-- owned that field keeps the answer that mod gave.
--
-- ------- and this one DOES write to the save.  Say so plainly.
--
-- Gen 1 records nothing about what caught a Pokemon.  Not in the engine
-- -- Pokemon.new builds species, level, exp, dvs, statExp, stats, hp,
-- catchRate, status and moves -- and not in the ROM it recompiles, whose
-- party struct has no ball anywhere in it.  Nor does Gen 2: the caught
-- data Crystal adds is time, level, location and OT gender, which is
-- exactly what this engine's own Gen 2 mon carries (Breeding.lua,
-- Evolution.lua).  GEN 3 is the first generation to record the ball at
-- all, as four bits in the Misc substruct's origins halfword.  So this
-- feature cannot be free: it exists only because a field is invented.
--
-- And it is invented in this engine's idiom, not the ROM's.  A Lua key
-- on a mon table is how species, otId, nickname and traded are all
-- stored here, so it is the right shape for this codebase -- but it
-- corresponds to no byte in the real save format, and
-- GenSave.encodeMon writes fixed offsets from a known field list.  On
-- export to a 32768-byte .sav the field is not written, because there
-- is nowhere to write it.  Convert out and back and the machine lights
-- every ball red until the party turns over.  Cosmetic, and the only
-- honest place for it to fail.
--
-- `mon.caughtBall` goes onto the mon table, which IS save.party[i], and
-- SaveSerializer.encode is a generic pairs() recursion that writes every
-- key it finds -- so the field lands in the save file beside `species`
-- and `dvs`, and it stays there after this mod is uninstalled.  One
-- string per Pokemon caught, and nothing reads it but this and Pokeball
-- Colors.
--
-- The engine does offer a namespaced alternative: mod.save:get/set,
-- backed by save.modData["Gen1BattleUI"], a per-mod bucket with its own
-- version-keyed migration chain (Loader.lua:1349).  It is not used here,
-- deliberately.  A side table needs a key and a Gen 1 Pokemon has no
-- unique id -- the engine mints none -- so the best available key is a
-- content fingerprint (OT id, nickname, DVs), which is a heuristic that
-- can collide, and a party slot, which cannot survive a deposit.  A
-- field ON the Pokemon needs no key at all: it goes where the Pokemon
-- goes, through the box, through a trade, forever.  It is also the field
-- Pokeball Colors already owns and already writes by the same
-- only-if-absent rule, which is what lets the two of them share a save
-- and never disagree.
--
-- The trade, stated once so it is not discovered: a removable mod that
-- leaves nothing behind was worth less here than the feature working on
-- the Pokemon rather than on a guess about which Pokemon it is.
--
-- Untouched on purpose: POOF clouds (ambient zone colours, as vanilla),
-- every non-ball animation, every colour mode except ADVANCED -- the
-- mono modes have no per-sprite colour to give and animSpriteColors
-- returns nil there, which is passed straight through -- and every last
-- thing about catch rates, items and marts.

-- The four balls whose series art has a visible band get one; ULTRA_BALL
-- is deliberately left without.  Its accent is already {40,40,40}, so a
-- black band would sit against a near-black crescent and read as
-- nothing.
local BLACK = { 0, 0, 0 }

-- `body` is the larger region and `accent` the smaller highlight -- that
-- way round, and not the other: under the f0 shade map the sprite's body
-- is DMG colours 2/3, about twice the pixel area, and the accent is
-- colour 1.
local COLORS = {
  POKE_BALL   = { body = { 224,  72,  56 }, accent = { 248, 216, 208 },
                  line = BLACK },
  GREAT_BALL  = { body = {  56, 112, 216 }, accent = { 208, 224, 248 },
                  line = BLACK },
  ULTRA_BALL  = { body = { 232, 192,  40 }, accent = {  40,  40,  40 } },
  MASTER_BALL = { body = { 152,  72, 200 }, accent = { 232, 200, 248 },
                  line = BLACK },
  SAFARI_BALL = { body = { 112, 160,  72 }, accent = { 224, 232, 200 },
                  line = BLACK },
}

-- The anims that are part of a ball chain.  The toss rows carry the ball
-- id themselves; SHAKE_ANIM and the resting ball do not, so the chain
-- remembers it for them.
local BALL_MOVES = {
  TOSS_ANIM = true, GREATTOSS_ANIM = true, ULTRATOSS_ANIM = true,
  SHAKE_ANIM = true,
}

-- tile id -> the pixels whose DMG colour index changes, in tile-local
-- coordinates.  `body` are the perimeter outline pixels (3 -> 2, so they
-- join the body); `line` are the seam pixels (2 -> 3, so they become the
-- band).  Everything else is copied untouched.
--
-- Tiles 2/18 are the upright ball (the three tosses, mirrored for the
-- right half, which is why their data is symmetric) and 6/7/22/23 the
-- tilted one (SHAKE).  Derived from the 0.1.75 extraction of Red and
-- Yellow, whose move_anim_0.png are byte-identical.
local BAND_TILES = {
  [2]  = { body = { {6,4}, {7,4}, {4,5}, {5,5}, {3,6}, {3,7} },
           line = {} },
  [6]  = { body = { {5,4}, {6,4}, {7,4}, {3,5}, {4,5}, {2,6}, {2,7} },
           line = {} },
  [7]  = { body = { {0,4}, {1,5}, {2,5}, {3,6}, {3,7} },
           line = {} },
  [18] = { body = { {2,0}, {2,1}, {2,2}, {2,3}, {3,4}, {3,5}, {4,6},
                    {5,6}, {6,7}, {7,7} },
           line = { {3,1}, {4,1}, {5,1}, {5,2}, {6,2}, {7,2} } },
  [22] = { body = { {1,0}, {1,1}, {1,2}, {1,3}, {2,4}, {2,5}, {3,6},
                    {4,6}, {5,7}, {6,7}, {7,7} },
           line = { {6,2}, {7,2}, {2,3}, {3,3}, {4,3}, {5,3}, {6,3} } },
  [23] = { body = { {4,0}, {4,1}, {4,2}, {4,3}, {3,4}, {3,5}, {1,6},
                    {2,6}, {0,7} },
           line = { {2,0}, {3,0}, {1,1}, {2,1}, {0,2}, {1,2} } },
}

-- the generated sheets are GB greys: index 1 = 170, 2 = 85, 3 = 0
-- (tools/extract/gfx.py GB_SHADES).  LOVE 11 takes 0-1 floats.
local SHADE_BODY, SHADE_LINE = 85 / 255, 0

-- The heal machine's own flash beat: FlashSprite8Times swaps the two
-- middle shades in place, and a recoloured ball has to flash with the
-- rest of the machine rather than sit still through the jingle.
local HEAL_FLASH_MAP = { [0] = 0, [1] = 2, [2] = 1, [3] = 3 }

return function(mod, C)
  local Balls = {}

  -- Published so the suite can assert against the numbers this file
  -- draws from, and so "which mod coloured this ball" is answerable.
  Balls.colors = COLORS

  local function warn(fmt, ...)
    if mod.log and type(mod.log.warn) == "function" then
      mod.log:warn(fmt, ...)
    end
  end

  local function info(fmt, ...)
    if mod.log and type(mod.log.info) == "function" then
      mod.log:info(fmt, ...)
    end
  end

  -- Every module here is pcall-required and every failure is a reason
  -- string rather than a throw.  Unlike the menu, which is the mod, a
  -- ball this file cannot colour is a vanilla ball -- there is no
  -- version of "the battle stops" that is better than that.
  local function need(name)
    local ok, value = pcall(require, name)
    if ok and type(value) == "table" then return value end
    return nil
  end

  local PaletteFX = need("src.render.PaletteFX")
  local BattleState = need("src.battle.BattleState")
  local AnimPlayer = need("src.battle.AnimPlayer")
  local OverworldState = need("src.world.OverworldController")
  local Runtime = need("src.mods.Runtime")

  -- The mod manager's [ERRS] screen is the only channel that says
  -- anything on a device with no console, and the whole symptom of a
  -- failed band rebuild is "the band just isn't there" -- which is
  -- indistinguishable from the option being off.
  local function report(fmt, ...)
    local msg = string.format(fmt, ...)
    warn("%s", msg)
    if Runtime and type(Runtime.reportError) == "function" then
      pcall(Runtime.reportError, "Gen1BattleUI", msg)
    end
  end

  local gameRef              -- the live game, from game.ready
  local activeBattle         -- the BattleState whose ball chain is running

  -- ------- standing down for the mod this came from
  --
  -- Pokeball Colors does all of this and more, and two mods wrapping one
  -- funnel is a silent last-writer-wins conflict -- worse here than
  -- usual, because its band sheet and our band sheet would be served by
  -- two independently gated wraps of the same call.  So if it is
  -- installed, it wins: it owns the balls, including the ones with no
  -- colour here, and this file passes everything through untouched.
  --
  -- Checked at install AND at game.ready, because load order is the
  -- loader's and this mod's priority is nowhere near that one's.
  -- game.ready is before any battle draws, which is all the guarantee a
  -- draw-time gate needs.
  local deferring = false
  local function checkDeference()
    if type(mod.find) ~= "function" then return end
    local ok, other = pcall(mod.find, "pokeball_colors")
    if ok and other and not deferring then
      deferring = true
      info("Gen1BattleUI: pokeball_colors is installed and owns the ball "
           .. "colours; standing down")
    end
  end

  -- ------- is this frame ours to colour
  --
  -- ADVANCED only.  The mono and classic modes deliberately have no
  -- per-sprite colour to give, and passing their nil through is what
  -- leaves them exactly as they were.
  local function active()
    if deferring then return false end
    if not C.option("ball_colour", true) then return false end
    return PaletteFX ~= nil and PaletteFX.mode == "redpp"
  end

  local function norm(c)
    return { c[1] / 255, c[2] / 255, c[3] / 255 }
  end

  -- One warning per unknown ball id actually seen on screen, so a ball
  -- rendering in vanilla colours gives a reason instead of silence.
  local warnedMissing = {}
  local function warnMissingColor(ball)
    if ball and not warnedMissing[ball] then
      warnedMissing[ball] = true
      warn("Gen1BattleUI has no colour for the ball %s -- it renders in "
           .. "vanilla colours.  This mod covers the five balls Red, Blue "
           .. "and Yellow ship with; Pokeball Colors is the mod that "
           .. "covers balls added by other mods", tostring(ball))
    end
  end

  -- ------- the self-check behind the band
  --
  -- The re-indexed sheet is only correct if WE supply the palette: index
  -- 3 is black there, so anything that blits it raw draws a GB-grey ball
  -- with a black band.  That is not hypothetical -- a sprite pack that
  -- ships its own pre-coloured ball art and passes `colorFn = nil` in
  -- true-colour mode leaves our sheet wrap firing while our colour wrap
  -- never runs.
  --
  -- It cannot be seen from here: colorFn is nilled downstream of us.  So
  -- it is detected by RESULT instead.  Across one ball chain, our sheet
  -- going out without our colour pass running is a contradiction -- it
  -- cannot happen while we are the ones painting -- and it is checked at
  -- the start of the NEXT chain, when both answers are in.  One throw
  -- looks wrong, then the band switches off for the session and the
  -- other mod's own art shows through, which is the right outcome: their
  -- balls are already coloured.
  --
  -- Deliberately not keyed on any mod id.  Anything that suppresses the
  -- anim palette pass produces the same contradiction and gets the same
  -- answer, including mods written after this.
  local chainWanted, bandColorRan = false, false
  local conflictDetected, colorPassEverRan = false, false

  -- ------- the re-indexed sheet
  --
  -- Built once and lazily: a graphics context exists at draw time but
  -- not necessarily at load, and a headless run must not fault here.
  -- Any failure reports once and falls back to the vanilla sheet, which
  -- is the two-tone ball -- never a crash, never a missing sprite.
  local bandImage            -- a love Image, or false once a build failed
  local function bandSheet(ap)
    if bandImage ~= nil then return bandImage or nil end
    bandImage = false                          -- never retry per frame
    local sheet = ap and ap.data and ap.data.tilesheets
                  and ap.data.tilesheets[0]
    if not (sheet and sheet.path and love and love.image
            and love.image.newImageData and love.graphics
            and love.graphics.newImage) then
      report("no ball band: tilesheet 0 or the graphics context is "
             .. "unavailable")
      return nil
    end
    local ok, img = pcall(function()
      local id = love.image.newImageData(sheet.path)
      local cols = math.floor(id:getWidth() / 8)
      for tile, spec in pairs(BAND_TILES) do
        local tx, ty = (tile % cols) * 8, math.floor(tile / cols) * 8
        local function paint(list, v)
          for i = 1, #list do
            id:setPixel(tx + list[i][1], ty + list[i][2], v, v, v, 1)
          end
        end
        paint(spec.body, SHADE_BODY)
        paint(spec.line, SHADE_LINE)
      end
      return love.graphics.newImage(id)
    end)
    if not (ok and img) then
      report("no ball band: the sheet rebuild failed (%s)", tostring(img))
      return nil
    end
    bandImage = img
    return img
  end

  -- Does this ball render with a band right now?  Every gate the colour
  -- wrap applies, so the art and the palette can never disagree.
  local function bandColor(ball)
    if not ball then return nil end
    if conflictDetected then return nil end
    -- never serve the re-indexed sheet before our palette is known to
    -- land on it; blitted raw it is grey with a black band
    if not colorPassEverRan then return nil end
    if not active() then return nil end
    if not C.option("ball_band", true) then return nil end
    local c = COLORS[ball]
    return c and c.line or nil
  end

  -- The ball a given AnimPlayer is drawing right now.
  local function ballOf(ap)
    if not ap then return nil end
    return ap._g1bBall
      or (ap._g1bMove and BALL_MOVES[ap._g1bMove]
          and activeBattle and activeBattle._g1bBall)
      or nil
  end

  -- ------- the Pokemon Center's palette
  --
  -- Built the same way the machine's own jingle flash is built: fxHeal
  -- sends permuted GRAYS through the same shader, so a ball painted this
  -- way is the machine's own effect in different colours rather than
  -- something drawn over the top of it.
  --
  -- `line` is deliberately not used here.  The machine draws a DIFFERENT
  -- sprite -- the heal machine sheet's ball quad, not the anim tilesheet
  -- -- so its darkest shade is an outline and not a seam, and a band and
  -- an outline are not the same region.  The machine keeps the darkened
  -- body it has always had.
  local function ballPalette(c, flashed)
    local dark = { math.floor(c.body[1] * 0.35),
                   math.floor(c.body[2] * 0.35),
                   math.floor(c.body[3] * 0.35) }
    local pal = { PaletteFX.GRAYS[1], c.accent, c.body, dark }
    if flashed then pal = PaletteFX.permute(pal, HEAL_FLASH_MAP) end
    return pal
  end

  -- ------- installing
  --
  -- Every wrap keeps the vanilla function on the module under a key of
  -- this mod's own, so a second load wraps the original rather than
  -- wrapping the wrapper.
  local installed = false

  function Balls.install()
    if installed then return true end
    if not (PaletteFX and BattleState and AnimPlayer
            and type(BattleState.animSpriteColors) == "function"
            and type(BattleState.ballChain) == "function"
            and type(AnimPlayer.start) == "function") then
      return false, "this engine has no ball animation seam to colour"
    end
    installed = true
    checkDeference()

    -- tracker 1: what the AnimPlayer is playing.  Toss rows carry
    -- opts.ball into AnimPlayer:start (BattleState.lua ~1188); every
    -- start overwrites both fields, so nothing goes stale between rows.
    AnimPlayer._g1bOriginals = AnimPlayer._g1bOriginals
      or { start = AnimPlayer.start, sheetImage = AnimPlayer.sheetImage }
    local vanillaStart = AnimPlayer._g1bOriginals.start
    AnimPlayer.start = function(self, moveId, attackerIsPlayer, opts)
      self._g1bMove = moveId
      self._g1bBall = opts and opts.ball or nil
      return vanillaStart(self, moveId, attackerIsPlayer, opts)
    end

    -- tracker 2: the ball of the current toss chain.
    -- BattleState:ballChain(tossAnim, caught, shakes, ball) sees the ball
    -- for the whole toss/poof/shake chain (~4502), which is what covers
    -- the SHAKE rows and the resting lockedBall -- neither of which ever
    -- sees opts.ball.
    BattleState._g1bOriginals = BattleState._g1bOriginals or {
      ballChain = BattleState.ballChain,
      animSpriteColors = BattleState.animSpriteColors,
    }
    local vanillaBallChain = BattleState._g1bOriginals.ballChain
    BattleState.ballChain = function(self, tossAnim, caught, shakes, ball)
      self._g1bBall = ball
      activeBattle = self
      -- the verdict on the chain that just finished: we had a colour for
      -- that ball and our palette never reached it, so something else is
      -- drawing the ball animation
      if chainWanted and not bandColorRan and not conflictDetected then
        conflictDetected = true
        report("another mod is drawing the ball animation without this "
               .. "mod's palette; deferring to its art")
      end
      bandColorRan = false
      chainWanted = ball ~= nil and active() and COLORS[ball] ~= nil
      return vanillaBallChain(self, tossAnim, caught, shakes, ball)
    end

    -- tilesheet substitution: only tileset 0, only while a ball anim is
    -- playing, only for a ball that has a `line`.  Every other animation
    -- drawing from this sheet and every other colour mode keeps the
    -- vanilla art.  Deliberately does NOT write self.images -- that is
    -- the AnimPlayer's own cache of the vanilla sheets and must not be
    -- poisoned with ours.
    local vanillaSheetImage = AnimPlayer._g1bOriginals.sheetImage
    if type(vanillaSheetImage) == "function" then
      AnimPlayer.sheetImage = function(self, ts)
        if ts == 0 and self._g1bMove and BALL_MOVES[self._g1bMove]
           and active() and not conflictDetected then
          local ball = ballOf(self)
          if ball and bandColor(ball) then
            local img = bandSheet(self)
            if img then return img end
          end
        end
        return vanillaSheetImage(self, ts)
      end
    end

    -- ------- the wrap: recolour ball sprites, pass everything else on
    local vanillaColors = BattleState._g1bOriginals.animSpriteColors
    BattleState.animSpriteColors = function(self, s, px, py)
      local out = vanillaColors(self, s, px, py)
      if not out then return out end               -- mono modes / no zone
      if not active() then
        -- Whatever we expected of this chain, we are not colouring it now:
        -- a mode switch or the option going off between the toss and the
        -- wobbles is not another mod owning the ball, and the detector
        -- below must not read it as one.
        chainWanted = false
        return out
      end
      -- ball toss and shake tiles run under rOBP0 ("f0", or "f0x" while
      -- DoBallTossSpecialEffects has the palette complemented).  rOBP1
      -- and the ambient-e4 sprites -- move anims, emitters -- are left
      -- alone.
      if s.obp ~= "f0" and s.obp ~= "f0x" then return out end

      local ap = self.animPlayer
      local ball
      if self.animPlaying and ap then
        ball = ap._g1bBall
          or (ap._g1bMove and BALL_MOVES[ap._g1bMove] and self._g1bBall)
          or nil
      elseif ap and self.lockedBall then
        -- the resting closed ball, through the caught text
        ball = self._g1bBall
      end

      local c = ball and COLORS[ball]
      if not c then
        if ball then warnMissingColor(ball) end
        return out
      end

      -- Slots are DMG colour indices 1/2/3, and the shade each one takes
      -- is the engine's own OBJ_SHADES map (BattleState.lua:6026):
      --
      --   f0  = { 0, 3, 3 }   1 -> lightest, 2 and 3 -> darkest
      --   f0x = { 3, 0, 3 }   1 -> darkest,  2 -> lightest, 3 -> darkest
      --
      -- So the light shade is the accent and the dark shade is the body,
      -- and the flicker swaps indices 1 and 2 while index 3 -- the
      -- outline ring on vanilla art, the seam band on the re-indexed
      -- sheet -- stays on the dark shade through both.
      --
      -- Which is why the band is worked out from the UNSWAPPED body and
      -- the swap is applied to the other two.  Pokeball Colors swaps the
      -- pair first and takes its fallback from whichever is `body`
      -- afterwards, so a ball with no band -- of the five here, that is
      -- the ULTRA BALL, and the ULTRA BALL is one of the two that
      -- flickers -- renders its outline ring in the accent for the
      -- flashed frames where the hardware keeps it dark.  A one-pixel
      -- ring, and near-black against gold on that ball, which is
      -- presumably why it went unnoticed.
      local accent, body = norm(c.accent), norm(c.body)
      local line = bandColor(ball)
      local dark = line and norm(line) or body
      bandColorRan, colorPassEverRan = true, true
      if s.obp == "f0x" then
        -- rOBP0 is complemented for this block by
        -- DoBallTossSpecialEffects: keep the flicker, in the ball's own
        -- colours.  The MASTER and ULTRA tosses flash on hardware --
        -- AnimPlayer falls through to its own hardcoded test for those
        -- two (AnimPlayer.lua:447-455) -- and under ULTRA's near-black
        -- accent that reads as the ball turning over.  It stops at the
        -- wobbles because SHAKE_ANIM never flickers.  It is not a bug
        -- and it is not this feature.
        return { body, accent, dark }
      end
      return { accent, body, dark }
    end

    -- ------- what caught this Pokemon
    --
    -- Written only when the field is empty, so a Pokemon caught while
    -- another mod owned it keeps that mod's answer and the two can never
    -- disagree.  Absent on anything caught before this version, which
    -- the Center reads as a POKE BALL -- canon enough, and it corrects
    -- itself as the party turns over.
    if type(mod.events) == "table" and type(mod.events.on) == "function" then
      mod.events:on("pokemon.caught", function(p)
        if deferring then return end
        if not (p and p.mon and p.ball) then return end
        if p.mon.caughtBall == nil then p.mon.caughtBall = p.ball end
      end)
      mod.events:on("game.ready", function(p)
        gameRef = p and p.game
        checkDeference()
      end)
    else
      warn("Gen1BattleUI has no event bus to hear catches on; the heal "
           .. "machine keeps its one palette")
    end

    local okCenter, centerProblem = Balls.installCenter()
    if not okCenter then
      warn("Gen1BattleUI is not colouring the Pokemon Center balls: %s",
           tostring(centerProblem))
    end
    return true
  end

  -- ------- the Pokemon Center heal machine
  --
  -- fxHeal is a LOCAL closure inside OverworldState:drawWorld
  -- (OverworldController.lua:4522), so it cannot be wrapped, and
  -- drawWorld pushes and pops transforms internally so drawing after it
  -- returns lands in the wrong space.  Instead: wrap drawWorld, and ONLY
  -- while self.healAnim exists, temporarily shim love.graphics.draw.
  --
  -- The shim recognises the ball draws exactly -- the image is
  -- self.healMachineImg AND the quad is self.healMachineQuads[2], the
  -- ball quad, where [1] is the monitor -- counts them, and the i-th
  -- ball is party slot i, because stepHealAnim lights them in party
  -- order.  It exists for the few seconds the animation runs and is
  -- restored through pcall even if vanilla throws.
  --
  -- The `type(...) == "function"` gate is a capability check, not a
  -- version one: on a Gen 2 boot this require resolves to the adapter
  -- facade, where drawWorld has no backing and reads nil.  Installing
  -- over that would write a wrapper nothing calls and stash a nil
  -- "original".  Gold's heal machine is a different screen with its own
  -- seam, and Gold is not this mod's generation.
  function Balls.installCenter()
    if not (OverworldState and PaletteFX
            and type(OverworldState.drawWorld) == "function") then
      return false, "this engine has no Pokemon Center seam to draw into"
    end
    -- The machine is painted with the machine's OWN effect -- the same
    -- shader its jingle flash sends permuted greys through -- so a host
    -- missing any part of that is one where the balls stay as they were,
    -- not one where they are drawn some other way.
    if not (type(PaletteFX.shader) == "function"
            and type(PaletteFX.sendColors) == "function"
            and type(PaletteFX.permute) == "function"
            and type(PaletteFX.GRAYS) == "table") then
      return false, "this engine's palette pass has no shader to borrow"
    end

    OverworldState._g1bOriginals = OverworldState._g1bOriginals
      or { drawWorld = OverworldState.drawWorld }
    -- Read out of the table on the call rather than closed over, which the
    -- battle wraps above deliberately do not do: those are asked once per
    -- OAM sprite and this is asked once per frame, so the table index is
    -- free here and buys the suite a seam it can put a counter behind.
    -- "The shim is not installed on a frame that is not a heal" is a claim
    -- about a whole map draw, and standing up a live OverworldState to
    -- check it would be a test of the engine rather than of this.
    local function vanillaDrawWorld(self, ...)
      return OverworldState._g1bOriginals.drawWorld(self, ...)
    end
    OverworldState.drawWorld = function(self, ...)
      local ha = self.healAnim
      if not (ha and active() and C.option("center_balls", true)) then
        return vanillaDrawWorld(self, ...)
      end

      local lg = love.graphics
      local vanillaDraw = lg.draw
      local ballIndex = 0
      lg.draw = function(img, quad, ...)
        if img ~= nil and img == self.healMachineImg
           and self.healMachineQuads and quad == self.healMachineQuads[2] then
          ballIndex = ballIndex + 1
          local party = gameRef and gameRef.save and gameRef.save.party
          local mon = party and party[ballIndex]
          local ball = (mon and mon.caughtBall) or "POKE_BALL"
          local c = COLORS[ball]
          if not c then warnMissingColor(ball) end
          if c then
            local sh = PaletteFX.shader()
            if sh then
              local prev = lg.getShader()
              PaletteFX.sendColors(sh, ballPalette(c, not ha.visible))
              lg.setShader(sh)
              vanillaDraw(img, quad, ...)
              lg.setShader(prev)
              return
            end
          end
        end
        return vanillaDraw(img, quad, ...)
      end

      local ok, err = pcall(vanillaDrawWorld, self, ...)
      lg.draw = vanillaDraw
      if not ok then error(err) end
    end

    return true
  end

  return Balls
end
