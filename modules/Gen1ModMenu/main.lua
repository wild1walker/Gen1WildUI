-- Gen1ModMenu -- a readable mod manager for Gen1Recomp (mod api 2).
--
-- The engine's manager is src/mods/ManagerState.lua and has no hook on it.
-- What it does have is a screen id: src/ui/Screens.lua resolves "ManagerState"
-- out of the registry before its own builtin, so registering it replaces the
-- screen on every route in -- the START menu, the OPTION screen, F10, and
-- Gold's own push.
--
-- Only the drawing is replaced.  The instance handed back is the engine's
-- own, with its draw methods swapped, so the dependency closure, staged
-- changes, apply-and-restart, profiles and safe mode all stay exactly where
-- they are.  That is what `engine_internals` buys here: reaching the builtin
-- means requiring it by name.
--
-- The mod is split across src/*.lua for readability.  A mod's require is
-- sandboxed to engine modules and other mods' exports, so its own files are
-- loaded the supported way: mod:read through the loader's filesystem, then
-- load into this chunk's environment.  That works identically in the repo
-- and from an installed .zip.

local MODULE_DIR = "src/"

return function(mod)
  -- One place to turn a broken install into an attributed load error rather
  -- than a crash on the screen a player opens to fix things.
  local function loadModule(name)
    local relative = MODULE_DIR .. name .. ".lua"
    local source = mod:read(relative)
    if not source then
      mod.log:error("%s is missing from %s -- reinstall the mod",
        relative, tostring(mod.path))
      return nil
    end
    local chunk, compileError = load(source, "@" .. tostring(mod.path) .. "/" .. relative)
    if not chunk then
      mod.log:error("%s did not compile: %s", relative, tostring(compileError))
      return nil
    end
    local ok, value = pcall(chunk)
    if not ok then
      mod.log:error("%s failed to run: %s", relative, tostring(value))
      return nil
    end
    return value
  end

  local Options = loadModule("options")
  if not Options then return end

  mod.options:define(Options.schema)
  local opt = Options.reader(mod)

  local Rows = loadModule("rows")
  local Skin = loadModule("skin")
  local Screen = loadModule("screen")
  local Menus = loadModule("menus")
  if not (Rows and Skin and Screen and Menus) then return end

  mod.exports.installed = Screen.install(mod, Rows, Skin, Options, opt)
  -- the START menu's row and the OPTION screen's CANCEL, both outside the
  -- manager and both gated on the same STYLE row
  Menus.install(mod, Skin, opt)

  -- For a neighbouring mod that wants the same list model: the sorting and
  -- filtering are pure, and nothing in them needs this screen.
  mod.exports.rows = Rows
end
