--[[
    🌲 REBIRTH CHAMPIONS ULTIMATE — AUTO TREE FARMER (NEAREST & CLEAN)
    ====================================================================
    AKTUALIZACJA:
      1. SZYBSZE TEMPO (1.2 SEKUNDY):
         - Zmieniono czas fazy z 2.0s na 1.2s!
         - Faza 1: 1.2s po teleporcie (jak padnie wcześniej -> od razu leci dalej)
         - Krok 1 (W) + Faza 2: 1.2s
         - Krok 2 (W) + Faza 3: 1.2s
         - Jeśli po 2 krokach nadal stoi (3.6s) -> skip i 60 SEKUND BLACKLISTY na ten pień!
      2. 100% NIEZAWODNY PANIC BUTTON POD [END] (KILL SWITCH):
         - Wciśnięcie [End] (lub przycisku X w GUI) natychmiastowo:
           * Uśmierca wszystkie wątki i pętle bota (task.cancel)
           * Zatrzymuje ataki w grze i zeruje prędkości postaci
           * Odłącza WSZYSTKIE eventy
           * Całkowicie czyści i niszczy KAŻDE GUI (w gethui, CoreGui i PlayerGui)
           * Usuwa wszystkie ghost-instancje z pamięci
      3. CAŁKOWICIE WYKLUCZONE KRAINY (0 TELEPORTÓW):
         - Steampunk, Sakura, City, Spawn, Nuclear, Desert
      4. CELOWANIE:
         - Zawsze najbliższe dostępne żywe drzewo
    ====================================================================
]]

