local mod = RegisterMod('More Devil Deals', 1)
local json = require('json')
local game = Game()

mod.onGameStartHasRun = false

mod.font = Font()
mod.font:Load('font/luaminioutlined.fnt')

mod.kcolorRed = KColor(1, 0, 0, 0.5) -- red / 50% alpha
mod.kcolorGreen = KColor(0, 1, 0, 0.5) -- green / 50% alpha

mod.devilAngelRoomStartOptions = { 'default', 'angel', '50/50' }

mod.state = {}
mod.state.devilRoomSpawned = nil -- 3 state: nil, false, true; likely edge case w/ glowing hourglass going back a floor
mod.state.lastDevilRoomStage = LevelStage.STAGE_NULL -- room:GetLastDevilRoomStage doesn't work
mod.state.lastStage = LevelStage.STAGE_NULL
mod.state.enableBasementI = true
mod.state.enablePreAscent = false
mod.state.enableAscent = false
mod.state.enableCorpseII = true
mod.state.enableBlueWomb = true
mod.state.enableSheol = true    -- cathedral
mod.state.enableDarkRoom = true -- chest
mod.state.enableTheVoid = true
mod.state.enableHome = true
mod.state.foundHudIntegration = false
mod.state.forceRoomType = false
mod.state.devilAngelRoomStart = 'default'

function mod:onGameStart(isContinue)
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if isContinue then
        if type(state.devilRoomSpawned) == 'boolean' then
          mod.state.devilRoomSpawned = state.devilRoomSpawned
        end
        for _, v in ipairs({ 'lastDevilRoomStage', 'lastStage' }) do
          if math.type(state[v]) == 'integer' and math.abs(state[v]) >= LevelStage.STAGE_NULL and math.abs(state[v]) < LevelStage.NUM_STAGES then
            mod.state[v] = state[v]
          end
        end
      end
      for _, v in ipairs({ 'enableBasementI', 'enablePreAscent', 'enableAscent', 'enableCorpseII', 'enableBlueWomb', 'enableSheol', 'enableDarkRoom', 'enableTheVoid', 'enableHome', 'foundHudIntegration', 'forceRoomType' }) do
        if type(state[v]) == 'boolean' then
          mod.state[v] = state[v]
        end
      end
      if type(state.devilAngelRoomStart) == 'string' and mod:getTblIdx(mod.devilAngelRoomStartOptions, state.devilAngelRoomStart) > 0 then
        mod.state.devilAngelRoomStart = state.devilAngelRoomStart
      end
    end
  end
  
  if not isContinue then
    mod:setDevilAngelRoomStart()
  end
  
  mod.onGameStartHasRun = true
  mod:onNewRoom()
end

function mod:onGameExit(shouldSave)
  if shouldSave then
    mod:save()
    mod.state.devilRoomSpawned = nil
    mod.state.lastStage = LevelStage.STAGE_NULL
    mod.state.lastDevilRoomStage = LevelStage.STAGE_NULL
  else
    mod.state.lastDevilRoomStage = LevelStage.STAGE_NULL
    mod.state.lastStage = LevelStage.STAGE_NULL
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
    state.foundHudIntegration = mod.state.foundHudIntegration
    state.forceRoomType = mod.state.forceRoomType
    state.devilAngelRoomStart = mod.state.devilAngelRoomStart
    
    mod:SaveData(json.encode(state))
  else
    mod:SaveData(json.encode(mod.state))
  end
end

