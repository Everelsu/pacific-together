-- Helpers shared by the safety* scenarios (not a scenario itself).
local L = {}
local WARPER = "/Game/Gameplay/Inventory/Items/Car/Abilities/Abilities_TimeWarper_01/BP_Attach_Util_Ability_TimeWarper.BP_Attach_Util_Ability_TimeWarper_C"

local function gs() return StaticFindObject("/Script/Engine.Default__GameplayStatics") end

function L.paused(T) return gs():IsGamePaused(T.world()) end
function L.dilation(T) return gs():GetGlobalTimeDilation(T.world()) end

-- the game's own pause path (BP_UIManager_C:PauseGame -> GameplayStatics:SetGamePaused)
function L.pause(T, on)
    T.first("BP_UIManager_C"):PauseGame(FName("PacificTogetherTest"), on, {})
    T.log("PT|info PauseGame(%s) -> paused=%s", tostring(on), tostring(L.paused(T)))
end

-- a Chrono Dilator next to us, with its ability started (its timeline drives SetGlobalTimeDilation)
function L.startWarper(T)
    local c = LoadAsset(WARPER)
    local l = T.myPawn():K2_GetActorLocation()
    local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y, Z = l.Z + 400 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local w = gs():FinishSpawningActor(gs():BeginDeferredActorSpawnFromClass(T.world(), c, xf, 1, nil), xf)
    w:OnAbilityStart()
    T.log("PT|info warper %s started, dilation=%.3f", T.name(w), L.dilation(T))
    return w
end
function L.stopWarper(T, w)
    if w and w:IsValid() then w:OnAbilityEnd(); w:K2_DestroyActor() end
    gs():SetGlobalTimeDilation(T.world(), 1.0)
end

-- <copy>\PenDriverPro\Saved: the game runs in Binaries\Win64 (the runner's working directory)
function L.saved()
    local p = io.popen("cd")
    local cwd = p:read("l")
    p:close()
    return cwd:match("^(.*)\\Binaries\\Win64") .. "\\Saved"
end
-- running processes called name whose exe lies under root (default: our own copy)
function L.children(name, root)
    root = root or L.saved():match("^(.*)\\PenDriverPro\\Saved$")
    local p = io.popen('powershell -NoProfile -Command "@(Get-CimInstance Win32_Process -Filter \\"Name=\'' .. name .. '\'\\" | Where-Object { $_.ExecutablePath -like \'' .. root .. '\\*\' }).Count"')
    local n = tonumber(p:read("a"):match("%d+"))
    p:close()
    return n
end
function L.read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

-- name tags: TextRenderActors attached to a character
function L.tagsOn(T, char)
    local r = {}
    for _, a in ipairs(FindAllOf("TextRenderActor") or {}) do
        if a:IsValid() and T.inWorld(a) then
            local p = a:GetAttachParentActor()
            if p:IsValid() and (not char or p:GetFullName() == char:GetFullName()) and p:GetClass():GetFName():ToString() == T.CHAR then r[#r + 1] = a end
        end
    end
    return r
end
function L.tagState(T, a)
    local t = a.TextRender
    local c = t.TextRenderColor
    return { text = t.Text:ToString(), alpha = c.A, hidden = a.bHidden, mat = T.name(t:GetMaterial(0)) }
end

return L
