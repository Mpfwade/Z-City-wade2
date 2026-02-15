local MODE = MODE

zb = zb or {}

--[[
    HL2DM Respawn Mode
    Combines HL2DM's Combine vs Rebel gameplay with SMO's respawn system
    Players get multiple lives and respawn after a delay
]]

zb = zb or {}
zb.Points = zb.Points or {}

-- Respawn configuration (shared so clients know the values)
MODE.RespawnLives = 3
MODE.RespawnDelay = 10
