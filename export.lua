local Export = {}

function Export.save(session, game)
  local Runtime = require("src.core.game3.runtime")
  if not session or Runtime.getSession() ~= session or not game or game.session ~= session then
    return false, "The active playthrough has changed."
  end
  if not game.saveGame or not game.saveOffered or not game:saveOffered() then
    return false, "Saving is not available here. Return to normal gameplay first."
  end
  Export.install()
  local saved, result = pcall(game.saveGame, game)
  if not saved or result ~= true then return false, "Game save failed. No export was written." end
  local ok, exported, path = pcall(require("src.import.SaveFileIO").exportActiveSlot, session.version)
  if not ok then return false, "Export failed: " .. tostring(exported) end
  if not exported then return false, tostring(path) end
  return true, path
end

local function installCodec(Codec, Layout)
  if Codec._autoBreederExportVersion == 2 then return end
  local originalFromPort = Codec.fromPortMon
  local originalEncode = Codec.encodeBoxMon
  Codec.fromPortMon = function(mon, ...)
    local result = originalFromPort(mon, ...)
    if mon and mon.autoBreederOrigin == 2 then result._autoBreederOrigin = 2 end
    return result
  end
  Codec.encodeBoxMon = function(mon, ...)
    local result = originalEncode(mon, ...)
    if mon and mon._autoBreederOrigin == 2 then
      local offset, length = Layout.BOX_MON.otName, Layout.BOX_MON.otNameLength
      local name = Codec.encodeString(mon.otName, length, 255)
      result = result:sub(1, offset) .. name .. result:sub(offset + length + 1)
    end
    return result
  end
  Codec._autoBreederExportVersion = 2
end

function Export.install()
  local Codec = require("src.save_convert.Gen3Save")
  local Layout = require("src.save_convert.Gen3Layout")
  installCodec(Codec, Layout)
  local version=require("src.core.GameVersion").get()
  if (version=="emerald" or version=="ruby" or version=="sapphire") and Codec.forVersion then
    installCodec(Codec.forVersion(version), Layout)
  end
end
return Export
