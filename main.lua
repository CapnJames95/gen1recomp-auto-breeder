return function(mod)
  local function module(name)
    return assert(load(assert(mod:read(name .. ".lua")), "@autobreeder/" .. name .. ".lua"))()
  end
  local Runtime = require("src.core.game3.runtime")
  local Export = module("export")
  Export.install()
  local activeGame
  local Screen = module("screen")(module("breeder"), module("view"), {
    isActive = function(session) return Runtime.getSession() == session end,
    log = function(message) mod.log:info("%s", message) end,
    exportSave = function(session) return Export.save(session, activeGame) end,
  })
  local helpLease
  mod.hooks:wrap("input.step", function(next, game, dt)
    local Stack = require("src.ui.game3.stack")
    local Help = require("src.ui.game3.help_system")
    local top = Stack.top()
    if Screen.active and top and top.mod == Screen.active then
      if not helpLease then helpLease = { previous = Help.contextOverride } end
      Help.setContext(0)
      if game.input and game.input.setButtonAlias then game.input:setButtonAlias("l", nil) end
    elseif helpLease then
      if Help.contextOverride == 0 then Help.setContext(helpLease.previous) end
      helpLease = nil
    end
    return next(game, dt)
  end)
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local result = next(game, items)
    if type(result) ~= "table" then return result end
    local session = Runtime.getSession()
    if not session or (session.version ~= "firered" and session.version ~= "leafgreen" and session.version ~= "emerald") then return result end
    for _, row in ipairs(result) do if row.id == "autobreeder" then return result end end
    local position = #result + 1
    for index, row in ipairs(result) do if row.id == "save" then position = index; break end end
    table.insert(result, position, { id = "autobreeder", label = "AUTO BREEDER", onSelect = function()
      if Runtime.getSession() == session then activeGame = game; Screen.show(session) end
    end })
    return result
  end)
end
