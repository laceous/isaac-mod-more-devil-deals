local mod = RegisterMod('More Devil Deals', 1)
local json = require('json')
local game = Game()

mod.onGameStartHasRun = false

mod.state = {}
mod.state.devilRoomSpawned = nil -- 3 state: nil, false, true; likely edge case w/ glowing hourglass going back a floor
mod.state.lastDevilRoomStage = LevelStage.STAGE_NULL -- ascent, room:GetLastDevilRoomStage doesn't work
mod.state.enableBasementI = true
mod.state.enablePreAscent = false
mod.state.enableAscent = false
mod.state.enableCorpseII = true
mod.state.enableBlueWomb = true
mod.state.enableSheol = true    -- cathedral
mod.state.enableDarkRoom = true -- chest
mod.state.enableTheVoid = true
mod.state.enableHome = true

function mod:onGameStart(isContinue)
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if isContinue then
        if type(state.devilRoomSpawned) == 'boolean' then
          mod.state.devilRoomSpawned = state.devilRoomSpawned
        end
        if math.type(state.lastDevilRoomStage) == 'integer' and state.lastDevilRoomStage >= LevelStage.STAGE_NULL and state.lastDevilRoomStage < LevelStage.NUM_STAGES then
          mod.state.lastDevilRoomStage = state.lastDevilRoomStage
        end
      end
      for _, v in ipairs({ 'enableBasementI', 'enablePreAscent', 'enableAscent', 'enableCorpseII', 'enableBlueWomb', 'enableSheol', 'enableDarkRoom', 'enableTheVoid', 'enableHome' }) do
        if type(state[v]) == 'boolean' then
          mod.state[v] = state[v]
        end
      end
    end
  end
  
  mod.onGameStartHasRun = true
  mod:onNewRoom()
end

function mod:onGameExit(shouldSave)
  if shouldSave then
    mod:save()
    mod.state.devilRoomSpawned = nil
    mod.state.lastDevilRoomStage = LevelStage.STAGE_NULL
  else
    mod.state.lastDevilRoomStage = LevelStage.STAGE_NULL
    mod.state.devilRoomSpawned = nil
    mod:save()
  end
  
  mod.onGameStartHasRun = false
end

function mod:save(settingsOnly)
  if settingsOnly then
    local _, state
    if mod:HasData() then
      _, state = pcall(json.decode, mod:LoadData())
    end
    if type(state) ~= 'table' then
      state = {}
    end
    
    state.enableBasementI = mod.state.enableBasementI
    state.enablePreAscent = mod.state.enablePreAscent
    state.enableAscent = mod.state.enableAscent
    state.enableCorpseII = mod.state.enableCorpseII
    state.enableBlueWomb = mod.state.enableBlueWomb
    state.enableSheol = mod.state.enableSheol
    state.enableDarkRoom = mod.state.enableDarkRoom
    state.enableTheVoid = mod.state.enableTheVoid
    state.enableHome = mod.state.enableHome
    
    mod:SaveData(json.encode(state))
  else
    mod:SaveData(json.encode(mod.state))
  end
end

-- onNewLevel runs after onNewRoom, but we don't do anything in onNewRoom in the first room of the floor, so this is ok
function mod:onNewLevel()
  if not game:IsGreedMode() then
    mod.state.devilRoomSpawned = nil
    
    if mod:isPreAscent(false) or mod:isAscent(false) then
      if mod.state.lastDevilRoomStage > LevelStage.STAGE_NULL then
        local level = game:GetLevel()
        local stage = level:GetStage()
        if mod:isRepentanceStageType() then
          stage = stage + 1
        end
        
        -- edge case: STAGE_NULL (0) always gives 100%
        -- positive and negative numbers work as expected
        local diff = math.abs(mod.state.lastDevilRoomStage - stage)
        local lastDevilRoomStage = stage - diff
        if lastDevilRoomStage == LevelStage.STAGE_NULL and diff < 3 then -- 33, 67, 100
          lastDevilRoomStage = lastDevilRoomStage + 1
        end
        
        -- otherwise we get 100% on every floor in the ascent which feels cheap
        game:SetLastDevilRoomStage(lastDevilRoomStage)
      end
    else
      mod.state.lastDevilRoomStage = LevelStage.STAGE_NULL
    end
  end
