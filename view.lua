-- RS native small-font atlases do not render reliably in these compact mod menus.
-- Keep measurement and drawing on the same readable native face.
local function collectionFont()
 local v=require('src.core.GameVersion').get()
 return (v=='ruby' or v=='sapphire') and 'normal' or nil
end
local View = {}
local Window = require("src.ui.game3.window")
local Font = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")

local function text(value, left, top, width, small, colors)
  value = tostring(value or "")
  if Font.measure(value, {small=collectionFont()==nil and small }) > width then
    while #value > 0 and Font.measure(value .. "...", {small=collectionFont()==nil and small }) > width do value = value:sub(1, -2) end
    value = value .. "..."
  end
  Window.printPx(value, left, top, { maxWidth = width,small=collectionFont()==nil and small, colors = colors })
end

function View.wrap(value, width)
  local rows, line = {}, ""
  for word in tostring(value):gmatch("%S+") do
    local trial = line == "" and word or line .. " " .. word
    if Font.measure(trial, {small=collectionFont()==nil and true }) > width and line ~= "" then rows[#rows + 1], line = line, word
    else line = trial end
  end
  if line ~= "" then rows[#rows + 1] = line end
  return rows
end

function View.draw(screen, Breeder)
  local page = screen.pages[#screen.pages]
  local job = screen.job
  local function frame(left, top, width, height)
    Window.userFrame(Window.template(left, top, width, height), screen.frameType)
  end
  love.graphics.setColor(0.78, 0.88, 0.9, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 160)
  love.graphics.setColor(0.73, 0.84, 0.87, 1)
  for offset = 18, 135, 4 do love.graphics.rectangle("fill", 0, offset, 240, 1) end
  love.graphics.setColor(0, 123 / 255, 197 / 255, 1)
  love.graphics.rectangle("fill", 0, 0, 240, 16)
  love.graphics.setColor(1, 1, 1, 1)
  text(page.title, 8, 0, 190, false, Font.COLOR.WHITE)
  text(#page.rows > 6 and (page.cursor .. "/" .. #page.rows) or screen.session.version == "ruby" and "RU" or screen.session.version == "sapphire" and "SA" or screen.session.version == "emerald" and "EM" or screen.session.version == "leafgreen" and "LG" or "FR", 202, 0, 31, true, Font.COLOR.WHITE)
  local help = "A: choose  B/L: back  Left/Right: page"
  if page.kind == "progress" then
    frame(1, 3, 28, 13)
    local statuses = { searching = "Breeding...", paused = "Paused", limit = "Attempt limit reached", error = "Search stopped" }
    text(statuses[job.status] or job.status, 16, 27, 208)
    text("Eggs tried: " .. job.attempts, 16, 44, 208)
    text("Parent upgrades: " .. job.replacements .. "   Coverage: " .. job.score.coverage .. "/6", 16, 62, 208, true)
    text("Shinies seen: " .. job.shinyCount .. "   Best: " .. (job.best and Breeder.perfect(job.best) or 0) .. "/6", 16, 77, 208, true)
    local odds = job.score.probability > 0 and string.format("1 in %.0f", 1 / job.score.probability) or "No chance yet"
    text("Est. IVs only: " .. odds, 16, 92, 208, true)
    text(job.target.limit == 0 and "No limit. R: inspect parents" or "Limit: " .. job.target.limit .. "   R: parents", 16, 108, 208, true)
    help = job.status == "limit" and "A: extend limit  B: back  SELECT: stop" or "A: pause/resume  B: back  SELECT: stop"
  elseif page.kind == "result" then
    local mon = job.result
    local shiny = Pokemon.isShiny(mon)
    frame(1, 3, 10, 13)
    frame(13, 3, 16, 13)
    local pic = Pokemon.frontPic(mon.species, 0, shiny)
    if pic and pic.image then love.graphics.draw(pic.image, 16, 31) end
    text(Pokemon.name(mon.species), 12, 99, 74, true)
    text(shiny and "SHINY / Lv.5" or "Lv.5 hatchling", 12, 112, 74, true)
    text(Breeder.natures[Pokemon.natureId(mon.personality) + 1] .. " / " .. Pokemon.gender(mon.species, mon.personality), 111, 27, 116, true)
    text(Pokemon.abilityName(mon.ability), 111, 42, 116, true)
    text("HP " .. mon.ivs.hp .. "  ATK " .. mon.ivs.atk, 111, 59, 116, true)
    text("DEF " .. mon.ivs.def .. "  SPE " .. mon.ivs.spe, 111, 74, 116, true)
    text("SPA " .. mon.ivs.spa .. "  SPD " .. mon.ivs.spd, 111, 89, 116, true)
    text("Eggs: " .. job.attempts, 111, 107, 116, true)
    help = job.status == "claimed" and "Result kept. Save your game. B: back" or "A: keep / inspect result  B: back"
  else
    frame(1, 3, 28, 13)
    local first = math.max(1, math.min(page.cursor - 5, #page.rows - 5))
    for index = first, math.min(#page.rows, first + 5) do
      local row, top = page.rows[index], 28 + (index - first) * 16
      if index == page.cursor then
        love.graphics.setColor(0.82, 0.91, 0.96, 1)
        love.graphics.rectangle("fill", 9, top, 222, 16)
        love.graphics.setColor(1, 1, 1, 1)
        Window.cursorPx(10, top)
      end
      text(type(row.label) == "function" and row.label() or row.label, 19, top, 208, true)
    end
    local selected = page.rows[page.cursor]
    help = selected and selected.help or help
  end
  frame(1, 17, 28, 2)
  text(help, 12, 136, 216, true)
end

return View
