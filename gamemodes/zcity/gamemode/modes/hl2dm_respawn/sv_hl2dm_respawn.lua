MODE.name = "hl2dm_respawn"
MODE.PrintName = "Half-Life 2 Deathmatch (Respawn)"

MODE.Chance = 0.05

MODE.LootSpawn = false

MODE.ForBigMaps = true

MODE.OverideSpawnPos = true -- Required for GetPlySpawn to be called on respawn

-- Respawn system configuration
MODE.RespawnLives = 2 -- Base lives for Combine
MODE.RebelRespawnLives = 4 -- Rebels get one more life
MODE.RespawnDelay = 5

function MODE:ClearPlayerRoles()
    for _, ply in player.Iterator() do
        ply:SetNWString("PlayerRole", "")
        ply.subClass = nil
        ply.leader = nil
        ply.Lives = nil
        ply.timeDeath = nil
    end
end

function MODE.GuiltCheck(Attacker, Victim, add, harm, amt)
    return 1, true
end

-- Network strings
util.AddNetworkString("hl2dm_respawn_start")
util.AddNetworkString("hl2dm_respawn_roundend")
util.AddNetworkString("hl2dm_respawn_respawning")
util.AddNetworkString("hl2dm_respawn_eliminated")
util.AddNetworkString("hl2dm_respawn_lives")
util.AddNetworkString("RequestAirstrike_Respawn")

function MODE:Intermission()
    game.CleanUpMap()

    self.CTPoints = {}
    self.TPoints = {}
    table.CopyFromTo(zb.GetMapPoints("HMCD_TDM_T"), self.TPoints)
    table.CopyFromTo(zb.GetMapPoints("HMCD_TDM_CT"), self.CTPoints)

    for i, ply in ipairs(player.GetAll()) do
        ply:SetupTeam(ply:Team())
        -- Rebels (Team 0) get one more life than Combine (Team 1)
        ply.Lives = ply:Team() == 0 and self.RebelRespawnLives or self.RespawnLives
        ply.timeDeath = nil
    end

    -- Send each player their correct lives count
    for i, ply in ipairs(player.GetAll()) do
        net.Start("hl2dm_respawn_start")
        net.WriteInt(ply.Lives, 8)
        net.Send(ply)
    end
end