-- onNewLevel runs after onNewRoom, but we don't do anything in onNewRoom in the first room of the floor, so this is ok
-- onNewLevel runs before onGameStart, but that should be ok for our use cases
-- onNewLevel doesn't run again on continue until you go down to the next floor
function mod:onNewLevel()
  if not game:IsGreedMode() then
    local level = game:GetLevel()
    local stage = level:GetStage()
    if mod:isRepentanceStageType() then
      stage = stage + 1
    end
    
    --  1 = basement i
    --  2 = basement ii
    --  3 = caves i
    --  4 = caves ii
    --  5 = depths i
    --  6 = depths ii
    --  7 = mausoleum ii (dad's note)
    -- -7 = mausoleum ii (ascent)
    -- -6 = depths ii (ascent)
    -- -5 = depths i (ascent)
    -- -4 = caves ii (ascent)
    -- -3 = caves i (ascent)
    -- -2 = basement ii (ascent)
    -- -1 = basement i (ascent)
    local ascentStages = { 1, 2, 3, 4, 5, 6, 7, -7, -6, -5, -4, -3, -2, -1 }
    
    if mod:isAscent(false) then
      -- deal with going backwards, otherwise we get 100% on every floor in the ascent
      stage = stage * -1
      
      if mod:tblHasVal(ascentStages, mod.state.lastDevilRoomStage) then
        local diff = mod:walkDiff(ascentStages, mod.state.lastDevilRoomStage, stage)
        if diff > 0 then
          local lastDevilRoomStage = math.abs(stage) - diff
          -- edge case: 0 (STAGE_NULL) always gives 100%
          -- positive and negative numbers work as expected
          if lastDevilRoomStage == 0 and diff < 3 then -- 33, 67, 100
            lastDevilRoomStage = lastDevilRoomStage + 1 -- if 67: give 33 instead of 100
          end
          game:SetLastDevilRoomStage(lastDevilRoomStage)
        end
      end
    elseif mod:isHome(false) then
      -- deal with going from STAGE1_1 to STAGE8, end path for the ascent, otherwise it'll always be 100%
      if mod.state.lastStage == -1 and mod:tblHasVal(ascentStages, mod.state.lastDevilRoomStage) then
        local diff = mod:walkDiff(ascentStages, mod.state.lastDevilRoomStage, mod.state.lastStage)
        if diff >= 0 then
          game:SetLastDevilRoomStage(stage - (diff + 1))
        end
      end
    elseif mod:isSheolOrCathedral(false) then
      -- deal with skipping STAGE4_3 (which is common)
      -- going from the womb ii to the cathedral can give 67 when 33 makes more sense since the blue womb is optional
      if (mod.state.lastStage == stage - 2 and mod.state.lastDevilRoomStage > 0 and mod.state.lastDevilRoomStage <= stage - 2) or -- womb ii
         (mod.state.lastStage == stage - 3 and mod.state.lastDevilRoomStage > 0 and mod.state.lastDevilRoomStage <= stage - 3)    -- womb xl
      then
        game:SetLastDevilRoomStage(mod.state.lastDevilRoomStage + 1)
      end
    elseif mod:isTheVoid(false) then
      -- guarantee non-guaranteed 100% in the void (you can still take red heart damage)
      game:SetLastDevilRoomStage(LevelStage.STAGE_NULL)
    end
    
    mod.state.devilRoomSpawned = nil
    mod.state.lastStage = stage
    
    if mod.state.forceRoomType and not mod:hasCollectible(CollectibleType.COLLECTIBLE_DUALITY) then
      if mod:isSheolOrDarkRoom() then
        level:InitializeDevilAngelRoom(false, true)
      elseif mod:isCathedralOrChest() then
        level:InitializeDevilAngelRoom(true, false)
      end
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
      elseif mod:isBlueWomb(true) then
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

function mod:onUpdate()
  if not game:IsGreedMode() and mod:hasDevilRoomDoor() then
    local level = game:GetLevel()
    local stage = level:GetStage()
    if mod:isRepentanceStageType() then
      stage = stage + 1
    end
    if mod:isAscent(false) then
      stage = stage * -1
    end
    
    mod.state.lastDevilRoomStage = stage
  end
end

function mod:onRender()
  if not mod.state.foundHudIntegration then
    return
  end
  
  local hud = game:GetHUD()
  local seeds = game:GetSeeds()
  
  if Options.FoundHUD and
     hud:IsVisible() and
     not seeds:HasSeedEffect(SeedEffect.SEED_NO_HUD) and
     not game:IsGreedMode() and
     not mod:isTheBeast() and
     Isaac.GetChallenge() ~= Challenge.CHALLENGE_RED_REDEMPTION and
     (
       (mod.state.enableBasementI and mod:isBasementI(false)) or
       (mod.state.enablePreAscent and mod:isPreAscent(false)) or
       (mod.state.enableAscent and mod:isAscent(false)) or
       (mod.state.enableCorpseII and mod:isCorpseII(false)) or
       (mod.state.enableBlueWomb and mod:isBlueWomb(false)) or
       (mod.state.enableSheol and mod:isSheolOrCathedral(false)) or
       (mod.state.enableDarkRoom and mod:isDarkRoomOrChest(false)) or
       (mod.state.enableTheVoid and mod:isTheVoid(false)) or
       (mod.state.enableHome and mod:isHome(false))
     )
  then
    local total, devil, angel = mod:getDevilAngelRoomChance()
    local coords1, coords2 = mod:getTextCoords()
    if not coords2 then
      local kcolor1 = total <= 0.0 and mod.kcolorRed or mod.kcolorGreen
      mod.font:DrawString(string.format('%.1f%%', math.min(total, 1.0) * 100.0), coords1.X, coords1.Y, kcolor1, 0, false)
    else
      local kcolor1 = devil <= 0.0 and mod.kcolorRed or mod.kcolorGreen
      local kcolor2 = angel <= 0.0 and mod.kcolorRed or mod.kcolorGreen
      mod.font:DrawString(string.format('%.1f%%', math.min(devil, 1.0) * 100.0), coords1.X, coords1.Y, kcolor1, 0, false)
      mod.font:DrawString(string.format('%.1f%%', math.min(angel, 1.0) * 100.0), coords2.X, coords2.Y, kcolor2, 0, false)
    end
  end
end

-- thanks to planetarium chance for help figuring some of this out
function mod:getTextCoords()
  local seeds = game:GetSeeds()
  local coords = Vector(35, 145) -- default w/ bombShift
  
  local shiftCount = 0
  local bombShift = false
  local poopShift = false
  local blueHeartShift = false
  local redHeartShift = false
  local trueCoopShift = false
  local jacobShift = false
  
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    local playerType = player:GetPlayerType()
    
    if playerType == PlayerType.PLAYER_BLUEBABY_B then
      poopShift = true
    else
      bombShift = true
      
      if playerType == PlayerType.PLAYER_BETHANY then
        blueHeartShift = true
      elseif playerType == PlayerType.PLAYER_BETHANY_B then
        redHeartShift = true
      end
    end
    
    if i == 0 then
      if playerType == PlayerType.PLAYER_JACOB then
        jacobShift = true
      end
    elseif i > 0 then
      -- not child, not co-op baby
      -- it's possible for a player to initially not be a child and then be changed to a child later on
      -- the game will still show the true co-op ui in that case, that's an edge case we're not checking for here
      -- you can quit/continue to fix the visual glitch
      if player.Parent == nil and player:GetBabySkin() == BabySubType.BABY_UNASSIGNED then
        trueCoopShift = true
      end
    end
  end
  
  if bombShift and poopShift then
    shiftCount = shiftCount + 1
  end
  if blueHeartShift then
    shiftCount = shiftCount + 1
  end
  if redHeartShift then
    shiftCount = shiftCount + 1
  end
  if shiftCount > 0 then
    coords = coords + Vector(0, (11 * shiftCount) - 2)
  end
  if trueCoopShift then
    if jacobShift then
      coords = coords + Vector(0, 26)
    else
      coords = coords + Vector(0, 12)
    end
  end
  if REPENTOGON then
    if game.Difficulty == Difficulty.DIFFICULTY_HARD or -- hard mode / victory laps
       game:AchievementUnlocksDisallowed() or           -- challenge, seeded, seed effect, rerun, etc
       Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL -- secondary challenge check
    then
      coords = coords + Vector(0, 16)
    end
  else
    if game.Difficulty == Difficulty.DIFFICULTY_HARD or                  -- hard mode / victory laps
       seeds:IsCustomRun() or                                            -- challenge or seeded run
       Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL or               -- secondary challenge check
       seeds:HasSeedEffect(SeedEffect.SEED_INFINITE_BASEMENT) or         -- infinite basements
       seeds:HasSeedEffect(SeedEffect.SEED_PICKUPS_SLIDE) or             -- tricky pickups
       seeds:HasSeedEffect(SeedEffect.SEED_ITEMS_COST_MONEY) or          -- f2p version
       seeds:HasSeedEffect(SeedEffect.SEED_PACIFIST) or                  -- pacifism
       seeds:HasSeedEffect(SeedEffect.SEED_ENEMIES_RESPAWN) or           -- enemies respawn
       seeds:HasSeedEffect(SeedEffect.SEED_POOP_TRAIL) or                -- poopy trail
       seeds:HasSeedEffect(SeedEffect.SEED_INVINCIBLE) or                -- dog mode
       seeds:HasSeedEffect(SeedEffect.SEED_KIDS_MODE) or                 -- kids' co-op mode
       seeds:HasSeedEffect(SeedEffect.SEED_PERMANENT_CURSE_LABYRINTH) or -- inescapable labyrinth
       seeds:HasSeedEffect(SeedEffect.SEED_PREVENT_CURSE_DARKNESS) or    -- illuminate darkness
       seeds:HasSeedEffect(SeedEffect.SEED_PREVENT_CURSE_LABYRINTH) or   -- escape the labyrinth
       seeds:HasSeedEffect(SeedEffect.SEED_PREVENT_CURSE_LOST) or        -- i once was lost
       seeds:HasSeedEffect(SeedEffect.SEED_PREVENT_CURSE_UNKNOWN) or     -- know the unknown
       seeds:HasSeedEffect(SeedEffect.SEED_PREVENT_CURSE_MAZE) or        -- stay out of the maze
       seeds:HasSeedEffect(SeedEffect.SEED_PREVENT_CURSE_BLIND) or       -- heal the blind
       seeds:HasSeedEffect(SeedEffect.SEED_PREVENT_ALL_CURSES) or        -- total curse immunity
       seeds:HasSeedEffect(SeedEffect.SEED_GLOWING_TEARS) or             -- glowing tears
       seeds:HasSeedEffect(SeedEffect.SEED_ALL_CHAMPIONS) or             -- champion enemies
       seeds:HasSeedEffect(SeedEffect.SEED_ALWAYS_CHARMED) or            -- charmed enemies
       seeds:HasSeedEffect(SeedEffect.SEED_ALWAYS_CONFUSED) or           -- confused enemies
       seeds:HasSeedEffect(SeedEffect.SEED_ALWAYS_AFRAID) or             -- scaredy enemies
       seeds:HasSeedEffect(SeedEffect.SEED_ALWAYS_ALTERNATING_FEAR) or   -- skittish enemies
       seeds:HasSeedEffect(SeedEffect.SEED_ALWAYS_CHARMED_AND_AFRAID) or -- asocial enemies
       seeds:HasSeedEffect(SeedEffect.SEED_SUPER_HOT) or                 -- super hot
       seeds:HasSeedEffect(SeedEffect.SEED_G_FUEL) or                    -- g fuel!
       not mod:hasMomBeenDefeated()                                      -- has mom been defeated?
    then
      coords = coords + Vector(0, 16)
    end
  end
  
  coords = coords + game.ScreenShakeOffset + (Options.HUDOffset * Vector(20, 12))
  
  if mod:hasCollectible(CollectibleType.COLLECTIBLE_DUALITY) then
    return coords
  end
  
  if trueCoopShift then
    return coords, coords + Vector(0, 14)
  end
  return coords, coords + Vector(0, 12)
end

-- cube of meat/ball of bandages/harbingers are available after defeating mom
-- genesis/sacred orb can make cube of meat/ball of bandages unavailable
-- book of revelations is available after defeating a harbinger
function mod:hasMomBeenDefeated()
  local itemConfig = Isaac.GetItemConfig()
  
  for _, v in ipairs({ CollectibleType.COLLECTIBLE_BOOK_OF_REVELATIONS, CollectibleType.COLLECTIBLE_CUBE_OF_MEAT, CollectibleType.COLLECTIBLE_BALL_OF_BANDAGES }) do
    if itemConfig:GetCollectible(v):IsAvailable() then
      return true
    end
  end
  
  return false
end

function mod:setDevilAngelRoomStart()
  if mod.state.devilAngelRoomStart == 'angel' then
    game:SetStateFlag(GameStateFlag.STATE_FAMINE_SPAWNED, false) -- angel room spawned
    game:SetStateFlag(GameStateFlag.STATE_DEVILROOM_SPAWNED, true)
    game:SetStateFlag(GameStateFlag.STATE_DEVILROOM_VISITED, false)
  elseif mod.state.devilAngelRoomStart == '50/50' then
    game:SetStateFlag(GameStateFlag.STATE_FAMINE_SPAWNED, false)
    game:SetStateFlag(GameStateFlag.STATE_DEVILROOM_SPAWNED, true)
    game:SetStateFlag(GameStateFlag.STATE_DEVILROOM_VISITED, true)
  else -- default
    --game:SetStateFlag(GameStateFlag.STATE_FAMINE_SPAWNED, false)
    --game:SetStateFlag(GameStateFlag.STATE_DEVILROOM_SPAWNED, false)
    --game:SetStateFlag(GameStateFlag.STATE_DEVILROOM_VISITED, false)
  end
end

function mod:spawnDevilRoomDoor()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local rng = level:GetDevilAngelRoomRNG()
  local animate = mod.state.devilRoomSpawned == nil
  local chance = mod:getDevilRoomChance()
  
  -- room:GetDevilRoomChance doesn't zero out on our custom floors, use a boolean to keep track of that
  if chance > 0.0 then
    local devilRoom = level:GetRoomByIdx(GridRooms.ROOM_DEVIL_IDX, -1)
    local isDevilRoomConfigNil = devilRoom.Data == nil
    
    -- keep consistent devil/angel room if leaving/entering boss room w/o going in devil/angel room
    if isDevilRoomConfigNil and not animate then
      local seed = rng:GetSeed()
      local shiftIdx = REPENTOGON and rng:GetShiftIdx() or 2
      rng = RNG()
      rng:SetSeed(seed, shiftIdx)
    end
    
    if rng:RandomFloat() < chance then
      if room:TrySpawnDevilRoomDoor(animate, true) then
        mod.state.devilRoomSpawned = true
        return
      end
    end
  end
  
  mod.state.devilRoomSpawned = false
end

function mod:spawnDevilRoomDoorBlueWomb()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local rng = level:GetDevilAngelRoomRNG()
  local animate = mod.state.devilRoomSpawned == nil
  local chance = mod:getDevilRoomChance()
  
  if chance > 0.0 then
    local devilRoom = level:GetRoomByIdx(GridRooms.ROOM_DEVIL_IDX, -1)
    local isDevilRoomConfigNil = devilRoom.Data == nil
    
    if isDevilRoomConfigNil and not animate then
      local seed = rng:GetSeed()
      local shiftIdx = REPENTOGON and rng:GetShiftIdx() or 2
      rng = RNG()
      rng:SetSeed(seed, shiftIdx)
    end
    
    if rng:RandomFloat() < chance then
      local seed = level:GetDevilAngelRoomRNG():GetSeed()
      local shiftIdx = REPENTOGON and level:GetDevilAngelRoomRNG():GetShiftIdx() or 2
      
      -- if the player has duality, 2 doors will spawn and the room config will be nil
      -- otherwise, only 1 door will spawn, we'll need to spawn a 2nd door and nil out the room config
      if room:TrySpawnDevilRoomDoor(animate, true) then
        if isDevilRoomConfigNil then
          local doors = mod:getDevilRoomDoors()
          
          if #doors < 2 then
            room:TrySpawnDevilRoomDoor(animate, true)
            doors = mod:getDevilRoomDoors()
            
            devilRoom.Data = nil
            
            if #doors >= 2 then
              doors[2].TargetRoomType = doors[1].TargetRoomType == RoomType.ROOM_DEVIL and RoomType.ROOM_ANGEL or RoomType.ROOM_DEVIL
            end
            
            -- reset rng so the devil room that spawns is the same as if you had duality
            level:GetDevilAngelRoomRNG():SetSeed(seed, shiftIdx)
          end
        end
        
        -- the wrong door sprites load in this room
        mod:updateDevilDoorSprites()
        
        if animate then
          mod:updateDevilDoorDustColor()
        end
        
        mod.state.devilRoomSpawned = true
        return
      end
    end
  end
  
  mod.state.devilRoomSpawned = false
end

function mod:hasDevilRoomDoor()
  local room = game:GetRoom()
  
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(i)
    
    if door and door.TargetRoomIndex == GridRooms.ROOM_DEVIL_IDX then
      return true
    end
  end
  
  return false
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

function mod:updateDevilDoorSprites()
  local room = game:GetRoom()
  
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(i)
    
    if door and door.TargetRoomIndex == GridRooms.ROOM_DEVIL_IDX then
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
end

function mod:updateDevilDoorDustColor()
  local lastDevilDoorSlot = -1
  
  for _, v in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.DUST_CLOUD, -1, false, false)) do
    if v.SubType == 0 or v.SubType == 1 then
      local devilDoorSlot = mod:getDevilDoorSlotFromPosition(v.Position)
      
      if devilDoorSlot >= 0 then
        if devilDoorSlot ~= lastDevilDoorSlot then
          v.SubType = 1
          v:GetSprite().Color:SetOffset(-0.5, -0.5, -0.5) -- black/devil
        else
          v.SubType = 0
          v:GetSprite().Color:SetOffset(0, 0, 0) -- white/angel
        end
        
        lastDevilDoorSlot = devilDoorSlot
      end
    end
  end
