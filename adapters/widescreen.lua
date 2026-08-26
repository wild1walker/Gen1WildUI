-- Widescreen Battle Intro, fitted into the bundle.
--
-- The mod keeps its two settings in the save's own options bucket rather than
-- in a mod.options schema, and registers them as rows on the engine's OPTIONS
-- screen. Inside a bundle whose whole premise is one row per feature, that
-- would put them in two places and neither next to their own switch, so the
-- registration is suppressed (in features.lua) and the same two rows are
-- rebuilt here on the bundle's own screen.
--
-- The rows are driven through the option pairs the mod publishes, not through
-- storage this file reaches into itself. That matters: the mod mirrors every
-- write into both the loader's option table and the live save, and a second
-- writer that knew about only one of them would drift from the first the
-- moment a session saved.

local Adapter = {}

function Adapter.install(mod, context, feature)
  local exports = mod.exports

  local function pair(name)
    local p = exports[name]
    if type(p) == "table" and type(p.get) == "function"
       and type(p.set) == "function" then
      return p
    end
    return nil
  end

  local flashless = pair("flashless")
  local outro = pair("outro")

  if not (flashless or outro) then
    -- A version that no longer publishes them. Rather than reach into the
    -- save behind its back, leave its own OPTIONS rows alone -- features.lua
    -- suppresses that hook, so say plainly that the setting has gone
    -- somewhere this menu cannot follow.
    mod.log:warn("publishes no option pairs; its rows are not on the bundle "
      .. "menu. Check what this version calls them and update "
      .. "adapters/widescreen.lua")
    return
  end

  context.customRows[feature.id] = function()
    local rows = {}

    if flashless then
      rows[#rows + 1] = {
        id = "widescreen_flashless",
        label = "FLASHLESS INTROS",
        description = "EVERY BATTLE OPENS ON THE CHAMPION FIGHT'S OUTWARD SPIRAL INSTEAD OF THE PALETTE FLASH.",
        value = function() return flashless.get() and "ON" or "OFF" end,
        step = function() flashless.set(not flashless.get()) end,
      }
    end

    if outro then
      rows[#rows + 1] = {
        id = "widescreen_outro",
        label = "BLACK OUTRO",
        description = "ENDS A BATTLE ON A SLOW FADE TO BLACK INSTEAD OF THE WHITE FLASH.",
        value = function() return outro.get() and "ON" or "OFF" end,
        step = function() outro.set(not outro.get()) end,
      }
    end

    return rows
  end
end

return Adapter
