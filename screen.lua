return function(Breeder, View, services)
  local Screen = {}
  local Pokemon = require("src.core.game3.pokemon")
  local Daycare = require("src.core.game3.daycare")
  local Stack = require("src.ui.game3.stack")

  function Screen.show(session)
    if Screen.active and Screen.active.session == session then
      Stack.push("autobreeder", Screen.active, { fullscreen = true })
      return Screen.active
    end
    local screen = { session = session, target = Breeder.defaults(), parents = {}, sources = {}, pages = {},
      frameType = require("src.core.game3.options").ensure(session).frameType or 0 }
    Screen.active = screen
    local function page() return screen.pages[#screen.pages] end
    local function push(title, rows, kind)
      screen.pages[#screen.pages + 1] = { title = title, rows = rows or {}, cursor = 1, kind = kind }
    end
    local function back()
      if #screen.pages > 1 then table.remove(screen.pages)
      else Stack.pop("autobreeder") end
    end
    local function info(title, lines)
      local rows = {}
      for _, line in ipairs(lines) do rows[#rows + 1] = { label = line } end
      push(title, rows, "info")
    end
    local function confirm(title, action)
      push(title, { { label = "Go back", action = back }, { label = "Confirm", action = function() back(); action() end } })
    end
    local function choose(title, choices, action)
      local rows = {}
      for _, choice in ipairs(choices) do
        local value = choice.value
        rows[#rows + 1] = { label = choice.label, action = function() action(value); back() end }
      end
      push(title, rows)
    end
    local function monName(mon)
      return mon and Pokemon.name(mon.species) or "Choose..."
    end
    local function parentDetails(pair)
      local rows = {}
      for slot = 1, 2 do
        local mon = pair[slot]
        rows[#rows + 1] = "Parent " .. slot .. ": " .. monName(mon)
        if mon then
          rows[#rows + 1] = "IV " .. Breeder.spread(mon)
          rows[#rows + 1] = Pokemon.gender(mon.species, mon.personality) .. " / " .. Breeder.natures[Pokemon.natureId(mon.personality) + 1]
        end
      end
      info("PARENT DETAILS", rows)
    end
    local function improvedParents()
      local job = screen.job
      if job.status == "searching" then job.status = "paused" end
      local rows = { { label = "Inspect improved parents", action = function() parentDetails(job.parents) end } }
      for slot = 1, 2 do
        local parentSlot = slot
        rows[#rows + 1] = { label = function()
          local parent = job.parents[parentSlot]
          local state = not job.improvedParents[parentSlot] and "Original" or job.keptParents[parent] and "Kept" or "Keep"
          return "Parent " .. parentSlot .. ": " .. state .. " " .. monName(parent)
        end, help = Breeder.spread(job.parents[parentSlot]), action = function()
          confirm("KEEP IMPROVED PARENT " .. parentSlot .. "?", function()
            local ok, message = Breeder.keepParent(job, session, parentSlot, services.isActive)
            info(ok and "PARENT KEPT" or "CANNOT KEEP", View.wrap(message, 200))
          end)
        end }
      end
      push("IMPROVED PARENTS", rows)
    end
    local function selectParent(slot)
      local rows = {}
      local function add(mon, source, label)
        if not mon or Pokemon.isEgg(mon) then return end
        rows[#rows + 1] = { label = label .. " " .. monName(mon), help = Breeder.spread(mon), action = function()
          if screen.sources[3 - slot] == source then info("SAME PARENT", { "Choose a different Pokemon." }); return end
          screen.parents[slot], screen.sources[slot] = Breeder.copy(mon), source
          back()
        end }
      end
      for index, mon in ipairs(session.party or {}) do add(mon, "party" .. index, "Party " .. index) end
      local dc = Daycare.stateOf(session)
      for index = 1, 2 do add(Daycare.mon(dc, index), "daycare" .. index, "Day Care " .. index) end
      if #rows == 0 then rows[1] = { label = "No hatched parents available" } end
      push("PARENT " .. slot, rows)
    end
    local function parents()
      push("CHOOSE PARENTS", {
        { label = function() return "Parent 1: " .. monName(screen.parents[1]) end, action = function() selectParent(1) end },
        { label = function() return "Parent 2: " .. monName(screen.parents[2]) end, action = function() selectParent(2) end },
        { label = "Use both Day Care parents", action = function()
          local dc = Daycare.stateOf(session)
          if not Daycare.mon(dc, 1) or not Daycare.mon(dc, 2) then info("DAY CARE", { session.version == "emerald" and "Deposit two parents on Route 117." or "Deposit two parents at Four Island." }); return end
          screen.parents = { Breeder.copy(Daycare.mon(dc, 1)), Breeder.copy(Daycare.mon(dc, 2)) }
          screen.sources = { "daycare1", "daycare2" }
        end },
        { label = "Inspect selected parents", action = function() parentDetails(screen.parents) end },
        { label = "Original parents stay untouched", help = "Search breeds with copies of your parents." },
      })
    end
    local function repair()
      local rows = {}
      local function add(mon, label, present)
        if not mon or mon.metLevel ~= 0 or mon.pokeball ~= 4 then return end
        rows[#rows + 1] = { label = label .. " " .. monName(mon), help = "IV " .. Breeder.spread(mon), action = function()
          confirm("REPAIR ABILITY SLOT?", function()
            if not services.isActive(session) or not present() then
              info("CANNOT REPAIR", { "Pokemon or playthrough changed." }); return
            end
            local ok, message = Breeder.repairAbility(mon)
            info(ok and "ABILITY REPAIRED" or "CANNOT REPAIR", View.wrap(message, 200))
          end)
        end }
      end
      for index, mon in ipairs(session.party or {}) do
        add(mon, "Party " .. index, function() return session.party[index] == mon end)
      end
      local storage = require("src.core.game3.storage").ensure(session)
      for boxIndex, box in ipairs(storage.boxes) do
        for slot = 1, 30 do
          local mon = box.mons[slot]
          add(mon, "Box " .. boxIndex .. "/" .. slot, function() return box.mons[slot] == mon end)
        end
      end
      if #rows == 0 then rows[1] = { label = "No bred Pokemon in party or PC" } end
      push("REPAIR OLD RESULT", rows)
    end
    local function ivs()
      local rows = {
        { label = "Set all six IVs to 31", action = function() for _, key in ipairs(Breeder.keys) do screen.target.ivs[key] = true end end },
        { label = "Clear IV targets", action = function() screen.target.ivs = {} end },
      }
      for _, key in ipairs(Breeder.keys) do
        rows[#rows + 1] = { label = function() return key:upper() .. ": " .. (screen.target.ivs[key] and "31" or "Any") end,
          action = function() screen.target.ivs[key] = not screen.target.ivs[key] end }
      end
      push("PERFECT IV TARGETS", rows)
    end
    local function targets()
      local target = screen.target
      push("OFFSPRING TARGETS", {
        { label = "Perfect IVs...", help = "Choose six perfect IVs or individual stats.", action = ivs },
        { label = function() return "Shiny: " .. (target.shiny == nil and "Any" or target.shiny and "Yes" or "No") end,
          help = "Shininess is not inherited from parents.", action = function()
            choose("SHINY", { { label = "Any" }, { label = "Yes", value = true }, { label = "No", value = false } }, function(value) target.shiny = value end)
          end },
        { label = function() return "Nature: " .. (target.nature and Breeder.natures[target.nature + 1] or "Any") end, action = function()
          local choices = { { label = "Any" } }
          for index, name in ipairs(Breeder.natures) do choices[#choices + 1] = { label = name, value = index - 1 } end
          choose("NATURE", choices, function(value) target.nature = value end)
        end },
        { label = function() return "Gender: " .. (target.gender or "Any") end, action = function()
          choose("GENDER", { { label = "Any" }, { label = "Male", value = "M" }, { label = "Female", value = "F" }, { label = "Genderless", value = "U" } }, function(value) target.gender = value end)
        end },
        { label = function() return "Ability: " .. (target.ability and Pokemon.abilityName(target.ability) or "Any") end, action = function()
          if not screen.parents[1] or not screen.parents[2] then info("ABILITY", { "Choose parents first." }); return end
          local choices, seen = { { label = "Any" } }, {}
          for _, species in ipairs(Breeder.species(screen.parents)) do
            for _, ability in ipairs(Pokemon.abilities(species)) do
              if ability > 0 and not seen[ability] then
                choices[#choices + 1], seen[ability] = { label = Pokemon.abilityName(ability), value = ability }, true
              end
            end
          end
          choose("ABILITY", choices, function(value) target.ability = value end)
        end },
        { label = "All selected targets must match", help = "Changes apply to the next new search." },
      })
    end
    local function settings()
      push("SEARCH SETTINGS", {
        { label = function() return "Limit: " .. (screen.target.limit == 0 and "No limit" or tostring(screen.target.limit)) end, action = function()
          local choices = {}
          for _, value in ipairs({ 10000, 100000, 1000000, 10000000, 0 }) do
            choices[#choices + 1] = { label = value == 0 and "No limit (until stopped)" or tostring(value) .. " eggs", value = value }
          end
          choose("ATTEMPT LIMIT", choices, function(value) screen.target.limit = value end)
        end },
        { label = function() return "Improve parents: " .. (screen.target.replace and "On" or "Off") end,
          action = function() screen.target.replace = not screen.target.replace end },
        { label = "Eggs generated without walking", help = "Generation and hatch time are accelerated." },
        { label = "Closing this menu pauses search", help = "Reopen to resume during this play session." },
        { label = "Save kept results before quitting", help = "Unclaimed searches are not saved to disk." },
      })
    end
    local function progress()
      push("BREEDING SEARCH", {}, "progress")
    end
    local function result()
      local job = screen.job
      if not job or not job.result then info("RESULT", { "No matching egg found yet." }); return end
      push("MATCH FOUND", {}, "result")
    end
    local function start()
      local job, message = Breeder.start(session, screen.parents, screen.target)
      if not job then info("CANNOT START", View.wrap(message, 200)); return end
      screen.job = job
      progress()
    end
    local function current()
      local job = screen.job
      if not job then start(); return end
      if job.result then result(); return end
      if job.status == "paused" then job.status = "searching" end
      progress()
    end
    function screen.resultActions()
      local job = screen.job
      local function keep(hatch)
        if job.status == "claimed" then info("ALREADY KEPT", { "This result is already in your game.", "Save the game to keep it." }); return end
        confirm(hatch and "KEEP HATCHED POKEMON?" or "KEEP THIS EGG?", function()
          local ok, message = Breeder.keep(job, session, hatch, services.isActive)
          info(ok and "RESULT KEPT" or "CANNOT KEEP", View.wrap(message, 200))
        end)
      end
      push("KEEP RESULT", {
        { label = "Keep as egg", action = function() keep(false) end },
        { label = "Keep hatched (Lv.5)", action = function() keep(true) end },
        { label = "Inspect inherited moves", action = function()
          local rows = {}
          for _, move in ipairs(job.result.moves) do rows[#rows + 1] = Pokemon.moveName(move) end
          info("INHERITED MOVES", rows)
        end },
        { label = "Keep / inspect improved parents", action = improvedParents },
        { label = "Back to result", action = back },
      })
    end
    push("AUTO BREEDER", {
      { label = "Choose parents", action = parents },
      { label = "Offspring targets", action = targets },
      { label = "Search settings", action = settings },
      { label = function() return not screen.job and "Start breeding" or screen.job.result and "View result" or "Resume / view search" end, action = current },
      { label = "Start a new search", action = function()
        if screen.job then confirm("DISCARD SEARCH / RESULT?", start) else start() end
      end },
      { label = "Export / repair / help", action = function()
        push("EXPORT AND REPAIR", {
          { label = "Save + export for PKHeX", help = "Writes your game save and corrected GBA export.", action = function()
            confirm("SAVE GAME AND EXPORT?", function()
              if not services.isActive(session) then info("CANNOT EXPORT", { "The playthrough changed." }); return end
              local ok, path = services.exportSave(session)
              if not ok then info("EXPORT FAILED", View.wrap(path, 200)); return end
              services.log("Corrected GBA export: " .. path)
              local filename = path:match("[^/\\]+$") or path
              info("EXPORT WRITTEN", {
                "Use this .sav directly in PKHeX.",
                "Game folder: exports/" .. session.version,
                filename,
                "Full path is recorded in the mod log.",
                "Do not re-export from the launcher.",
                "That export loses this correction.",
              })
            end)
          end },
          { label = "Repair old result's ability slot", help = "Choose a bred Pokemon. Keeps PID and IVs.", action = repair },
          { label = "How breeding works", action = function()
        info("HOW IT WORKS", {
          "Uses the engine's real egg generator.", "Three IVs inherited; three are rolled.", "Copies of your parents improve.",
          "Their combined IV coverage is kept.", "Shiny parents give no shiny bonus.", "Shiny odds are about 1 in 8192.",
          "Nature / ability are not inherited.", "No Everstone or Destiny Knot bonus.", "Walking and hatching are skipped.",
          "Discarded eggs are not kept.", "Keep a match, then save your game.", "Unclaimed searches end on reload.",
        })
          end },
          { label = "Use this menu for GBA export", help = "Returning to the launcher removes the export correction." },
        })
      end },
    })
    function screen.handleInput(input)
      local job, currentPage = screen.job, page()
      if input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("l") then
        if job and job.status == "searching" then job.status = "paused" end
        back(); return
      end
      if currentPage.kind == "progress" then
        if input:wasPressed("select") then
          job.status = job.status == "searching" and "paused" or job.status
          confirm("STOP AND DISCARD SEARCH?", function() screen.job = nil; screen.pages = { screen.pages[1] } end)
        elseif input:wasPressed("a") then
          if job.status == "limit" then
            job.target.limit = job.target.limit + math.max(screen.target.limit, 1000000)
            job.status = "searching"
          elseif job.status == "paused" then job.status = "searching"
          elseif job.status == "searching" then job.status = "paused" end
        elseif input:wasPressed("r") then improvedParents() end
        return
      end
      if currentPage.kind == "result" then
        if input:wasPressed("a") then screen.resultActions() end
        return
      end
      local delta = input:wasPressed("up") and -1 or input:wasPressed("down") and 1 or input:wasPressed("left") and -5 or input:wasPressed("right") and 5 or 0
      if #currentPage.rows > 0 then
        currentPage.cursor = (currentPage.cursor - 1 + delta) % #currentPage.rows + 1
        if input:wasPressed("a") and currentPage.rows[currentPage.cursor].action then currentPage.rows[currentPage.cursor].action() end
      end
    end
    function screen.update()
      local job = screen.job
      if not job then return end
      if not services.isActive(session) then job.status = "paused"; Stack.pop("autobreeder"); return end
      if page().kind ~= "progress" then return end
      if job.status == "searching" then
        Breeder.step(job, 256, love.timer.getTime, 0.006)
        if job.status == "found" then back(); result()
        elseif job.status == "error" then services.log(job.message); info("SEARCH ERROR", { "Search stopped. Originals are safe.", "See the mod log for details." }) end
      end
    end
    function screen.draw() View.draw(screen, Breeder) end
    Stack.push("autobreeder", screen, { fullscreen = true })
    return screen
  end
  return Screen
end