end

function mod:getDevilDoorSlotFromPosition(pos)
  local room = game:GetRoom()
  
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(i)
    
    if door and door.TargetRoomIndex == GridRooms.ROOM_DEVIL_IDX and room:GetGridIndex(room:GetDoorSlotPosition(i)) == room:GetGridIndex(pos) then
      return i
    end
  end
  
  return -1
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

function mod:hasTrinket(trinket)
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    
    if player:HasTrinket(trinket, false) then
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
    if Isaac.GetChallenge() == Challenge.CHALLENGE_RED_REDEMPTION then
      chance = 0.0
    elseif mod.state.enableBlueWomb and mod:isBlueWomb(false) then
      chance = 1.0
    elseif (mod.state.devilRoomSpawned == false and chance < 1.0) or -- goat head / eucharist
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
    end
  end
  
  return chance
end

function mod:getDevilAngelRoomChance()
  local level = game:GetLevel()
  local totalChance = math.min(mod:getDevilRoomChance(), 1.0)
  
  local angelRoomSpawned = game:GetStateFlag(GameStateFlag.STATE_FAMINE_SPAWNED) -- repurposed
  local devilRoomSpawned = game:GetStateFlag(GameStateFlag.STATE_DEVILROOM_SPAWNED)
  local devilRoomVisited = game:GetStateFlag(GameStateFlag.STATE_DEVILROOM_VISITED)
  
  local devilRoomChance = 1.0
  if mod:hasCollectible(CollectibleType.COLLECTIBLE_EUCHARIST) then
    devilRoomChance = 0.0
  elseif devilRoomSpawned and devilRoomVisited and game:GetDevilRoomDeals() > 0 then -- devil deals locked in
    if mod:hasCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES) or
       mod:hasCollectible(CollectibleType.COLLECTIBLE_ACT_OF_CONTRITION) or
       level:GetAngelRoomChance() > 0.0 -- confessional, sac room
    then
      devilRoomChance = 0.5
    end
  elseif devilRoomSpawned or mod:hasCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES) or level:GetAngelRoomChance() > 0.0 then
    if not (devilRoomVisited or angelRoomSpawned) then
      devilRoomChance = 0.0
    else
      devilRoomChance = 0.5
    end
  end
  
  -- https://bindingofisaacrebirth.fandom.com/wiki/Angel_Room#Angel_Room_Generation_Chance
  if devilRoomChance == 0.5 then
    if mod:hasTrinket(TrinketType.TRINKET_ROSARY_BEAD) then
      devilRoomChance = devilRoomChance * (1.0 - 0.5)
    end
    if game:GetDonationModAngel() >= 10 then -- donate 10 coins
      devilRoomChance = devilRoomChance * (1.0 - 0.5)
    end
    if mod:hasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_1) then
      devilRoomChance = devilRoomChance * (1.0 - 0.25)
    end
    if mod:hasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_2) then
      devilRoomChance = devilRoomChance * (1.0 - 0.25)
    end
    if level:GetStateFlag(LevelStateFlag.STATE_EVIL_BUM_KILLED) then
      devilRoomChance = devilRoomChance * (1.0 - 0.25)
    end
    if level:GetStateFlag(LevelStateFlag.STATE_BUM_LEFT) and not level:GetStateFlag(LevelStateFlag.STATE_EVIL_BUM_LEFT) then
      devilRoomChance = devilRoomChance * (1.0 - 0.1)
    end
    if level:GetStateFlag(LevelStateFlag.STATE_EVIL_BUM_LEFT) and not level:GetStateFlag(LevelStateFlag.STATE_BUM_LEFT) then
      devilRoomChance = devilRoomChance * (1.0 + 0.1)
    end
    if level:GetAngelRoomChance() > 0.0 or
       (level:GetAngelRoomChance() < 0.0 and (mod:hasCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES) or mod:hasCollectible(CollectibleType.COLLECTIBLE_ACT_OF_CONTRITION)))
    then
      devilRoomChance = devilRoomChance * (1.0 - level:GetAngelRoomChance())
    end
    if mod:hasCollectible(CollectibleType.COLLECTIBLE_BOOK_OF_VIRTUES) then
      devilRoomChance = devilRoomChance * (1.0 - 0.25)
    end
    devilRoomChance = math.max(0.0, math.min(devilRoomChance, 1.0))
  end
  
  if not game:IsGreedMode() then
    if mod:isBasementI(false) or
       mod:isPreAscent(false) or
       mod:isAscent(false) or
       mod:isCorpseII(false) or
       mod:isBlueWomb(false) or
       mod:isSheolOrCathedral(false) or
       mod:isDarkRoomOrChest(false) or
       mod:isTheVoid(false) or
       mod:isHome(false)
    then
      local devilRoom = level:GetRoomByIdx(GridRooms.ROOM_DEVIL_IDX, -1)
      if devilRoom.Data and devilRoom.Data.Type == RoomType.ROOM_DEVIL then
        devilRoomChance = 1.0
      elseif devilRoom.Data and devilRoom.Data.Type == RoomType.ROOM_ANGEL then
        devilRoomChance = 0.0
      elseif mod:isBlueWomb(false) then
        devilRoomChance = 0.5
      end
    end
  end
  
  local angelRoomChance = 1.0 - devilRoomChance
  return totalChance, totalChance * devilRoomChance, totalChance * angelRoomChance