end

function mod:onNewRoom()
  if not mod.onGameStartHasRun then
    return
  end
  
  if not game:IsGreedMode() then
    local room = game:GetRoom()
    
    if room:IsClear() then
      if mod:isBasementI(true) or
         mod:isPreAscent(true) or
         mod:isAscent(true) or
         mod:isCorpseII(true) or
         mod:isSheolOrCathedral(true) or
         mod:isDarkRoomOrChest(true) or
         mod:isTheVoid(true) or
         mod:isHome(true)
      then
        mod:spawnDevilRoomDoor()
      elseif mod:isBlueWomb(true) and mod.state.enableBlueWomb then
        mod:spawnDevilRoomDoorBlueWomb()
      end
    end
  end
end

-- potential issue: other mods can cause this callback to be skipped by returning true
-- an alt implementation would involve hooking into MC_POST_UPDATE and constantly checking which is inefficient
function mod:onPreSpawnAward()
  if not game:IsGreedMode() then
    if mod:isBasementI(true) or
       mod:isCorpseII(true) or
       mod:isSheolOrCathedral(true) or
       mod:isDarkRoomOrChest(true) or
       mod:isTheVoid(true)
    then
      mod:spawnDevilRoomDoor()
    end
  end
end

function mod:spawnDevilRoomDoor()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local rng = level:GetDevilAngelRoomRNG()
  local stage = level:GetStage()
  local animate = mod.state.devilRoomSpawned == nil
  local chance = mod:getDevilRoomChance()
  
  -- room:GetDevilRoomChance doesn't zero out on our custom floors, use a boolean to keep track of that
  if chance > 0.0 then
    if rng:RandomFloat() < chance then
      if room:TrySpawnDevilRoomDoor(animate, true) then
        if mod:isPreAscent(false) or mod:isAscent(false) then
          mod.state.lastDevilRoomStage = mod:isRepentanceStageType() and stage + 1 or stage
        end
        
        mod.state.devilRoomSpawned = true
        return
      end
    end
  end
  
  mod.state.devilRoomSpawned = false
end

function mod:spawnDevilRoomDoorBlueWomb()
  local room = game:GetRoom()
  local player = game:GetPlayer(0)
  local hasDuality = mod:hasCollectible(CollectibleType.COLLECTIBLE_DUALITY)
  
  if not hasDuality then
    player:AddCollectible(CollectibleType.COLLECTIBLE_DUALITY, 0, false, nil, 0)
  end
  
  room:TrySpawnDevilRoomDoor(false, true)
  
  if not hasDuality then
    player:RemoveCollectible(CollectibleType.COLLECTIBLE_DUALITY, false, nil, true)
  end
  
  -- the wrong door sprites load in this room
  local doors = mod:getDevilRoomDoors()
  mod:updateDoorSprites(doors)
end

function mod:getDevilRoomDoors()
  local room = game:GetRoom()
  local doors = {}
  
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(i)
    
    if door and door.TargetRoomIndex == GridRooms.ROOM_DEVIL_IDX then
      table.insert(doors, door)
    end
  end
  
  return doors
end

function mod:updateDoorSprites(doors)
  for _, door in ipairs(doors) do
    local sprite = door:GetSprite()
    
    if door.TargetRoomType == RoomType.ROOM_DEVIL then
      sprite:Load('gfx/grid/door_07_devilroomdoor.anm2', true)
      sprite:Play('Opened', true)
    elseif door.TargetRoomType == RoomType.ROOM_ANGEL then
      sprite:Load('gfx/grid/door_07_holyroomdoor.anm2', true)
      sprite:Play('Opened', true)
    end
  end
end

function mod:hasCollectible(collectible)
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    
    if player:HasCollectible(collectible, false) then
      return true
    end
  end
  
  return false
end

function mod:hasTv()
  return #Isaac.FindByType(EntityType.ENTITY_GENERIC_PROP, 4, -1, false, false) > 0
end