-- ====================================================================
-- CZYSZCZENIE POPRZEDNICH INSTANCJI I GHOST-GUI PRZED STARTEM
-- ====================================================================
local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local CollectionService   = game:GetService("CollectionService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService    = game:GetService("UserInputService")
local StarterGui          = game:GetService("StarterGui")
local CoreGui             = game:GetService("CoreGui")

local LP = Players.LocalPlayer

local function purgeAllGuis()
    pcall(function()
        if gethui then
            for _, c in ipairs(gethui():GetChildren()) do
                if c.Name:find("RCU_TreeFarm") then
                    pcall(function() c:Destroy() end)
                end
            end
        end
    end)
    pcall(function()
        for _, c in ipairs(CoreGui:GetChildren()) do
            if c.Name:find("RCU_TreeFarm") then
                pcall(function() c:Destroy() end)
            end
        end
    end)
    pcall(function()
        local pg = LP:FindFirstChild("PlayerGui")
        if pg then
            for _, c in ipairs(pg:GetChildren()) do
                if c.Name:find("RCU_TreeFarm") then
                    pcall(function() c:Destroy() end)
                end
            end
        end
    end)
end

-- Uruchomienie kill switcha poprzedniej instancji jeśli istnieje
if getgenv and getgenv().RCU_PanicKill then
    pcall(getgenv().RCU_PanicKill)
end
purgeAllGuis()

local ScriptActive = true
local ScriptConnections = {}
local ScriptThreads = {}

local function addConnection(conn)
    table.insert(ScriptConnections, conn)
    return conn
end

local function addThread(t)
    table.insert(ScriptThreads, t)
    return t
end

local Settings = {
    AutoFarm        = true,     -- Domyślnie włączone
    AutoEquipAxe    = true,     -- Auto-wyciąganie Sakura Axe
    AttackDistance  = 4.0,      -- Dystans podejścia od pnia
    HitRate         = 0.10,     -- Częstotliwość uderzeń podczas fazy
    PhaseDuration   = 1.2,      -- ZMIENIONO NA 1.2s NA FAZĘ!
}

local Stats = {
    TreesChopped    = 0,
    CurrentTarget   = "Brak",
    Status          = "Inicjalizacja...",
}

local skipTrees = {}
local lastEquipAttempt = 0

-- ====================================================================
-- 1. CZARNA LISTA KRAIN (WYKLUCZONE Z FARMY I TELEPORTÓW)
-- ====================================================================
local BANNED_REALMS = {
    ["steampunk"] = true,
    ["sakura"]    = true,
    ["city"]      = true,
    ["spawn"]     = true,
    ["nuclear"]   = true,
    ["desert"]    = true,
}

local function isMapBanned(name)
    if not name or type(name) ~= "string" then return false end
    local m = name:lower():gsub("%s+", "")
    if BANNED_REALMS[m] then return true end
    for banned, _ in pairs(BANNED_REALMS) do
        if m:find(banned) then return true end
    end
    return false
end

local function isTreeBanned(treeFolder)
    if not treeFolder then return true end

    -- 1. Atrybut groupId
    local gid = treeFolder:GetAttribute("groupId")
    if gid and type(gid) == "string" and isMapBanned(gid) then
        return true
    end

    -- 2. Nazwa samego obiektu
    if isMapBanned(treeFolder.Name) then
        return true
    end

    -- 3. Strefa w Workspace.Game.Maps.<World>.<Zone>
    local curr = treeFolder.Parent
    while curr and curr ~= Workspace do
        if curr.Parent and (curr.Parent.Name == "Maps" or curr.Parent.Name:match("^W%d+") or curr.Parent.Name == "Game") then
            if isMapBanned(curr.Name) then
                return true
            end
        end
        curr = curr.Parent
    end

    return false
end

-- ====================================================================
-- 2. KONTROLERY GRY (TreeController & DataController)
-- ====================================================================
local treeController = nil
local dataController = nil
local treeService    = nil
local lumberId       = nil

local function hookGameControllers()
    pcall(function()
        if getgc then
            for _, obj in ipairs(getgc(true)) do
                if type(obj) == "table" then
                    if rawget(obj, "Name") == "TreeController" then
                        treeController = obj
                    elseif rawget(obj, "Name") == "DataController" or (rawget(obj, "getData") and rawget(obj, "replica")) then
                        dataController = obj
                    end
                end
            end
        end
    end)

    if treeController and debug and debug.getupvalues then
        pcall(function()
            if treeController.autoDamageTree then
                local uvs = debug.getupvalues(treeController.autoDamageTree)
                for _, v in pairs(uvs) do
                    local t = typeof(v)
                    if t == "table" and rawget(v, "damage2") then
                        treeService = v
                    elseif t == "table" and rawget(v, "getData") and not dataController then
                        dataController = v
                    elseif (t == "string" or t == "number") and not lumberId then
                        lumberId = v
                    end
                end
            end
        end)
    end
end
hookGameControllers()

-- ====================================================================
-- 3. POMOCNIK KLIKANIA W GUI
-- ====================================================================
local function clickGuiBtn(btn, doubleClick)
    if not btn then return false end

    local function singleClick()
        pcall(function()
            if getconnections then
                for _, conn in ipairs(getconnections(btn.Activated)) do conn:Fire() end
                for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do conn:Fire() end
                for _, conn in ipairs(getconnections(btn.MouseButton1Down)) do conn:Fire() end
                for _, conn in ipairs(getconnections(btn.MouseButton1Up)) do conn:Fire() end
            end
        end)

        pcall(function()
            if firesignal then
                firesignal(btn.Activated)
                firesignal(btn.MouseButton1Click)
                firesignal(btn.MouseButton1Down)
                firesignal(btn.MouseButton1Up)
            end
        end)

        pcall(function()
            local pos = btn.AbsolutePosition
            local size = btn.AbsoluteSize
            local cx = pos.X + size.X / 2
            local cy = pos.Y + size.Y / 2
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
            task.wait(0.02)
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
        end)
    end

    singleClick()
    if doubleClick then
        task.wait(0.12)
        singleClick()
    end

    return true
end

-- ====================================================================
-- 4. DETEKCJA I WYCIĄGANIE SAKURA AXE
-- ====================================================================
local function isAxeEquipped()
    local char = LP.Character
    if not char then return false end
    if char:FindFirstChild("_axe") ~= nil then
        return true
    end
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp and bp:FindFirstChild("_axe") then return true end
    for _, child in ipairs(char:GetChildren()) do
        local n = child.Name:lower()
        if n:find("axe") or n:find("siekiera") then
            return true
        end
    end
    if dataController then
        local ok, res = pcall(function()
            local d = dataController:getData()
            return d and d.isAxeEquipped == true
        end)
        if ok and res then return true end
    end
    return false
end

local function equipSakuraAxe()
    if isAxeEquipped() then return true end
    if tick() - lastEquipAttempt < 2.0 then return false end
    lastEquipAttempt = tick()

    pcall(hookGameControllers)

    -- Krok 1: Otwórz Pets menu
    local pGui = LP:FindFirstChild("PlayerGui")
    local mainUI = pGui and pGui:FindFirstChild("MainUI")
    local hud = mainUI and mainUI:FindFirstChild("HUD")
    local bars = hud and hud:FindFirstChild("Bars")
    local leftBar = bars and bars:FindFirstChild("Left")
    local row2 = leftBar and leftBar:FindFirstChild("Row2")
    local petsFrame = row2 and row2:FindFirstChild("Pets")
    local petsBtn = petsFrame and petsFrame:FindFirstChild("Main") and petsFrame.Main:FindFirstChild("Click")

    if petsBtn then
        clickGuiBtn(petsBtn, false)
        task.wait(0.40)
    end

    -- Krok 2: Kliknij zakładkę "Items"
    local menus = mainUI and mainUI:FindFirstChild("Menus")
    local invMenu = menus and menus:FindFirstChild("InventoryFrame")
    local utility = invMenu and invMenu:FindFirstChild("Utility")
    local dispList = utility and utility:FindFirstChild("Displays") and utility.Displays:FindFirstChild("List")
    local itemsTab = dispList and dispList:FindFirstChild("Items") and dispList.Items:FindFirstChild("Click")

    if itemsTab then
        clickGuiBtn(itemsTab, false)
        task.wait(0.40)
    end

    -- Krok 3: Przewiń listę na sam dół (CanvasPosition = 99999)
    local itemsDisp = invMenu and invMenu:FindFirstChild("Displays") and invMenu.Displays:FindFirstChild("Items")
    local list = itemsDisp and itemsDisp:FindFirstChild("List")
    local listHolder = list and list:FindFirstChild("Holder")
    if listHolder and listHolder:IsA("ScrollingFrame") then
        pcall(function()
            listHolder.CanvasPosition = Vector2.new(0, 99999)
        end)
        task.wait(0.30)
    end

    -- Krok 4: Znajdź kartę Sakura Axe
    local exclusiveSection = listHolder and listHolder:FindFirstChild("Exclusive")
    local clips = exclusiveSection and exclusiveSection:FindFirstChild("Clips")
    local clipsHolder = clips and clips:FindFirstChild("Holder")

    local cardBtn = nil

    if clipsHolder then
        local exactCard = clipsHolder:FindFirstChild("07a3142449904a45b8a132c6f35b351f")
        if exactCard and exactCard:FindFirstChild("Main") and exactCard.Main:FindFirstChild("Click") then
            cardBtn = exactCard.Main.Click
        end
    end

    if not cardBtn and clipsHolder then
        for _, card in ipairs(clipsHolder:GetChildren()) do
            if card:IsA("GuiObject") and card:FindFirstChild("Main") and card.Main:FindFirstChild("Click") then
                for _, desc in ipairs(card:GetDescendants()) do
                    if desc:IsA("TextLabel") and (desc.Text:lower():find("sakura") or desc.Text:lower():find("axe")) then
                        cardBtn = card.Main.Click
                        break
                    end
                end
                if cardBtn then break end
            end
        end
    end

    if not cardBtn and clipsHolder then
        for _, card in ipairs(clipsHolder:GetChildren()) do
            if card:IsA("GuiObject") and card:FindFirstChild("Main") and card.Main:FindFirstChild("Click") then
                cardBtn = card.Main.Click
                break
            end
        end
    end

    if cardBtn then
        clickGuiBtn(cardBtn, true)
        task.wait(0.35)
    end

    for i = 1, 10 do
        if isAxeEquipped() then break end
        task.wait(0.10)
    end

    -- Krok 5: Zamknij ekwipunek
    if petsBtn then
        clickGuiBtn(petsBtn, false)
    elseif invMenu and invMenu:FindFirstChild("Close") and invMenu.Close:FindFirstChild("Click") then
        clickGuiBtn(invMenu.Close.Click, false)
    end
    task.wait(0.20)

    return isAxeEquipped()
end

-- ====================================================================
-- 5. POZYCJA I STAN DRZEW
-- ====================================================================
local function getTreePrimary(treeFolder)
    local model = treeFolder:FindFirstChildWhichIsA("Model")
    return (model and model.PrimaryPart) 
        or treeFolder:FindFirstChild("Part") 
        or treeFolder:FindFirstChildWhichIsA("BasePart", true)
end

local function getTreePosition(treeFolder)
    local primary = getTreePrimary(treeFolder)
    if primary then
        return primary.Position
    end
    if treeFolder:IsA("PVInstance") then
        local pcallOk, cf = pcall(function() return treeFolder:GetPivot() end)
        if pcallOk and cf then
            return cf.Position
        end
    end
    local anyPart = treeFolder:FindFirstChildWhichIsA("BasePart", true)
    if anyPart then
        return anyPart.Position
    end
    return nil
end

local function isTreeAlive(treeFolder)
    if not treeFolder or not treeFolder.Parent then return false end
    if isTreeBanned(treeFolder) then return false end

    -- Czarna lista (cooldown po ścięciu lub na oporne drzewa)
    if skipTrees[treeFolder] and tick() < skipTrees[treeFolder] then
        return false
    end

    -- Sprawdź licznik respawnu w silniku gry
    local respawnGui = treeFolder:FindFirstChild("TreeRespawn", true)
    if respawnGui and respawnGui:IsA("BillboardGui") and respawnGui.Enabled == true then
        local timerLbl = respawnGui:FindFirstChild("Timer", true)
        if timerLbl and timerLbl:IsA("TextLabel") and timerLbl.Text ~= "" and timerLbl.Text ~= "0" and timerLbl.Text ~= "00:00" and not timerLbl.Text:lower():find("label") then
            return false
        end
    end

    -- Sprawdź DataController
    if dataController then
        pcall(function()
            local d = dataController:getData()
            local gid = treeFolder:GetAttribute("groupId")
            local tid = treeFolder:GetAttribute("treeId")
            if d and d.trees and gid and tid then
                local group = d.trees[gid] or d.trees[tostring(gid)]
                if group then
                    local tData = group[tid] or group[tonumber(tid)] or group[tostring(tid)]
                    if tData and tData.respawn and tData.respawn > 0 then
                        return false
                    end
                end
            end
        end)
    end

    -- Fizyczna widoczność
    if treeFolder:IsA("BasePart") and treeFolder.Transparency < 0.95 then
        return true
    end
    for _, p in ipairs(treeFolder:GetDescendants()) do
        if p:IsA("BasePart") and p.Transparency < 0.95 then
            return true
        end
    end

    return false
end

-- ====================================================================
-- 6. WYBÓR NAJBLIŻSZEGO DOSTĘPNEGO DRZEWA
-- ====================================================================
local function getNearestAliveTree()
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local allTrees = CollectionService:GetTagged("Tree")
    local nearest = nil
    local minDist = math.huge

    for _, t in ipairs(allTrees) do
        if not isTreeBanned(t) and isTreeAlive(t) then
            local pos = getTreePosition(t)
            if pos then
                local dist = (hrp.Position - pos).Magnitude
                if dist < minDist then
                    minDist = dist
                    nearest = t
                end
            end
        end
    end

    return nearest
end

-- ====================================================================
-- 7. KAMERA I TELEPORTACJA
-- ====================================================================
local function alignCameraToTree(treeFolder)
    local primPos = getTreePosition(treeFolder)
    if not primPos then return end

    local cam = Workspace.CurrentCamera
    local camPos = cam.CFrame.Position
    local aimTarget = Vector3.new(primPos.X, primPos.Y + 1.2, primPos.Z)

    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local hrpPos = hrp.Position
        local lookGround = Vector3.new(aimTarget.X, hrpPos.Y, aimTarget.Z)
        hrp.CFrame = CFrame.lookAt(hrpPos, lookGround)
    end

    pcall(function()
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = CFrame.lookAt(camPos, aimTarget)
        task.wait(0.02)
        cam.CameraType = Enum.CameraType.Custom
    end)
end

local function teleportToTree(treeFolder)
    if isTreeBanned(treeFolder) then return false end

    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local primPos = getTreePosition(treeFolder)
    if not primPos then return false end

    local hrpPos  = hrp.Position

    local dir = Vector3.new(hrpPos.X - primPos.X, 0, hrpPos.Z - primPos.Z)
    if dir.Magnitude < 0.1 then
        dir = Vector3.new(1, 0, 0)
    else
        dir = dir.Unit
    end

    local targetX = primPos.X + (dir.X * Settings.AttackDistance)
    local targetZ = primPos.Z + (dir.Z * Settings.AttackDistance)

    -- Dynamiczny raycast podłoża (ochrona przed próżnią)
    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = { char, treeFolder }
    rp.FilterType = Enum.RaycastFilterType.Exclude

    -- 1. Grunt pod pniem
    local treeGround = Workspace:Raycast(Vector3.new(primPos.X, primPos.Y + 15, primPos.Z), Vector3.new(0, -60, 0), rp)
    local baseGroundY = treeGround and (treeGround.Position.Y + 3.0) or (primPos.Y - 4.5)

    -- 2. Grunt pod punktem lądowania
    local spotGround = Workspace:Raycast(Vector3.new(targetX, primPos.Y + 15, targetZ), Vector3.new(0, -60, 0), rp)
    if not spotGround and treeGround then
        targetX = primPos.X - (dir.X * Settings.AttackDistance)
        targetZ = primPos.Z - (dir.Z * Settings.AttackDistance)
        spotGround = Workspace:Raycast(Vector3.new(targetX, primPos.Y + 15, targetZ), Vector3.new(0, -60, 0), rp)
    end

    local targetY = spotGround and (spotGround.Position.Y + 3.0) or baseGroundY

    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = CFrame.lookAt(Vector3.new(targetX, targetY, targetZ), Vector3.new(primPos.X, targetY, primPos.Z))

    alignCameraToTree(treeFolder)
    task.wait(0.06)
    return true
end

-- ====================================================================
-- 8. KROK W PRZÓD (W)
-- ====================================================================
local function stepForwardTowardsTree(treeFolder, stepDistance)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp then return end

    local primPos = getTreePosition(treeFolder)
    if not primPos then return end

    local fwd = Vector3.new(primPos.X - hrp.Position.X, 0, primPos.Z - hrp.Position.Z)
    if fwd.Magnitude > 0.1 then
        fwd = fwd.Unit
    else
        fwd = hrp.CFrame.LookVector
    end

    -- 1. Fizyczny krok postaci do przodu
    hrp.CFrame = hrp.CFrame + (fwd * stepDistance)

    -- 2. Klawisz W w silniku
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
        task.wait(0.04)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
    end)
    if hum then
        pcall(function() hum:Move(fwd) end)
    end

    alignCameraToTree(treeFolder)
