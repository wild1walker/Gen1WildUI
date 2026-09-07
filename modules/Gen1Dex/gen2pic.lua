-- Gen1Dex on Gold, Silver and Crystal: the dex entry's pic, when the cart
-- cannot find one.
--
-- Returns a factory: factory(mod, DexData) -> { install, report }.
--
-- ------- what was reported
--
-- A dex entry for a POKeMON that HAS been seen, drawn with its name, its kind,
-- its number, its footprint and its action bar all present -- and the seven by
-- seven block where the picture goes pure black.  Measured off the screenshot
-- rather than judged by eye: that block is 118,608 pixels of a single value,
-- (0,0,0), with no second colour anywhere in it, and the whole 160x144 frame
-- carries exactly three colours -- the theme's paper, the theme's ink and the
-- dex sheet's own orange.  The POKeMON's two palette colours are not on the
-- screen at all.
--
-- `PokedexMenu:drawPic` explains that shape exactly, and only that shape:
--
--     if not image then return end
--
-- comes BEFORE the plate is filled and before the pic is laid, so a species
-- whose picture does not resolve draws nothing whatever -- not a blank plate,
-- not a placeholder, not a warning.  The page around it is untouched, which is
-- why everything else on the screen looks right.  A silent early return is the
-- one outcome that looks identical to "the mod is not installed".
--
-- ------- what this file does NOT claim
--
-- It does not know WHY `picFor` came back empty.  `def.spriteFront` is the
-- same field `src/ui/gen2/BattleState.lua:708` draws a battle pic from, and
-- battle pics work on this cart, so the field and the asset pipeline are not
-- obviously at fault.  That is precisely the reason this file exists in the
-- shape it does: it turns an invisible failure into a visible one AND into a
-- log line that names which of the three links broke --
--
--     no `self.pokemon` table at all
--     a table with no row for this species (a key that does not match)
--     a row with no `spriteFront`, or one whose image would not load
--
-- -- so the next report carries the answer instead of another black square.
-- Guessing at the cause and "fixing" it blind is how the plate arm this file
-- replaces got written.
--
-- ------- what the player sees instead
--
-- The question mark, in the question-mark palette: the cart's own way of
-- saying "I have no picture for this one", already drawn by this very
-- function for a row that has not been SEEN.  It is reached by handing the
-- base call a row that says so, rather than by drawing anything here -- so the
-- placeholder is the cart's, in the cart's colours, at the cart's size, and
-- this file draws nothing at all.
--
-- Honest rather than tidy: the dex genuinely does not have that picture, and a
-- question mark is what the dex says when it does not have a picture.

return function(mod, DexData)
  local self = {}

  -- One line per species, once per session.  A dex with a broken sheet would
  -- otherwise write a line every frame of every entry the player scrolls past.
  local told = {}
  local seen = 0

  -- Pulled out so a test can ask the question without a screen: given the
  -- three links, which one broke?
  function self.report(pokemon, species)
    if type(pokemon) ~= "table" then
      return "the dex has no `pokemon` table at all"
    end
    local def = pokemon[species]
    if type(def) ~= "table" then
      return ("no row for `%s` in the `pokemon` table -- the dex's species "
        .. "key does not match the one the sprites are filed under")
        :format(tostring(species))
    end
    if not def.spriteFront then
      return ("`%s` has no spriteFront"):format(tostring(species))
    end
    return ("`%s` has spriteFront %s, and it did not load")
      :format(tostring(species), tostring(def.spriteFront))
  end

  local MARK = "__gen1DexGen2Pic"

  function self.install()
    local okDex, PokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
    if not (okDex and type(PokedexMenu) == "table") then
      mod.log:warn("no src.ui.gen2.PokedexMenu; the missing-pic placeholder "
        .. "stands down")
      return false
    end
    if rawget(PokedexMenu, MARK) then return true end
    local basePic = PokedexMenu.drawPic
    if type(basePic) ~= "function" or type(PokedexMenu.picFor) ~= "function" then
      mod.log:warn("src.ui.gen2.PokedexMenu has no drawPic/picFor; the "
        .. "missing-pic placeholder stands down")
      return false
    end

    PokedexMenu.drawPic = function(screen, row, tx, ty, ownColors, ...)
      -- Only the case the cart draws nothing for.  A row that has not been
      -- SEEN already takes the question mark on its own, and a row whose pic
      -- resolves is none of this file's business.
      if not (row and row.seen and row.species) then
        return basePic(screen, row, tx, ty, ownColors, ...)
      end
      local okPic, image = pcall(screen.picFor, screen, row.species)
      if okPic and image then
        return basePic(screen, row, tx, ty, ownColors, ...)
      end

      if not told[row.species] then
        told[row.species] = true
        seen = seen + 1
        -- Once per species, and only the first few: a cart whose whole sheet
        -- is missing would otherwise write 251 lines into someone's log.
        if seen <= 5 then
          mod.log:warn("the #DEX has no picture for %s, so it shows the "
            .. "question mark: %s", tostring(row.species),
            self.report(screen.pokemon, row.species))
        elseif seen == 6 then
          mod.log:warn("...and more besides; the #DEX is missing pictures for "
            .. "at least six species, which is a sheet rather than a species")
        end
      end

      -- The cart's own placeholder, drawn by the cart: a row that says it has
      -- not been seen takes the questionMark path and the question-mark
      -- palette, plate and all.  Nothing is drawn here.
      local placeholder = {}
      for key, value in pairs(row) do placeholder[key] = value end
      placeholder.seen = false
      return basePic(screen, placeholder, tx, ty, ownColors, ...)
    end

    PokedexMenu[MARK] = true
    return true
  end

  return self
end
