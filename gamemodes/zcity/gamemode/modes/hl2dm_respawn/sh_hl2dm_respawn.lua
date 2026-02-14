local MODE = MODE

zb = zb or {}

--[[
    HL2DM Respawn Mode
    Combines HL2DM's Combine vs Rebel gameplay with SMO's respawn system
    Players get multiple lives and respawn after a delay
]]

zb = zb or {}
zb.Points = zb.Points or {}

zb.Points.HL2DM_SNIPERSPAWN = zb.Points.HL2DM_SNIPERSPAWN or {}
zb.Points.HL2DM_SNIPERSPAWN.Color = Color(243,9,9)
zb.Points.HL2DM_SNIPERSPAWN.Name = "HL2DM_SNIPERSPAWN"

zb.Points.HL2DM_CROSSBOWSPAWN = zb.Points.HL2DM_CROSSBOWSPAWN or {}
zb.Points.HL2DM_CROSSBOWSPAWN.Color = Color(243,9,9)
zb.Points.HL2DM_CROSSBOWSPAWN.Name = "HL2DM_CROSSBOWSPAWN"

-- Respawn configuration (shared so clients know the values)
MODE.RespawnLives = 3
MODE.RespawnDelay = 10