end

-- ====================================================================
-- 9. CYKL BICIA (1.2s NA FAZĘ Z KROKAMI W I NATYCHMIASTOWYM PRZERWANIEM)
-- ====================================================================
local function performHitCycle(treeFolder, durationSec)
    local primPos = getTreePosition(treeFolder)
    if not primPos then return false end

    if not isTreeAlive(treeFolder) then
        return false
    end

    local groupId = treeFolder:GetAttribute("groupId")
    local treeId = treeFolder:GetAttribute("treeId")

    pcall(function()
        if treeController then
            treeController._currentTree = treeFolder
            treeController._selectedTree = treeFolder
            if treeController.autoDamageTree then
                treeController:autoDamageTree()
            end
        end
    end)

    local start = tick()
    local lastDirectHit = 0

    while (tick() - start) < durationSec do
        if not ScriptActive or not Settings.AutoFarm then
            return false
        end

        -- Natychmiastowy sukces jak drzewo pęknie!
        if not isTreeAlive(treeFolder) then
            return true
        end

        local now = tick()

        -- Bezpośredni pakiet sieciowy damage2
        if treeService and treeService.damage2 and (now - lastDirectHit) >= 0.18 then
            lastDirectHit = now
            pcall(function()
                treeService.damage2:Fire(groupId, treeId, lumberId)
            end)
        end

        -- Kliknięcie wirtualne w pień
        pcall(function()
            local cam = Workspace.CurrentCamera
            local sPos, onScreen = cam:WorldToViewportPoint(primPos)
            local clickX = onScreen and sPos.X or (cam.ViewportSize.X / 2)
            local clickY = onScreen and sPos.Y or (cam.ViewportSize.Y / 2)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 1)
            task.wait(0.015)
            VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 1)
        end)

        task.wait(Settings.HitRate)
    end

    return not isTreeAlive(treeFolder)
