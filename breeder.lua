local Breeder = {}
local Pokemon = require("src.core.game3.pokemon")
local Breeding = require("src.core.game3.breeding")
local Daycare = require("src.core.game3.daycare")
local Rng = require("src.core.game3.rng")
local Storage = require("src.core.game3.storage")

Breeder.keys = { "hp", "atk", "def", "spe", "spa", "spd" }
Breeder.natures = { "Hardy", "Lonely", "Brave", "Adamant", "Naughty", "Bold", "Docile", "Relaxed", "Impish", "Lax", "Timid", "Hasty", "Serious", "Jolly", "Naive", "Modest", "Mild", "Quiet", "Bashful", "Rash", "Calm", "Gentle", "Sassy", "Careful", "Quirky" }

function Breeder.copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, entry in pairs(value) do result[key] = Breeder.copy(entry) end
  return result
end

function Breeder.defaults()
  return { ivs = { hp = true, atk = true, def = true, spe = true, spa = true, spd = true }, limit = 1000000, replace = true }
end

function Breeder.perfect(mon)
  local count = 0
  for _, key in ipairs(Breeder.keys) do
    if mon.ivs and mon.ivs[key] == 31 then count = count + 1 end
  end
  return count
end

function Breeder.spread(mon)
  local values = {}
  for _, key in ipairs(Breeder.keys) do values[#values + 1] = tostring(mon.ivs[key]) end
  return table.concat(values, "/")
end

function Breeder.abilitySlot(mon)
  local abilities = Pokemon.abilities(mon.species)
  return (abilities[2] or 0) ~= 0 and mon.personality % 2 or 0
end

function Breeder.repairAbility(mon)
  if not mon or mon.metLevel ~= 0 or mon.pokeball ~= 4 or not mon.personality or not Pokemon.speciesMeta(mon.species) then
    return false, "Only bred Pokemon can use this repair."
  end
  mon.abilityNum = Breeder.abilitySlot(mon)
  mon.ability = Pokemon.abilityId(mon.species, mon.personality)
  mon.abilityId = mon.ability
  mon.autoBreederOrigin = 2
  return true, "Ability slot repaired. Save the game, then export again. PID and IVs are unchanged."
end

function Breeder.species(pair)
  local result, seen = {}, {}
  for _, low in ipairs({ 1, 32768 }) do
    local dc = { pair[1], pair[2], offspringPersonality = low }
    local species = Breeding.alterEggSpeciesWithIncenseItem(Breeding.parentSlots(dc), dc)
    if not seen[species] then result[#result + 1], seen[species] = species, true end
  end
  table.sort(result)
  return result
end

function Breeder.score(pair, targets, version)
  local coverage, both, factors = 0, 0, {}
  for index, key in ipairs(Breeder.keys) do
    local perfect = (pair[1].ivs[key] == 31 and 1 or 0) + (pair[2].ivs[key] == 31 and 1 or 0)
    if perfect > 0 then coverage = coverage + 1 end
    if perfect == 2 then both = both + 1 end
    factors[index] = targets[key] and perfect / 2 or 1
  end
  -- Enumerate the native three selections. Emerald removes list positions,
  -- rather than the selected values, so a stat can be inherited repeatedly.
  local probability = 0
  local function visit(available, inherited, depth, weight)
    if depth == 4 then
      local chance = weight
      for index, key in ipairs(Breeder.keys) do
        if targets[key] then chance = chance * (inherited[index] and factors[index] or 1 / 32) end
      end
      probability = probability + chance
      return
    end
    local rs=version=='ruby' or version=='sapphire'
    local count=rs and (7-depth) or #available
    for pick=1,count do
      local stat=available[pick]
      local nextAvailable, nextInherited = Breeder.copy(available), Breeder.copy(inherited)
      if rs then
        -- Native RS invalidates the slot indexed by the selected STAT and
        -- compacts the full six-slot buffer, retaining its old tail.
        nextAvailable[stat]=255
        local temp=Breeder.copy(nextAvailable);local j=1
        for k=1,6 do if temp[k]~=255 then nextAvailable[j]=temp[k];j=j+1 end end
      else table.remove(nextAvailable, version == "emerald" and depth or pick) end
      nextInherited[stat] = true
      visit(nextAvailable, nextInherited, depth + 1, weight / count)
    end
  end
  visit({1, 2, 3, 4, 5, 6}, {}, 1, 1)
  return { coverage = coverage, both = both, probability = probability, compatibility = Breeding.compatibility(pair) }
end

function Breeder.better(candidate, previous)
  if candidate.coverage < previous.coverage or candidate.probability < previous.probability - 1e-18 then return false end
  if candidate.probability > previous.probability + 1e-18 then return true end
  if candidate.coverage ~= previous.coverage then return candidate.coverage > previous.coverage end
  if candidate.both ~= previous.both then return candidate.both > previous.both end
  return candidate.compatibility > previous.compatibility
end

function Breeder.validate(pair, target)
  for slot = 1, 2 do
    local mon = pair[slot]
    if not mon then return false, "Choose two parents first." end
    if Pokemon.isEgg(mon) then return false, "Eggs cannot be parents." end
    for _, key in ipairs(Breeder.keys) do
      local value = mon.ivs and mon.ivs[key]
      if type(value) ~= "number" or value < 0 or value > 31 or value % 1 ~= 0 then return false, "Parent IV data is unavailable." end
    end
  end
  if Breeding.compatibility(pair) == 0 then return false, "These parents cannot breed." end
  if target.nature ~= nil and (type(target.nature) ~= "number" or target.nature < 0 or target.nature > 24 or target.nature % 1 ~= 0) then return false, "Invalid nature." end
  if type(target.limit) ~= "number" or target.limit < 0 or target.limit % 1 ~= 0 then return false, "Invalid attempt limit." end
  local possible = false
  for _, species in ipairs(Breeder.species(pair)) do
    for low = 0, 255 do
      if (not target.gender or Pokemon.gender(species, low) == target.gender)
        and (not target.ability or Pokemon.abilityId(species, low) == target.ability) then possible = true; break end
    end
  end
  if not possible then return false, "Gender / ability combination is impossible." end
  return true
end

function Breeder.start(session, pair, target)
  if session.version ~= "firered" and session.version ~= "leafgreen" and session.version ~= "emerald" and session.version ~= "ruby" and session.version ~= "sapphire" then return nil, "A supported Gen 3 game is required." end
  local ok, message = Breeder.validate(pair, target)
  if not ok then return nil, message end
  local scratch = { version = session.version, party = {}, map = session.map, name = session.name,
    playerName = session.playerName, trainerId = session.trainerId or session.id or session.playerId,
    secretId = session.secretId, gender = session.gender, playerGender = session.playerGender,
    dex = { seen = {}, owned = {}, caught = {} } }
  local parents = Breeder.copy(pair)
  Rng.Random()
  return { status = "searching", session = session, scratch = scratch, parents = parents,
    original = Breeder.copy(pair), target = Breeder.copy(target), rng = Rng.getState(), attempts = 0,
    replacements = 0, shinyCount = 0, elapsed = 0, score = Breeder.score(parents, target.ivs, session.version),
    species = table.concat(Breeder.species(parents), ","), history = {}, improvedParents = {}, keptParents = {} }
end

function Breeder.matches(mon, target)
  for key, selected in pairs(target.ivs) do
    if selected and mon.ivs[key] ~= 31 then return false end
  end
  return (target.shiny == nil or Pokemon.isShiny(mon) == target.shiny)
    and (target.nature == nil or Pokemon.natureId(mon.personality) == target.nature)
    and (target.gender == nil or Pokemon.gender(mon.species, mon.personality) == target.gender)
    and (target.ability == nil or Pokemon.abilityId(mon.species, mon.personality) == target.ability)
end

function Breeder.generate(job)
  local dc = { job.parents[1], job.parents[2] }
  local policy=require("src.core.game3.profile").forSession(job.scratch).daycare
  if policy and policy.pendingPersonality then
    dc.offspringPersonality=policy.pendingPersonality(job.scratch,dc)
  elseif job.scratch.version == "emerald" then
    dc.offspringPersonality = Breeding.rsePersonality(job.scratch, dc)
  else
    dc.offspringPersonality = (Rng.Random() % 0xFFFE) + 1
  end
  local species, mother, father = Breeding.parentSlots(dc)
  species = Breeding.alterEggSpeciesWithIncenseItem(species, dc)
  local egg = assert(Breeding.setInitialEggData(job.scratch, species, dc), "Engine could not generate an egg.")
  Breeding.inheritIVs(egg, dc, job.scratch)
  Breeding.buildEggMoveset(egg, dc[father], dc[mother])
  if job.scratch.version == "emerald" then
    if Pokemon.national(species) == 172 then Breeding.giveVoltTackleIfLightBall(job.scratch, egg, dc) end
  end
  if Breeding.isRse(job.scratch) then
    egg.metLocation = 0 -- Unhatched RSE eggs use the RSE egg location.
  else
    egg.metLocation = 146
  end
  egg.abilityNum = Breeder.abilitySlot(egg)
  egg.autoBreederOrigin = 2
  Pokemon.applyStats(egg)
  return egg
end

function Breeder.consider(job, egg)
  local best, bestSlot = job.score, nil
  local candidate
  for slot = 1, 2 do
    if job.parents[slot].species ~= 132 then
      local pair = { job.parents[1], job.parents[2] }
      pair[slot] = egg
      local score = Breeder.score(pair, job.target.ivs, job.session.version)
      if score.compatibility > 0 and Breeder.better(score, best)
        and table.concat(Breeder.species(pair), ",") == job.species then
        best, bestSlot = score, slot
      end
    end
  end
  if bestSlot then
    candidate = Breeder.copy(egg)
    Breeding.hatchMon(job.scratch, candidate)
    job.parents[bestSlot], job.score = candidate, best
    job.improvedParents[bestSlot] = true
    job.replacements = job.replacements + 1
    job.history[#job.history + 1] = { attempt = job.attempts, slot = bestSlot, ivs = Breeder.copy(candidate.ivs), probability = best.probability }
    if #job.history > 32 then table.remove(job.history, 1) end
  end
end

function Breeder.step(job, count, clock, budget)
  if job.status ~= "searching" then return end
  local previous = Rng.getState()
  local started = clock and clock() or 0
  Rng.setState(job.rng)
  local ok, failure = pcall(function()
    for attempt = 1, count or 128 do
      if job.target.limit > 0 and job.attempts >= job.target.limit then job.status = "limit"; break end
      local egg = Breeder.generate(job)
      job.attempts = job.attempts + 1
      if Pokemon.isShiny(egg) then job.shinyCount = job.shinyCount + 1 end
      if not job.best or Breeder.perfect(egg) > Breeder.perfect(job.best) then job.best = Breeder.copy(egg) end
      if Breeder.matches(egg, job.target) then job.result, job.status = egg, "found"; break end
      if job.target.replace then Breeder.consider(job, egg) end
      if clock and clock() - started >= (budget or 0.006) then break end
    end
    if job.status == "searching" and job.target.limit > 0 and job.attempts >= job.target.limit then job.status = "limit" end
  end)
  job.rng = Rng.getState()
  Rng.setState(previous)
  if clock then job.elapsed = job.elapsed + clock() - started end
  if not ok then job.status, job.message = "error", tostring(failure) end
end

function Breeder.keepParent(job, session, slot, isActive)
  if session and (session.version=='ruby' or session.version=='sapphire') and tostring(require('src.core.game3.map').current or session.map):find('BATTLE_TOWER',1,true) then return false,'Leave the Battle Tower before receiving Pokemon.' end
  if session and session.version=="emerald" and session.frontier and (session.frontier.challengeStatus or 0)~=0 then return false,"Finish the Battle Frontier challenge before receiving Pokemon." end
  if session ~= job.session or (isActive and not isActive(session)) then return false, "The playthrough has changed." end
  local parent = job.parents[slot]
  if not parent or not job.improvedParents[slot] then return false, "This parent has not been improved. Original parents are not copied." end
  if job.keptParents[parent] then return false, "This improved parent is already kept." end
  local mon = Breeder.copy(parent)
  local party = session.party or {}
  local destination = "party"
  if #party < 6 then
    session.party = party
    party[#party + 1] = mon
  else
    local sent, box = Storage.sendMonToPC(session, mon)
    if not sent then return false, "Party and PC are full. Free a slot, then retry." end
    destination = "PC box " .. tostring(box)
  end
  job.keptParents[parent] = true
  return true, "Improved parent sent to " .. destination .. ". Save your game."
end

function Breeder.keep(job, session, hatch, isActive)
  if session and (session.version=='ruby' or session.version=='sapphire') and tostring(require('src.core.game3.map').current or session.map):find('BATTLE_TOWER',1,true) then return false,'Leave the Battle Tower before receiving Pokemon.' end
  if session and session.version=="emerald" and session.frontier and (session.frontier.challengeStatus or 0)~=0 then return false,"Finish the Battle Frontier challenge before receiving Pokemon." end
  if session ~= job.session or (isActive and not isActive(session)) then return false, "The playthrough has changed." end
  if job.status ~= "found" or not job.result then return false, "No unclaimed match." end
  if not Breeder.matches(job.result, job.target) then return false, "Result no longer matches the target." end
  local mon = Breeder.copy(job.result)
  local party = session.party or {}
  local destination
  if #party < 6 then
    destination = "party"
  else
    local sent, box = Storage.sendMonToPC(session, mon)
    if not sent then return false, "Party and PC are full. Free a slot, then retry." end
    destination = "PC box " .. tostring(box)
  end
  if hatch then Breeding.hatchMon(session, mon) end
  if destination == "party" then session.party = party; party[#party + 1] = mon end
  job.status = "claimed"
  return true, (hatch and "Hatched Pokemon" or "Egg") .. " sent to " .. destination .. ". Save your game."
end

return Breeder
