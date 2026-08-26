-- The editor.  A registered screen rather than mod.options rows, because
-- mod.options has define and get and no set (src/mods/Loader.lua:1211): its
-- rows are edited in the manager, by the player, and a mod cannot write them.
-- The four row types it does offer -- toggle, choice, number, text -- have no
-- reorder widget either.
--
-- One screen serves both menus.  opts.context names which: "start" carries
-- the pin catalog, "pc" does not, because a pin is a field action and the
-- overworld is not reachable from inside a PC.
--
-- Controls: Up/Down move, A grabs and drops a row, SELECT toggles a row
-- between shown and hidden (or a pin between on and off), B leaves.

return function(mod, Layout, Pins, contexts)
  local Font = mod.ui.Font
  local Theme = mod.ui.Theme

  local COLS, ROWS = 20, 18
  local FIRST_ROW, VISIBLE = 3, 12
  local LABEL_TILES = 12

  local Screen = {}
  Screen.__index = Screen

  -- 12 tiles of label, then the state column: the box is 20 wide and the
  -- cursor owns the first, so a longer label is cut rather than drawn over
  -- the right border.  Cut on a GLYPH boundary, not a byte one -- Font.split
  -- hands back a span per glyph with its byte range, and POKéDEX is seven
  -- glyphs across eight bytes, so a plain sub() can slice a character in half.
  local function truncate(text)
    local spans = Font.split(text)
    if #spans <= LABEL_TILES then return text end
    return text:sub(1, spans[LABEL_TILES].to)
  end

  -- A pin reaches the snapshot under the label the MENU gave it, which for a
  -- pin with a menuLabel is the short one (MAP).  The editor names every pin
  -- after the item or move it comes from instead, so the list does not rename
  -- a row underneath the cursor when SHORT NAMES is switched, and reads the
  -- same whether the pin is currently on the menu or waiting below it.
  -- Answers nil for anything that is not a pin -- engine rows keep the label
  -- the menu built them with, which is the only name they have.
  local function catalogName(game, key)
    if not Layout.isPin(key) then return nil end
    local entry = Pins.byId(Layout.pinId(key))
    if not entry then return nil end
    local ok, name = pcall(entry.label, mod, game)
    return ok and name or nil
  end

  -- Everything the player can arrange: the rows the last build of THIS menu
  -- actually produced, plus -- on the START menu only -- every pin in the
  -- catalog, marked unavailable when it is not owned yet.
  local function buildEntries(ctx, game)
    local layout = ctx.load()
    local protected = ctx.protected()
    local entries, seen = {}, {}

    for _, row in ipairs(ctx.snapshot or {}) do
      if not seen[row.key] then
        seen[row.key] = true
        entries[#entries + 1] = {
          key = row.key, label = catalogName(game, row.key) or row.label,
          kind = "row",
          on = not layout.hidden[row.key],
          locked = protected[row.key] or false,
        }
      end
    end

    if not ctx.pins then return entries end

    local pinEntries = {}
    for _, entry in ipairs(Pins.catalog) do
      local key = Layout.pinKey(entry.id)
      if not seen[key] then
        local ok, label = pcall(entry.label, mod, game)
        local owned = false
        local gotOwned, value = pcall(entry.owned, game)
        if gotOwned then owned = value and true or false end
        pinEntries[#pinEntries + 1] = {
          key = key, label = ok and label or entry.id, kind = "pin",
          on = layout.pins[key] and true or false, owned = owned,
        }
      end
    end

    -- Honour the saved order for pins too, so a pinned row sits in the editor
    -- where it sits in the menu.
    local rank = {}
    for i, key in ipairs(layout.order) do rank[key] = i end
    table.sort(pinEntries, function(a, b)
      local ra, rb = rank[a.key], rank[b.key]
      if ra and rb then return ra < rb end
      if ra then return true end
      if rb then return false end
      return a.label < b.label
    end)
    for _, entry in ipairs(pinEntries) do entries[#entries + 1] = entry end

    return entries
  end

  function Screen.new(game, opts)
    opts = opts or {}
    local self = setmetatable({}, Screen)
    self.isOpaque = true
    self.game = game
    self.ctx = contexts[opts.context or "start"] or contexts.start
    self.onCancel = opts.onCancel
    self.entries = buildEntries(self.ctx, game)
    self.index = 1
    self.scroll = 0
    self.grabbed = false
    return self
  end

  function Screen:clampScroll()
    if self.index - self.scroll > VISIBLE then
      self.scroll = self.index - VISIBLE
    elseif self.index - self.scroll < 1 then
      self.scroll = self.index - 1
    end
    if self.scroll < 0 then self.scroll = 0 end
  end

  function Screen:commit()
    local ctx = self.ctx
    local layout = ctx.load()
    local keys = {}
    for _, entry in ipairs(self.entries) do
      keys[#keys + 1] = entry.key
      if entry.kind == "pin" then
        layout.pins[entry.key] = entry.on or nil
        layout.hidden[entry.key] = nil
      else
        layout.hidden[entry.key] = (not entry.on) or nil
      end
    end
    Layout.reorder(layout, keys)
    ctx.save(layout)
  end

  function Screen:move(delta)
    local target = self.index + delta
    if target < 1 or target > #self.entries then return end
    if self.grabbed then
      local entries = self.entries
      entries[self.index], entries[target] = entries[target], entries[self.index]
      self:commit()
    end
    self.index = target
  end

  function Screen:update()
    local input = self.game.input
    if #self.entries == 0 then
      if input:wasPressed("b") or input:wasPressed("a") then self:leave() end
      return
    end
    if input:wasPressed("up") then
      self:move(-1)
    elseif input:wasPressed("down") then
      self:move(1)
    elseif input:wasPressed("a") then
      self.grabbed = not self.grabbed
    elseif input:wasPressed("select") then
      local entry = self.entries[self.index]
      -- A locked row is the only remaining route back to this screen;
      -- refusing the toggle is what makes "hide everything" recoverable.
      if entry and not entry.locked then
        entry.on = not entry.on
        self:commit()
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      if self.grabbed then
        self.grabbed = false
      else
        self:leave()
      end
    end
    self:clampScroll()
  end

  function Screen:leave()
    self:commit()
    self.game.stack:pop()
    -- The PC menu is still sitting underneath (its rows use keepOpen), so it
    -- is rebuilt in place rather than left showing the arrangement it had
    -- when the editor opened.
    if self.ctx.refresh then self.ctx.refresh() end
    if self.onCancel then self.onCancel() end
  end

  local function marker(entry)
    if entry.kind == "pin" then
      if not entry.owned then return "----" end
      return entry.on and " PIN" or "  --"
    end
    if entry.locked then return "LOCK" end
    return entry.on and "  ON" or " OFF"
  end

  function Screen:draw()
    Font.drawBox(0, 0, COLS, ROWS)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(self.ctx.title, 8, 8)

    if #self.entries == 0 then
      Font.draw("NOTHING TO ARRANGE", 16, FIRST_ROW * 8)
      Font.draw(self.ctx.emptyHint, 16, (FIRST_ROW + 2) * 8)
      love.graphics.setColor(1, 1, 1, 1)
      return
    end

    for row = 1, VISIBLE do
      local entry = self.entries[self.scroll + row]
      if not entry then break end
      local y = (FIRST_ROW + row - 1) * 8
      Font.draw(truncate(entry.label or entry.key), 2 * 8, y)
      Font.draw(marker(entry), 15 * 8, y)
    end

    local cursorY = (FIRST_ROW + (self.index - self.scroll) - 1) * 8
    Font.drawCode(self.grabbed and Theme.cursorHollow or Theme.cursor, 8, cursorY)
    if self.scroll + VISIBLE < #self.entries then
      Font.drawCode(Theme.moreArrow, (COLS - 2) * 8, (ROWS - 1) * 8)
    end

    Font.draw(self.grabbed and "A:DROP" or "A:MOVE", 8, (ROWS - 2) * 8)
    Font.draw("SEL:ON/OFF", 9 * 8, (ROWS - 2) * 8)
    love.graphics.setColor(1, 1, 1, 1)
  end

  return Screen
end