end

local function chopTargetTreeWithSteps(treeFolder)
    if isTreeBanned(treeFolder) then return false end

    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end

    local primPos = getTreePosition(treeFolder)
    local dist = primPos and math.floor((hrp.Position - primPos).Magnitude) or 0
    Stats.CurrentTarget = string.format("%s (%d studów)", treeFolder.Name, dist)

    -- FAZA 1: Pierwsze tempo po teleporcie (1.2s)
    Stats.Status = "Rąbię (Faza 1 - 1.2s)..."
    local dead = performHitCycle(treeFolder, Settings.PhaseDuration)
    if dead or not Settings.AutoFarm or not ScriptActive then
        if dead then
            skipTrees[treeFolder] = tick() + 15
            Stats.TreesChopped = Stats.TreesChopped + 1
            Stats.Status = "Ścięto w 1. tempo!"
            task.wait(0.05)
            return true
        end
        return false
    end

    -- FAZA 2: Pierwszy krok w przód (W) + 1.2s
    Stats.Status = "Krok w przód (W) -> Faza 2 (1.2s)..."
    stepForwardTowardsTree(treeFolder, 0.85)
    dead = performHitCycle(treeFolder, Settings.PhaseDuration)
    if dead or not Settings.AutoFarm or not ScriptActive then
        if dead then
            skipTrees[treeFolder] = tick() + 15
            Stats.TreesChopped = Stats.TreesChopped + 1
            Stats.Status = "Ścięto po kroku (W)!"
            task.wait(0.05)
            return true
        end
        return false
    end

    -- FAZA 3: Drugi krok w przód (W) + 1.2s
    Stats.Status = "Drugi krok w przód (W) -> Faza 3 (1.2s)..."
    stepForwardTowardsTree(treeFolder, 0.85)
    dead = performHitCycle(treeFolder, Settings.PhaseDuration)
    if dead or not Settings.AutoFarm or not ScriptActive then
        if dead then
            skipTrees[treeFolder] = tick() + 15
            Stats.TreesChopped = Stats.TreesChopped + 1
            Stats.Status = "Ścięto po 2. kroku (W)!"
            task.wait(0.05)
            return true
        end
        return false
    end

    -- FAZA 4: Drzewo nie pękło mimo 2 kroków (W) -> ZMIANA DRZEWA
    -- I PEŁNA 1 MINUTA (60 SEKUND) ZAKAZU TELEPORTACJI DO TEGO DRZEWA!
    Stats.Status = "Oporne drzewo! Ignoruję na 60s..."
    skipTrees[treeFolder] = tick() + 60
    task.wait(0.05)
    return false