end

function mod:tblHasVal(tbl, val)
  for _, v in ipairs(tbl) do
    if v == val then
      return true
    end
  end
  
  return false
end

function mod:getTblIdx(tbl, val)
  for i, v in ipairs(tbl) do
    if v == val then
      return i
    end
  end
  
  return 0
end

function mod:walkDiff(tbl, val1, val2)
  local i1, i2
  
  for i, v in ipairs(tbl) do
    if v == val1 then
      i1 = i
    end
    if v == val2 then
      i2 = i
    end
  end
  
  if i1 and i2 then
    return i2 - i1
  end
  
  return -1
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
  
  -- level:IsPreAscent
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
  
  -- level:IsAscent
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

function mod:isSheolOrDarkRoom()
  local level = game:GetLevel()
  local stage = level:GetStage()
  
  return (stage == LevelStage.STAGE5 or stage == LevelStage.STAGE6) and
         not level:IsAltStage()
end

function mod:isCathedralOrChest()
  local level = game:GetLevel()
  local stage = level:GetStage()
  
  return (stage == LevelStage.STAGE5 or stage == LevelStage.STAGE6) and
         level:IsAltStage()
end

function mod:isTheBeast()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  local stage = level:GetStage()
  
  -- ROOM_SECRET_EXIT_IDX/ROOM_DEBUG_IDX
  return stage == LevelStage.STAGE8 and
         room:GetType() == RoomType.ROOM_DUNGEON and
         (
           roomDesc.Data.Variant == 666 or
           roomDesc.Data.Variant == 667 or
           roomDesc.Data.Variant == 668 or
           roomDesc.Data.Variant == 669 or
           roomDesc.Data.Variant == 670 or
           roomDesc.Data.Variant == 671
         )
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
                       { stage = 'The Void'         , field = 'enableTheVoid'  , info = { 'Spawns after defeating Delirium', 'Start with 100% chance' } },
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
        local total, devil, angel = mod:getDevilAngelRoomChance()
        if mod:hasCollectible(CollectibleType.COLLECTIBLE_DUALITY) then
          return string.format('Devil + Angel room chance: %.1f%%', math.min(total, 1.0) * 100.0)
        end
        return string.format('Devil room chance: %.1f%%', math.min(devil, 1.0) * 100.0)
      end,
      OnChange = function(b)
        -- nothing to do
      end,
      Info = { ':)' }
    }
  )
  ModConfigMenu.AddSetting(
    mod.Name,
    'Debug',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return false
      end,
      Display = function()
        if mod:hasCollectible(CollectibleType.COLLECTIBLE_DUALITY) then
          return ''
        end
        local total, devil, angel = mod:getDevilAngelRoomChance()
        return string.format('Angel room chance: %.1f%%', math.min(angel, 1.0) * 100.0)
      end,
      OnChange = function(b)
        -- nothing to do
      end,
      Info = { ':)' }
    }
  )
  ModConfigMenu.AddSpace(mod.Name, 'Debug')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Debug',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.foundHudIntegration
      end,
      Display = function()
        return 'Found hud integration: ' .. (mod.state.foundHudIntegration and 'on' or 'off')
      end,
      OnChange = function(b)
        mod.state.foundHudIntegration = b
        mod:save(true)
      end,
      Info = { 'Requires found hud to be enabled', 'in the options menu' }
    }
  )
  ModConfigMenu.AddSetting(
    mod.Name,
    'Debug',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.forceRoomType
      end,
      Display = function()
        return 'Force room type in sheol/cathedral: ' .. (mod.state.forceRoomType and 'on' or 'off')
      end,
      OnChange = function(b)
        mod.state.forceRoomType = b
        mod:save(true)
      end,
      Info = { 'Devil room in sheol/dark room', 'Angel room in cathedral/chest', 'Applied at start of level (if no duality)' }
    }
  )
  ModConfigMenu.AddSetting(
    mod.Name,
    'Debug',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod:getTblIdx(mod.devilAngelRoomStartOptions, mod.state.devilAngelRoomStart)
      end,
      Minimum = 1,
      Maximum = #mod.devilAngelRoomStartOptions,
      Display = function()
        return 'Devil or angel room start: ' .. mod.state.devilAngelRoomStart
      end,
      OnChange = function(n)
        mod.state.devilAngelRoomStart = mod.devilAngelRoomStartOptions[n]
        mod:save(true)
      end,
      Info = { 'Default (devil), angel, or 50/50', 'This will be applied to your next run' }
    }
  )
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, mod.onPreSpawnAward)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)

if ModConfigMenu then
  mod:setupModConfigMenu()
end