function mod:getDevilRoomChance()
  local room = game:GetRoom()
  local chance = room:GetDevilRoomChance()
  
  if not game:IsGreedMode() then
    if (mod.state.devilRoomSpawned == false and chance < 1.0) or -- goat head / eucharist
       (not mod.state.enableBasementI and mod:isBasementI(false)) or
       (not mod.state.enablePreAscent and mod:isPreAscent(false)) or
       (not mod.state.enableAscent and mod:isAscent(false)) or
       (not mod.state.enableCorpseII and mod:isCorpseII(false)) or
       (not mod.state.enableBlueWomb and mod:isBlueWomb(false)) or
       (not mod.state.enableSheol and mod:isSheolOrCathedral(false)) or
       (not mod.state.enableDarkRoom and mod:isDarkRoomOrChest(false)) or
       (not mod.state.enableTheVoid and mod:isTheVoid(false)) or
       (not mod.state.enableHome and mod:isHome(false))
    then
      chance = 0.0
    elseif mod.state.enableBlueWomb and mod:isBlueWomb(false) then
      chance = 1.0
    end
  end
  
  return chance
end

function mod:getCurrentDimension()
  local level = game:GetLevel()
  return mod:getDimension(level:GetCurrentRoomDesc())
end

function mod:getDimension(roomDesc)
  local level = game:GetLevel()
  local ptrHash = GetPtrHash(roomDesc)
  
  -- 0: main dimension
  -- 1: secondary dimension, used by downpour mirror dimension and mines escape sequence
  -- 2: death certificate dimension
  for i = 0, 2 do
    if ptrHash == GetPtrHash(level:GetRoomByIdx(roomDesc.SafeGridIndex, i)) then
      return i
    end
  end
  
  return -1
end

-- basement/cellar/burning basement i (not xl, not ascent)
function mod:isBasementI(checkRoom)
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage() -- might want to parse StageAPI.CurrentStage.LevelgenStage
  
  local levelCheck = stage == LevelStage.STAGE1_1 and
                     not mod:isCurseOfTheLabyrinth() and
                     not mod:isRepentanceStageType() and
                     not game:GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH)
  
  if checkRoom then
    return levelCheck and
           room:IsCurrentRoomLastBoss()
  end
  
  return levelCheck
end

-- dad's note
function mod:isPreAscent(checkRoom)
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  
  local levelCheck = (stage == LevelStage.STAGE3_2 or (mod:isCurseOfTheLabyrinth() and stage == LevelStage.STAGE3_1)) and
                     mod:isRepentanceStageType() and
                     game:GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH_INIT) and
                     not game:GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH)
  
  if checkRoom then
    return levelCheck and
           room:IsCurrentRoomLastBoss()
  end
  
  return levelCheck
end

-- starts in boss room, ends in starting room
-- layout or red rooms can block devil doors here
function mod:isAscent(checkRoom)
  local level = game:GetLevel()
  local stage = level:GetStage()
  
  local levelCheck = stage >= LevelStage.STAGE1_1 and stage <= LevelStage.STAGE3_2 and
                     game:GetStateFlag(GameStateFlag.STATE_BACKWARDS_PATH)
  
  if checkRoom then
    return levelCheck and
           level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and
           mod:getCurrentDimension() == 0
  end
  
  return levelCheck
end

-- corpse ii/xl (mother)
function mod:isCorpseII(checkRoom)
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  local levelCheck = (stage == LevelStage.STAGE4_2 or (mod:isCurseOfTheLabyrinth() and stage == LevelStage.STAGE4_1)) and
                     mod:isRepentanceStageType()
  
  if checkRoom then
    return levelCheck and
           room:GetType() == RoomType.ROOM_BOSS and
           roomDesc.GridIndex == GridRooms.ROOM_SECRET_EXIT_IDX
  end
  
  return levelCheck
end

-- ??? / hush (void room)
-- using the hush room doesn't usually work w/o workarounds
function mod:isBlueWomb(checkRoom)
  local level = game:GetLevel()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  local levelCheck = stage == LevelStage.STAGE4_3
  
  if checkRoom then
    return levelCheck and
           roomDesc.GridIndex == GridRooms.ROOM_THE_VOID_IDX
  end
  
  return levelCheck
end