end

-- ====================================================================
-- 10. BEZWZGLĘDNY KILL SWITCH (PANIC KILL)
-- ====================================================================
local ToggleBtn = nil
local ScreenGui = nil

local function panicKillAll()
    ScriptActive = false
    Settings.AutoFarm = false

    -- 1. Zatrzymanie wątków w silniku Luau
    for _, th in ipairs(ScriptThreads) do
        pcall(function() task.cancel(th) end)
    end
    table.clear(ScriptThreads)

    -- 2. Zatrzymanie ataków w kontrolerze gry
    pcall(function()
        if treeController and treeController.cancelAutoDamageTree then
            treeController:cancelAutoDamageTree()
        end
    end)

    -- 3. Zatrzymanie postaci
    pcall(function()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        if hum then
            hum:Move(Vector3.zero)
        end
    end)

    -- 4. Odłączenie wszystkich połączeń
    for _, conn in ipairs(ScriptConnections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(ScriptConnections)

    -- 5. Całkowite zniszczenie GUI ze WSZYSTKICH kontenerów
    pcall(function()
        if ScreenGui then
            ScreenGui:Destroy()
        end
    end)
    purgeAllGuis()

    -- 6. Czyszczenie getgenv
    if getgenv then
        getgenv().RCU_PanicKill = nil
        getgenv().RCU_Running = nil
    end

    -- 7. Powiadomienie
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "🚨 PANIC KILL",
            Text = "Skrypt, procesy i GUI zostały CAŁKOWICIE ZAMKNIĘTE I USUNIĘTE!",
            Duration = 5
        })
    end)
