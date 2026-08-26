-- Loading a bundled mod's own Lua files, the sandbox-supported way.
--
-- A mod's `require` is scoped to engine modules and other mods' exports, so a
-- bundle cannot require its way into `modules/Gen1Sprint/src/sprint.lua`.  The
-- supported route is the one every mod in the index already uses for its own
-- files: read the source through the loader's filesystem, then `load` it into
-- this chunk's environment.  That works identically from a git checkout and
-- from an installed .zip.
--
-- Everything here is failure-tolerant on purpose.  A bundle hosts a dozen
-- independent features, and one of them being half-installed must degrade to
-- "that feature is off and said why" rather than taking the other eleven down
-- with it.

local Loader = {}

-- `mod` here is always the real engine mod object, never a facade: the paths
-- are bundle-root-relative and only the real object can resolve them.
function Loader.new(mod)
  local self = { mod = mod }

  -- Returns the chunk, or nil plus a reason already written to the log.
  -- `chunkName` is what shows up in a traceback, so it is worth spelling out
  -- in full -- a stack frame reading `modules/Gen1Dex/entry.lua:41` is the
  -- difference between a bug report and a shrug.
  function self.chunk(path)
    local source, readError = mod:read(path)
    if not source then
      local reason = ("cannot read %s (%s)"):format(path, tostring(readError))
      mod.log:error("%s -- reinstall the mod", reason)
      return nil, reason
    end
    local compiled, compileError = load(source, "@" .. tostring(mod.path) .. "/" .. path)
    if not compiled then
      local reason = ("%s did not compile: %s"):format(path, tostring(compileError))
      mod.log:error("%s", reason)
      return nil, reason
    end
    return compiled
  end

  -- Load and run a file, returning whatever it returned.  Extra arguments are
  -- passed to the chunk, which is how the upstream QOL feature files take
  -- their `local generation = ...` header.
  function self.run(path, ...)
    local compiled, reason = self.chunk(path)
    if not compiled then return nil, reason end
    local ok, value = pcall(compiled, ...)
    if not ok then
      local failure = ("%s failed to run: %s"):format(path, tostring(value))
      mod.log:error("%s", failure)
      return nil, failure
    end
    return value
  end

  return self
end

return Loader