-- satan/isaac
function mod:isSheolOrCathedral(checkRoom)
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  
  local levelCheck = stage == LevelStage.STAGE5
  
  if checkRoom then
    return levelCheck and
           room:IsCurrentRoomLastBoss()
  end
  
  return levelCheck
end

-- the lamb/blue baby
function mod:isDarkRoomOrChest(checkRoom)
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  local levelCheck = stage == LevelStage.STAGE6
  
  if checkRoom then
    return levelCheck and
           room:IsCurrentRoomLastBoss() and -- this can be mega satan in some challenges
           roomDesc.GridIndex >= 0          -- which we don't want, check for grid index
  end
  
  return levelCheck
end

-- delirium
-- red rooms can block devil doors here
function mod:isTheVoid(checkRoom)
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  local levelCheck = stage == LevelStage.STAGE7
  
  if checkRoom then
    return levelCheck and
           room:GetType() == RoomType.ROOM_BOSS and
           room:GetRoomShape() == RoomShape.ROOMSHAPE_2x2 and
           roomDesc.GridIndex >= 0
  end
  
  return levelCheck
end

-- dogma/beast (living room)
function mod:isHome(checkRoom)
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  
  local levelCheck = stage == LevelStage.STAGE8
  
  if checkRoom then
    return levelCheck and
           room:IsCurrentRoomLastBoss() and
           not mod:hasTv() -- requires no auto-cutscenes mod
  end
  
  return levelCheck
end

function mod:isRepentanceStageType()
  local level = game:GetLevel()
  local stageType = level:GetStageType()
  
  return stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B
end

function mod:isCurseOfTheLabyrinth()
  local level = game:GetLevel()
  local curses = level:GetCurses()
  local curse = LevelCurse.CURSE_OF_LABYRINTH
  
  return curses & curse == curse
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  for _, v in ipairs({ 'Stages', 'Debug' }) do
    ModConfigMenu.RemoveSubcategory(mod.Name, v)
  end
  for _, v in ipairs({
                       { stage = 'Basement I'       , field = 'enableBasementI', info = { 'Basement, Cellar, Burning Basement' } },
                       { stage = 'Pre-Ascent'       , field = 'enablePreAscent', info = { 'Spawns with Dad\'s Note', 'Mausoleum, Gehenna' } },
                       { stage = 'Ascent'           , field = 'enableAscent'   , info = { 'Spawns in the starting room with light beam', 'Backwards path: Mausoleum -> Basement' } },
                       { stage = 'Corpse II / XL'   , field = 'enableCorpseII' , info = { 'Spawns after defeating Mother' } },
                       { stage = '???'              , field = 'enableBlueWomb' , info = { 'Spawns in The Void room after defeating Hush', 'Duality + Goat Head effects enabled' } },
                       { stage = 'Sheol / Cathedral', field = 'enableSheol'    , info = { 'Spawns after defeating Satan or Isaac' } },
                       { stage = 'Dark Room / Chest', field = 'enableDarkRoom' , info = { 'Spawns after defeating The Lamb or ???' } },
                       { stage = 'The Void'         , field = 'enableTheVoid'  , info = { 'Spawns after defeating Delirium' } },
                       { stage = 'Home'             , field = 'enableHome'     , info = { 'Spawns in the living room after defeating', 'The Beast' } }
                    })
  do
    ModConfigMenu.AddSetting(
      mod.Name,
      'Stages',
      {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
          return mod.state[v.field]
        end,
        Display = function()
          return v.stage .. ' : ' .. (mod.state[v.field] and 'on' or 'off')
        end,
        OnChange = function(b)
          mod.state[v.field] = b
          mod:save(true)
        end,
        Info = v.info
      }
    )
  end
  ModConfigMenu.AddSetting(
    mod.Name,
    'Debug',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return false
      end,
      Display = function()
        local chance = mod:getDevilRoomChance()
        return string.format('Devil + Angel room chance: %.1f%%', math.min(chance, 1.0) * 100.0)
      end,
      OnChange = function(b)
        -- nothing to do
      end,
      Info = { 'The API doesn\'t separate these out' }
    }
  )
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, mod.onPreSpawnAward)

if ModConfigMenu then
  mod:setupModConfigMenu()
end