end

if getgenv then
    getgenv().RCU_PanicKill = panicKillAll
end

-- ====================================================================
-- 11. GŁÓWNA PĘTLA BOTA
-- ====================================================================
local farmThread = task.spawn(function()
    while ScriptActive do
        if Settings.AutoFarm then
            local char = LP.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if hrp and hum and hum.Health > 0 then
                -- 1. Zapewnij siekierę
                if Settings.AutoEquipAxe and not isAxeEquipped() then
                    Stats.Status = "Wyciągam Sakura Axe..."
                    equipSakuraAxe()
                end

                -- 2. Pobierz najbliższe dostępne żywe drzewo
                Stats.Status = "Szukam najbliższego drzewa..."
                local target = getNearestAliveTree()

                if target then
                    -- 3. Teleportuj pod pień
                    teleportToTree(target)

                    -- 4. Rąb z 2 krokami (W) i 60s blacklistą w razie oporu
                    chopTargetTreeWithSteps(target)
                else
                    Stats.Status = "Brak dostępnych drzew. Czekam na respawn..."
                    task.wait(0.5)
                end
            else
                Stats.Status = "Czekam na postać..."
                task.wait(0.4)
            end
        else
            Stats.Status = "Zatrzymano (Włącz Auto Farm)"
            task.wait(0.3)
        end
        task.wait(0.02)
    end
end)
addThread(farmThread)