-- Check alive players, counting those with lives remaining as "alive" for round purposes
function MODE:CheckAlivePlayers()
    local tbl = {}

    for i, info in pairs(team.GetAllTeams()) do
        if i == TEAM_UNASSIGNED or i == TEAM_SPECTATOR then continue end
        tbl[i] = {}
    end

    for _, ply in ipairs(player.GetAll()) do
        if ply:Team() == TEAM_UNASSIGNED or ply:Team() == TEAM_SPECTATOR then continue end
        
        -- Player only counts as "out" if they have no lives remaining
        -- Dead players with lives left still count toward their team
        local hasLivesRemaining = ply.Lives and ply.Lives > 0
        local isAliveAndNotIncap = ply:Alive() and not (ply.organism and ply.organism.incapacitated)
        
        -- Include player if they're alive OR have lives to respawn with
        if isAliveAndNotIncap or hasLivesRemaining then
            tbl[ply:Team() or 0] = tbl[ply:Team() or 0] or {}
            tbl[ply:Team()][(#tbl[ply:Team() or 0] or 0) + 1] = ply
        end
    end

    return tbl
end

function MODE:ShouldRoundEnd()
    local endround, winner = zb:CheckWinner(self:CheckAlivePlayers())
    return endround
end

function MODE:RoundStart()
end

function MODE:GetPlySpawn(ply)
    -- Handle respawn positioning
    local plyTeam = ply:Team()
    if plyTeam == 1 then
        if self.CTPoints and #self.CTPoints > 0 then
            local point = self.CTPoints[math.random(#self.CTPoints)]
            if point and point.pos then
                ply:SetPos(point.pos)
            end
        end
    else
        if self.TPoints and #self.TPoints > 0 then
            local point = self.TPoints[math.random(#self.TPoints)]
            if point and point.pos then
                ply:SetPos(point.pos)
            end
        end
    end
end

-- Function to respawn a player with their role equipment
local function RespawnPlayer(ply, MODE)
    if not IsValid(ply) then return end
    if ply:Team() == TEAM_SPECTATOR then return end
    
    ply.subClass = nil
    
    -- Get spawn position BEFORE spawning
    local spawnPos = nil
    local plyTeam = ply:Team()
    if plyTeam == 1 then
        if MODE.CTPoints and #MODE.CTPoints > 0 then
            local point = MODE.CTPoints[math.random(#MODE.CTPoints)]
            if point and point.pos then
                spawnPos = point.pos + Vector(0, 0, 10) -- Slightly elevated to avoid getting stuck
            end
        end
    else
        if MODE.TPoints and #MODE.TPoints > 0 then
            local point = MODE.TPoints[math.random(#MODE.TPoints)]
            if point and point.pos then
                spawnPos = point.pos + Vector(0, 0, 10)
            end
        end
    end
    
    if not ply:Alive() then
        ply:Spawn()
    end
    
    -- Force set position and reset velocity
    if spawnPos then
        ply:SetPos(spawnPos)
        ply:SetVelocity(Vector(0, 0, 0))
        
        -- Set position again in next frame to ensure it sticks
        timer.Simple(0, function()
            if IsValid(ply) then
                ply:SetPos(spawnPos)
                ply:SetVelocity(Vector(0, 0, 0))
            end
        end)
    end
    
    ply:SetSuppressPickupNotices(true)
    ply.noSound = true

    -- Reapply player class based on team (like SMO does)
    if ply:Team() == 1 then
        ply:SetPlayerClass("Combine")
        zb.GiveRole(ply, "Combine", Color(0, 180, 200))
    else
        ply:SetPlayerClass("Rebel")
        zb.GiveRole(ply, "Rebel", Color(210, 80, 0))
    end

    local inv = ply:GetNetVar("Inventory", {})
    inv["Weapons"] = inv["Weapons"] or {}
    inv["Weapons"]["hg_sling"] = true
    ply:SetNetVar("Inventory", inv)

    local hands = ply:Give("weapon_hands_sh")
    if IsValid(hands) then
        ply:SelectWeapon(hands)
    end

    timer.Simple(0.1, function()
        if IsValid(ply) then
            ply.noSound = false
        end
    end)
    
    timer.Simple(0.2, function()
        if IsValid(ply) then
            ply:SelectWeapon("weapon_hands_sh")
        end
    end)

    ply:SetSuppressPickupNotices(false)
    
    -- Notify client of current lives
    net.Start("hl2dm_respawn_lives")
    net.WriteInt(ply.Lives or 0, 8)
    net.Send(ply)
end

function MODE:GiveEquipment()
    timer.Simple(0.1, function()
        local elites = 1
        local medics = 1
        local grenadiers = 1
        local shotgunners = 1
        local snipersC = 1
        local snipersR = 1

        local players_alive = zb:CheckPlaying()
        local leader = false
        
        for _, ply in RandomPairs(players_alive) do
            ply:SetSuppressPickupNotices(true)
            ply.noSound = true
            
            -- Initialize lives based on team - Rebels get one more life
            ply.Lives = ply:Team() == 0 and self.RebelRespawnLives or self.RespawnLives
            ply.timeDeath = nil

            local hands = ply:Give("weapon_hands_sh")
            ply:SelectWeapon(hands)

            if ply:Team() == 1 then
                if elites > 0 and not ply.subClass then
                    elites = elites - 1
                    ply.subClass = "elite"
                    if not leader then
                        ply.leader = true
                        ply:SetNWString("PlayerRole", "Elite")
                        leader = true
                    end
                end

                if shotgunners > 0 and not ply.subClass then
                    shotgunners = shotgunners - 1
                    ply.subClass = "shotgunner"
                    ply:SetNWString("PlayerRole", "Shotgunner")
                end

                if snipersC > 0 and (#players_alive > 6) and not ply.subClass then
                    snipersC = snipersC - 1
                    ply.subClass = "sniper"
                    local points = zb.GetMapPoints("HL2DM_SNIPERSPAWN")
                    if #points > 0 then
                        ply:SetPos(points[math.random(#points)].pos)
                    end
                end
            else
                if medics > 0 and not ply.subClass then
                    medics = medics - 1
                    ply.subClass = "medic"
                end

                if grenadiers > 0 and (#players_alive > 6) and not ply.subClass then
                    grenadiers = grenadiers - 1
                    ply.subClass = "grenadier"
                end

                if snipersR > 0 and (#players_alive > 6) and not ply.subClass then
                    snipersR = snipersR - 1
                    ply.subClass = "sniper"
                    local points = zb.GetMapPoints("HL2DM_CROSSBOWSPAWN")
                    if #points > 0 then
                        ply:SetPos(points[math.random(#points)].pos)
                    end
                end
            end
            
            local inv = ply:GetNetVar("Inventory", {})
            inv["Weapons"] = inv["Weapons"] or {}
            inv["Weapons"]["hg_sling"] = true
            ply:SetNetVar("Inventory", inv)

            ply:SetPlayerClass(ply:Team() == 1 and "Combine" or "Rebel")

            timer.Simple(0.1, function()
                if IsValid(ply) then
                    ply.noSound = false
                end
            end)

            ply:SetSuppressPickupNotices(false)
        end
    end)
end

-- RoundThink handles respawning players
function MODE:RoundThink()
    self.ThinkPlayersDeath = self.ThinkPlayersDeath or CurTime()
    
    if self.ThinkPlayersDeath < CurTime() then
        self.ThinkPlayersDeath = CurTime() + 0.5

        for i, ply in ipairs(player.GetAll()) do
            if not ply:Alive() and ply.timeDeath and (ply.timeDeath < CurTime()) then
                ply.timeDeath = nil
                RespawnPlayer(ply, self)
            end
        end
    end
end

function MODE:GetTeamSpawn()
    return zb.TranslatePointsToVectors(zb.GetMapPoints("HMCD_TDM_T")), zb.TranslatePointsToVectors(zb.GetMapPoints("HMCD_TDM_CT"))
end

function MODE:CanSpawn()
end

function MODE:EndRound()
    local team0, team1, winnerteam = 0, 0, 0
    for _, ply in player.Iterator() do
        -- Count players who are alive OR have lives remaining
        local hasLivesOrAlive = ply:Alive() or (ply.Lives and ply.Lives > 0)
        if hasLivesOrAlive and ply:Team() == 0 then
            team0 = team0 + 1
        elseif hasLivesOrAlive and ply:Team() == 1 then
            team1 = team1 + 1
        end
    end
    
    if team0 > team1 then
        winnerteam = 0 -- rebel wins
    elseif team1 > team0 then
        winnerteam = 1 -- combine wins
    elseif team0 == team1 then
        winnerteam = 2 -- draw
    end
    if team0 == 0 and team1 == 0 then
        winnerteam = 3 -- everybody died
    end
    
    self:ClearPlayerRoles()
    
    timer.Simple(2, function()
        net.Start("hl2dm_respawn_roundend")
        net.WriteInt(winnerteam, 3)
        net.Broadcast()
    end)
end

function MODE:PlayerDeath(_, ply)
    if not IsValid(ply) then return end
    
    -- Set default lives based on team if not already set
    ply.Lives = ply.Lives or (ply:Team() == 0 and self.RebelRespawnLives or self.RespawnLives)
    
    if ply.Lives < 1 then
        ply.Lives = 0
        return
    end
    
    -- Decrement lives and set respawn timer
    ply.Lives = ply.Lives - 1
    ply.timeDeath = CurTime() + self.RespawnDelay
    
    -- Notify client about respawn
    net.Start("hl2dm_respawn_respawning")
    net.WriteFloat(CurTime())
    net.WriteInt(ply.Lives, 8)
    net.Send(ply)
end

function MODE:CanLaunch()
    local TPoints = zb.GetMapPoints("HMCD_TDM_T")
    local CTPoints = zb.GetMapPoints("HMCD_TDM_CT")
    if TPoints and #TPoints > 0 and CTPoints and #CTPoints > 0 then
        return true
    end
    return false
end

-- Airstrike system (same as HL2DM)
local ACD_NextAirstrikeTime = 0 
local ACD_MaxStrikes = 2 
local ACD_StrikesLeft = {} 

local function FindAccessibleAngle(pos)
    for i = 1, 50 do
        local ang = AngleRand()
        local trace = util.QuickTrace(pos, ang:Forward() * 10000)
        if trace.HitSky then
            return ang
        end
    end
    return nil
end

local function FindCanisterPos(pos, normal, dist)
    local offsetPos = pos + normal * 10
    local trace = util.QuickTrace(offsetPos, -normal * dist * 2)
    
    if trace.Hit and util.PointContents(offsetPos) ~= CONTENTS_SOLID then
        local ang = FindAccessibleAngle(trace.HitPos + normal * 7)
        if ang then
            return {
                Pos = trace.HitPos + normal * 7,
                Ang = ang
            }
        end
    end
    return nil
end

local function Airstrike(pos, normal, ply)
    if CurTime() < ACD_NextAirstrikeTime then return end 
    local canisterData = FindCanisterPos(pos, normal, 1000)
    
    if canisterData then
        local ent = ents.Create("env_headcrabcanister")
        ent:SetPos(canisterData.Pos)
        ent:SetAngles(canisterData.Ang)
        ent:SetKeyValue("spawnflags", 8192)
        ent:Spawn()
        ent:Activate()
        ent:SetKeyValue("FlightSpeed", 5000)
        ent:SetKeyValue("FlightTime", 5)
        ent:SetKeyValue("SmokeLifetime", 30)
        ent:SetKeyValue("HeadcrabType", math.random(0, 2))
        ent:SetKeyValue("HeadcrabCount", 0)
        ent:SetKeyValue("Damage", 200)
        ent:SetKeyValue("DamageRadius", 300)
        ent:Fire("FireCanister")

        ACD_NextAirstrikeTime = CurTime() + 70
        ACD_StrikesLeft[ply] = (ACD_StrikesLeft[ply] or ACD_MaxStrikes) - 1
    end
end

net.Receive("RequestAirstrike_Respawn", function(len, ply)
    if not ply.leader then return end

    if ACD_StrikesLeft[ply] == nil then
        ACD_StrikesLeft[ply] = ACD_MaxStrikes
    end

    if ACD_StrikesLeft[ply] > 0 then
        local pos = ply:GetEyeTrace().HitPos
        local normal = ply:GetEyeTrace().HitNormal
        Airstrike(pos, normal, ply)
    else
        ply:ChatPrint("Access denied.")
    end
end)

hook.Add("PostCleanupMap", "ACD_ResetAirstrikes_Respawn", function()
    ACD_StrikesLeft = {} 
    ACD_NextAirstrikeTime = 0 
end)