-- ====================================================================
-- 12. INTERFEJS GRAFICZNY (GUI) Z PRZYCISKIEM PANIC KILL
-- ====================================================================
local guiName = "RCU_TreeFarm_Clean"

ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = guiName
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if gethui then
        ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = LP:WaitForChild("PlayerGui")
    else
        ScreenGui.Parent = LP:WaitForChild("PlayerGui")
    end
end)
if not ScreenGui.Parent then
    ScreenGui.Parent = LP:WaitForChild("PlayerGui")
end

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 320, 0, 270)
MainFrame.Position = UDim2.new(0.5, -160, 0.45, -135)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(46, 170, 80)
MainStroke.Thickness = 1.5
MainStroke.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -90, 0, 26)
TitleLabel.Position = UDim2.new(0, 10, 0, 10)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "🌲 RCU AUTO TREE"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextSize = 13
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = MainFrame

-- Fizyczny przycisk [KILL] w nagłówku GUI
local HeaderKillBtn = Instance.new("TextButton")
HeaderKillBtn.Size = UDim2.new(0, 68, 0, 22)
HeaderKillBtn.Position = UDim2.new(1, -76, 0, 10)
HeaderKillBtn.BackgroundColor3 = Color3.fromRGB(190, 45, 45)
HeaderKillBtn.BorderSizePixel = 0
HeaderKillBtn.Text = "✕ KILL"
HeaderKillBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
HeaderKillBtn.TextSize = 11
HeaderKillBtn.Font = Enum.Font.GothamBold
HeaderKillBtn.Parent = MainFrame

local HeaderKillCorner = Instance.new("UICorner")
HeaderKillCorner.CornerRadius = UDim.new(0, 4)
HeaderKillCorner.Parent = HeaderKillBtn

addConnection(HeaderKillBtn.MouseButton1Click:Connect(panicKillAll))

local HintLabel = Instance.new("TextLabel")
HintLabel.Size = UDim2.new(1, -20, 0, 16)
HintLabel.Position = UDim2.new(0, 10, 0, 36)
HintLabel.BackgroundTransparency = 1
HintLabel.Text = "Prawy Ctrl: Menu | [End]: PANIC KILL (ZAMKNIJ)"
HintLabel.TextColor3 = Color3.fromRGB(140, 155, 175)
HintLabel.TextSize = 10
HintLabel.Font = Enum.Font.Gotham
HintLabel.TextXAlignment = Enum.TextXAlignment.Left
HintLabel.Parent = MainFrame

local StatsFrame = Instance.new("Frame")
StatsFrame.Size = UDim2.new(1, -20, 0, 120)
StatsFrame.Position = UDim2.new(0, 10, 0, 58)
StatsFrame.BackgroundColor3 = Color3.fromRGB(25, 31, 42)
StatsFrame.BorderSizePixel = 0
StatsFrame.Parent = MainFrame

local StatsCorner = Instance.new("UICorner")
StatsCorner.CornerRadius = UDim.new(0, 8)
StatsCorner.Parent = StatsFrame

local function createStatRow(yPos, labelText, defaultVal)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.40, 0, 0, 20)
    lbl.Position = UDim2.new(0, 8, 0, yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Color3.fromRGB(160, 175, 195)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = StatsFrame

    local val = Instance.new("TextLabel")
    val.Size = UDim2.new(0.58, 0, 0, 20)
    val.Position = UDim2.new(0.40, 0, 0, yPos)
    val.BackgroundTransparency = 1
    val.Text = defaultVal
    val.TextColor3 = Color3.fromRGB(255, 255, 255)
    val.TextSize = 11
    val.Font = Enum.Font.GothamBold
    val.TextXAlignment = Enum.TextXAlignment.Right
    val.Parent = StatsFrame

    return val
end

local StatusVal  = createStatRow(6, "Status:", "Czuwanie")
local TargetVal  = createStatRow(28, "Cel:", "Brak")
local ChoppedVal = createStatRow(50, "Ścięte drzewa:", "0")
local AxeVal     = createStatRow(72, "Siekiera:", "Sprawdzam...")
local BannedVal  = createStatRow(94, "Wykluczone:", "Spawn, Sakura, City, Steampunk, Nuclear, Desert")
BannedVal.TextSize = 9
BannedVal.TextColor3 = Color3.fromRGB(240, 100, 100)

local EquipAxeBtn = Instance.new("TextButton")
EquipAxeBtn.Size = UDim2.new(0.48, -14, 0, 32)
EquipAxeBtn.Position = UDim2.new(0, 12, 0, 186)
EquipAxeBtn.BackgroundColor3 = Color3.fromRGB(36, 120, 190)
EquipAxeBtn.BorderSizePixel = 0
EquipAxeBtn.Text = "🪓 WYCIĄGNIJ SIEKIERĘ"
EquipAxeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
EquipAxeBtn.TextSize = 11
EquipAxeBtn.Font = Enum.Font.GothamBold
EquipAxeBtn.Parent = MainFrame

local EqCorner = Instance.new("UICorner")
EqCorner.CornerRadius = UDim.new(0, 6)
EqCorner.Parent = EquipAxeBtn

addConnection(EquipAxeBtn.MouseButton1Click:Connect(function()
    EquipAxeBtn.Text = "Wyciągam..."
    equipSakuraAxe()
    task.wait(0.5)
    EquipAxeBtn.Text = "🪓 WYCIĄGNIJ SIEKIERĘ"
end))

ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0.52, -10, 0, 32)
ToggleBtn.Position = UDim2.new(0.48, 0, 0, 186)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(46, 170, 80)
ToggleBtn.BorderSizePixel = 0
ToggleBtn.Text = "AUTO FARM: WŁĄCZONY ✓"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.TextSize = 11
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Parent = MainFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 6)
ToggleCorner.Parent = ToggleBtn

addConnection(ToggleBtn.MouseButton1Click:Connect(function()
    Settings.AutoFarm = not Settings.AutoFarm
    if Settings.AutoFarm then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(46, 170, 80)
        ToggleBtn.Text = "AUTO FARM: WŁĄCZONY ✓"
        hookGameControllers()
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(190, 45, 45)
        ToggleBtn.Text = "AUTO FARM: WYŁĄCZONY"
        Stats.Status = "Zatrzymano"
    end
end))

local uiThread = task.spawn(function()
    while ScriptActive do
        if ScreenGui and ScreenGui.Parent then
            StatusVal.Text   = Stats.Status
            TargetVal.Text   = Stats.CurrentTarget
            ChoppedVal.Text  = tostring(Stats.TreesChopped)

            if isAxeEquipped() then
                AxeVal.Text = "Wyciągnięta (_axe) ✓"
                AxeVal.TextColor3 = Color3.fromRGB(80, 220, 120)
            else
                AxeVal.Text = "Schowana (wyciągam...) ⏳"
                AxeVal.TextColor3 = Color3.fromRGB(240, 180, 50)
            end
        else
            break
        end
        task.wait(0.2)
    end
end)
addThread(uiThread)

-- Obsługa klawiszy: Prawy CTRL (Menu) oraz END / Keypad 1 (Panic Button)
addConnection(UserInputService.InputBegan:Connect(function(input, gpe)
    if input.KeyCode == Enum.KeyCode.End or input.KeyCode == Enum.KeyCode.KeypadOne then
        panicKillAll()
        return
    end
    if not gpe then
        if input.KeyCode == Enum.KeyCode.RightControl then
            if MainFrame then
                MainFrame.Visible = not MainFrame.Visible
            end
        end
    end
end))

-- Dodatkowy strażnik klawisza End (ciągły polling co 50ms)
local keyGuardThread = task.spawn(function()
    while ScriptActive do
        pcall(function()
            if UserInputService:IsKeyDown(Enum.KeyCode.End) or UserInputService:IsKeyDown(Enum.KeyCode.KeypadOne) then
                panicKillAll()
            end
        end)
        task.wait(0.05)
    end
end)
addThread(keyGuardThread)

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "RCU Tree Farm (1.2s)",
        Text = "Wystartowano! Fazy: 1.2s, [End] lub [✕ KILL]: Zamknięcie.",
        Duration = 6
    })
end)
