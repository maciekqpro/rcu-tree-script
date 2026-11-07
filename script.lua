--[[
    🌲 REBIRTH CHAMPIONS ULTIMATE — AUTO TREE FARMER v8 (+ AUTO EGG 250M)
    ====================================================================
    GŁÓWNE FUNKCJE I NOWOŚCI:
      1. OKIENKO WYKLUCZANIA MAP (CZARNA LISTA KRAIN):
         - Zintegrowany, przejrzysty panel ze wszystkimi mapami (Spawn, Sakura, Farm,
           Desert, City, Steampunk, Nuclear, Kingdom, Atlantis, Winter, Magma itd.).
         - Każda zaznaczona mapa (czerwona z napisem [✕ OMIJAJ]) jest w 100% POMIJANA.
         - Możesz zaznaczyć 1, 2, 3 lub dowolną liczbę map — bot nie zetnie na nich ani jednego drzewa!
         - Przycisk [ODZNACZ WSZYSTKIE] pozwala zresetować wykluczenia 1 kliknięciem.
      2. KOMFORTOWY WIDOK 3. OSOBY (ZZA PLECÓW):
         - Kamera NIGDY nie skacze do oczu/głowy postaci!
         - Domyślny widok zza pleców (~7 studów za graczem) pokazuje całego awatara,
           machanie siekierą i pień drzewa.
         - Opcja przełączenia na całkowicie WOLNĄ KAMERĘ (Custom) w GUI!
      3. CAŁKOWITA ELIMINACJA GHOST TREES (RESPAWN 0.5 TRANSPARENCY):
         - Odradzające się drzewa z Transparency = 0.5 lub aktywnym Billboardem respawnu
           są natychmiast odrzucane. Bot bije tylko żywe drzewa o pełnym pniu!
      4. PRZENIKALNOŚĆ CIAŁA POSTACI (CanQuery = false):
         - Promienie kliknięć przenikają przez głowę, plecy i zwierzaki gracza.
      5. KROKI W PRZÓD (W) BEZ PRZERYWANIA BICIA:
         - Fazy 1.2s z płynnym krokiem CFrame i automatycznym dobijaniem twardych drzew.
      6. PANIC BUTTON POD [END] & [KEYPAD 1] ORAZ [✕ KILL] W GUI.
      7. PRAWY CTRL UKRYWA / POKAZUJE MENU.
    ====================================================================
]]

-- Zabij poprzednią instancję jeśli działa w tle
if getgenv and getgenv().RCU_PanicKill then
    pcall(getgenv().RCU_PanicKill)
end

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
    AutoFarm        = true,             -- Auto farm aktywny
    AutoEquipAxe    = true,             -- Auto-wyciąganie Sakura Axe
    AutoOpenEggs    = false,            -- Auto-otwieranie jajka 250M w tle (RE[3])
    EggHatchRate    = 0.65,             -- Co ile sekund otwierać jajka (0.65s = animacja 17 jajek)
    EggName         = "250M",           -- Nazwa jajka do otwierania na odległość
    AttackDistance  = 2.8,              -- Dystans podejścia do pnia (2.8 studa)
    HitRate         = 0.08,             -- Częstotliwość kliknięć w pętli
    PhaseDuration   = 1.2,              -- Czas trwania każdej fazy (1.2s)
    CameraMode      = "Free",           -- "ThirdPerson" (zza pleców) lub "Free" (wolna myszka)
    ExcludedMaps    = {},               -- Tabela wykluczonych map: { ["desert"] = true, ... }
}

local Stats = {
    TreesChopped    = 0,
    EggsOpened      = 0,
    CurrentTarget   = "Brak",
    Status          = "Inicjalizacja...",
    ExcludedText    = "Brak (rąbię wszystko)",
}

local skipTrees = {}
local lastEquipAttempt = 0

-- Usługi silnika Roblox
local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local CollectionService   = game:GetService("CollectionService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService    = game:GetService("UserInputService")
local StarterGui          = game:GetService("StarterGui")
local CoreGui             = game:GetService("CoreGui")

local LP = Players.LocalPlayer

-- ====================================================================
-- SYSTEM ZDALNEGO OTWIERANIA JAJEK 250M (RE[3] BEZ TELEPORTACJI I KLAWISZY)
-- ====================================================================
local _cachedEggRemote = nil

local function getEggRemote()
    if _cachedEggRemote and _cachedEggRemote.Parent then
        return _cachedEggRemote
    end
    pcall(function()
        local knitServices = ReplicatedStorage:FindFirstChild("Packages") 
            and ReplicatedStorage.Packages:FindFirstChild("Knit")
            and ReplicatedStorage.Packages.Knit:FindFirstChild("Services")
        if knitServices then
            for _, s in ipairs(knitServices:GetChildren()) do
                local rp = s:FindFirstChild("RP")
                if rp and rp:FindFirstChild("globalEgg") then
                    local re = s:FindFirstChild("RE")
                    if re then
                        local list = re:GetChildren()
                        if list[3] then
                            _cachedEggRemote = list[3]
                        end
                    end
                    break
                end
            end
        end
    end)
    return _cachedEggRemote
end

-- ====================================================================
-- 1. ROZPOZNAWANIE MAP I ODKRYWANIE KRAIN Z DRZEWAMI
-- ====================================================================
local function getTreeMapName(treeFolder)
    if not treeFolder then return "Inna" end

    -- 1. Sprawdź atrybut groupId
    local gid = treeFolder:GetAttribute("groupId")
    if gid and type(gid) == "string" and #gid > 0 then
        return gid:sub(1, 1):upper() .. gid:sub(2):lower()
    end

    -- 2. Sprawdź strukturę folderów w Workspace (np. Workspace.Game.Maps.W1.Spawn.Trees)
    local p = treeFolder.Parent
    while p and p ~= Workspace do
        local pName = p.Name
        if p.Parent and (p.Parent.Name == "Maps" or (p.Parent.Parent and p.Parent.Parent.Name == "Maps")) then
            if pName ~= "Trees" and pName ~= "W1" and pName ~= "W2" and pName ~= "W3" then
                return pName:sub(1, 1):upper() .. pName:sub(2):lower()
            end
        end
        p = p.Parent
    end

    -- 3. Fallback na zone/parent
    local zone = treeFolder.Parent and treeFolder.Parent.Parent
    if zone and zone:IsA("Instance") and zone.Name ~= "Workspace" and zone.Name ~= "Game" and zone.Name ~= "Maps" and zone.Name ~= "W1" and zone.Name ~= "W2" then
        return zone.Name
    end

    return "Inna"
end

-- Lista MAP Z DRZEWAMI w kolejnosci progresji na mapie gry
-- (tylko mapy na ktorych faktycznie rosna drzewa)
-- Lista TYLKO 15 MAP Z DRZEWAMI w ścisłej kolejności progresji:
local TREE_MAPS_ORDERED = {
    "Spawn", "Farm", "Desert", "Nuclear", "Atlantis", "Kingdom",
    "City", "Cave", "Volcano", "Heaven", "Magic", "Circus",
    "Jungle", "Steampunk", "Sakura"
}

local ALLOWED_MAPS_SET = {}
for _, m in ipairs(TREE_MAPS_ORDERED) do
    ALLOWED_MAPS_SET[m:lower()] = true
end

local function discoverAllMapsWithTrees()
    -- Zwraca TYLKO i WYŁĄCZNIE 15 wybranych map, zero innych
    return TREE_MAPS_ORDERED
end

-- ====================================================================
-- 2. CLIENT-SIDE HITBOX EXPANDER & PRZENIKANIE PROMIENI PRZEZ GRACZA
-- ====================================================================
local function expandTreeHitbox(treeFolder)
    if not treeFolder or not treeFolder.Parent then return end
    pcall(function()
        for _, desc in ipairs(treeFolder:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc.CanCollide = false
                local sz = desc.Size
                if sz.X < 26 or sz.Z < 26 then
                    desc.Size = Vector3.new(math.max(sz.X, 28), math.max(sz.Y, 28), math.max(sz.Z, 28))
                end
            end
        end
    end)
end

pcall(function()
    for _, t in ipairs(CollectionService:GetTagged("Tree")) do
        expandTreeHitbox(t)
    end
    addConnection(CollectionService:GetInstanceAddedSignal("Tree"):Connect(function(t)
        task.wait(0.1)
        expandTreeHitbox(t)
    end))
end)

local function disableCharacterRaycastBlocking()
    pcall(function()
        local char = LP.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanQuery = false
                end
            end
        end
    end)
end

local function restoreCharacterRaycastBlocking()
    pcall(function()
        local char = LP.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.CanQuery = true
                end
            end
        end
    end)
end

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
    return false
end

local function equipSakuraAxe()
    if isAxeEquipped() then return true end
    if tick() - lastEquipAttempt < 2.0 then return false end
    lastEquipAttempt = tick()

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
        task.wait(0.35)
    end

    -- Krok 2: Kliknij zakładkę "Items"
    local menus = mainUI and mainUI:FindFirstChild("Menus")
    local invMenu = menus and menus:FindFirstChild("InventoryFrame")
    local utility = invMenu and invMenu:FindFirstChild("Utility")
    local dispList = utility and utility:FindFirstChild("Displays") and utility.Displays:FindFirstChild("List")
    local itemsTab = dispList and dispList:FindFirstChild("Items") and dispList.Items:FindFirstChild("Click")

    if itemsTab then
        clickGuiBtn(itemsTab, false)
        task.wait(0.35)
    end

    -- Krok 3: Przewiń listę na sam dół
    local itemsDisp = invMenu and invMenu:FindFirstChild("Displays") and invMenu.Displays:FindFirstChild("Items")
    local list = itemsDisp and itemsDisp:FindFirstChild("List")
    local listHolder = list and list:FindFirstChild("Holder")
    if listHolder and listHolder:IsA("ScrollingFrame") then
        pcall(function()
            listHolder.CanvasPosition = Vector2.new(0, 99999)
        end)
        task.wait(0.25)
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
        task.wait(0.30)
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
-- 5. POZYCJA I STAN DRZEW (Z UWZGLĘDNIENIEM WYKLUCZEŃ MAP)
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

    -- 1. Sprawdź czy mapa należy do 15 dozwolonych krain i nie jest wykluczona
    local mMap = getTreeMapName(treeFolder):lower()
    if not ALLOWED_MAPS_SET[mMap] then
        return false
    end
    if Settings.ExcludedMaps[mMap] then
        return false
    end

    -- 2. Czarna lista (ścięte lub pominięte oporne drzewa)
    if skipTrees[treeFolder] and tick() < skipTrees[treeFolder] then
        return false
    end

    -- 3. Sprawdź czy silnik gry włączył Billboard respawnu
    local respawnGui = treeFolder:FindFirstChild("TreeRespawn", true)
    if respawnGui and respawnGui:IsA("BillboardGui") and respawnGui.Enabled then
        return false
    end

    -- 4. Sprawdź przezroczystość części (0.5 to martwe drzewo w respawnie)
    local hasRespawningPart = false
    local hasSolidPart = false

    for _, desc in ipairs(treeFolder:GetDescendants()) do
        if desc:IsA("BasePart") then
            if desc.Transparency >= 0.35 and desc.Transparency < 0.99 then
                hasRespawningPart = true
                break
            elseif desc.Transparency < 0.25 then
                hasSolidPart = true
            end
        end
    end

    if hasRespawningPart then
        return false
    end

    return hasSolidPart
end

-- ====================================================================
-- 6. POMOCNIK STANU HP DRZEWA Z UI
-- ====================================================================
local function getTreeHealthGui()
    local pg = LP:FindFirstChild("PlayerGui")
    local mainUI = pg and pg:FindFirstChild("MainUI")
    local hud = mainUI and mainUI:FindFirstChild("HUD")
    local bars = hud and hud:FindFirstChild("Bars")
    local bottom = bars and bars:FindFirstChild("Bottom")
    return bottom and bottom:FindFirstChild("TreeHealth")
end

local function isTreeBeingDamaged()
    local th = getTreeHealthGui()
    return (th and th.Visible == true)
end

-- ====================================================================
-- 7. WYBÓR NAJBLIŻSZEGO DOSTĘPNEGO DRZEWA (TYLKO NIEWYKLUCZONE MAPY)
-- ====================================================================
local function getNearestAliveTree()
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local allTrees = CollectionService:GetTagged("Tree")
    local nearest = nil
    local minDist = math.huge

    for _, t in ipairs(allTrees) do
        local mMap = getTreeMapName(t):lower()
        -- Pomijaj drzewa spoza 15 map lub zaznaczone jako wykluczone
        if ALLOWED_MAPS_SET[mMap] and not Settings.ExcludedMaps[mMap] and isTreeAlive(t) then
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
-- 8. NATURALNY WIDOK 3. OSOBY (ZZA PLECÓW) I TELEPORTACJA
-- ====================================================================
local function lockCameraToTree(treeFolder)
    if Settings.CameraMode == "Free" then
        return
    end

    local primPos = getTreePosition(treeFolder)
    if not primPos then return end

    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local cam = Workspace.CurrentCamera
    if not cam then return end

    -- Wygodny widok zza pleców postaci (~7 studów z tyłu, lekko z góry)
    local fwd = hrp.CFrame.LookVector
    local desiredDist = 7.0

    -- Sprawdź czy za plecami nie ma ściany
    local origin = hrp.Position + Vector3.new(0, 2.8, 0)
    local backDir = -(fwd * desiredDist)
    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = { char, treeFolder }
    rp.FilterType = Enum.RaycastFilterType.Exclude

    local wallCheck = Workspace:Raycast(origin, backDir, rp)
    local actualDist = wallCheck and math.max(2.5, (wallCheck.Position - origin).Magnitude - 0.5) or desiredDist

    local camPos = origin - (fwd * actualDist)
    local targetPos = Vector3.new(primPos.X, primPos.Y + 1.2, primPos.Z)

    pcall(function()
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = CFrame.lookAt(camPos, targetPos)
    end)
end

local function restoreCamera()
    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam and cam.CameraType ~= Enum.CameraType.Custom then
            cam.CameraType = Enum.CameraType.Custom
        end
    end)
end

local function teleportToTree(treeFolder)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    expandTreeHitbox(treeFolder)
    disableCharacterRaycastBlocking()

    local primPos = getTreePosition(treeFolder)
    if not primPos then return false end

    local hrpPos = hrp.Position

    local dir = Vector3.new(hrpPos.X - primPos.X, 0, hrpPos.Z - primPos.Z)
    if dir.Magnitude < 0.1 then
        dir = Vector3.new(1, 0, 0)
    else
        dir = dir.Unit
    end

    -- Dystans 2.8 studa od pnia
    local targetX = primPos.X + (dir.X * Settings.AttackDistance)
    local targetZ = primPos.Z + (dir.Z * Settings.AttackDistance)

    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = { char, treeFolder }
    rp.FilterType = Enum.RaycastFilterType.Exclude

    local treeGround = Workspace:Raycast(Vector3.new(primPos.X, primPos.Y + 15, primPos.Z), Vector3.new(0, -60, 0), rp)
    local baseGroundY = treeGround and (treeGround.Position.Y + 3.0) or (primPos.Y - 4.5)

    local spotGround = Workspace:Raycast(Vector3.new(targetX, primPos.Y + 15, targetZ), Vector3.new(0, -60, 0), rp)
    if not spotGround and treeGround then
        targetX = primPos.X - (dir.X * Settings.AttackDistance)
        targetZ = primPos.Z - (dir.Z * Settings.AttackDistance)
        spotGround = Workspace:Raycast(Vector3.new(targetX, primPos.Y + 15, targetZ), Vector3.new(0, -60, 0), rp)
    end

    local targetY = spotGround and (spotGround.Position.Y + 3.0) or baseGroundY

    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    hrp.CFrame = CFrame.lookAt(Vector3.new(targetX, targetY, targetZ), Vector3.new(primPos.X, targetY, primPos.Z))

    lockCameraToTree(treeFolder)
    task.wait(0.06)
    return true
end

-- ====================================================================
-- 9. KROK W PRZÓD BEZ PRZERYWANIA BICIA
-- ====================================================================
local function stepForwardTowardsTree(treeFolder, stepDistance)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local primPos = getTreePosition(treeFolder)
    if not primPos then return end

    local fwd = Vector3.new(primPos.X - hrp.Position.X, 0, primPos.Z - hrp.Position.Z)
    if fwd.Magnitude > 0.1 then
        fwd = fwd.Unit
    else
        fwd = hrp.CFrame.LookVector
    end

    hrp.CFrame = CFrame.lookAt(hrp.Position + (fwd * stepDistance), Vector3.new(primPos.X, hrp.Position.Y, primPos.Z))
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    lockCameraToTree(treeFolder)
    task.wait(0.04)
end

-- ====================================================================
-- SYSTEM ANTYZAKŁÓCEŃ VIM: ŚCIEŻKI KLIKNIĘĆ POZA GUI (CIĄGŁE BICIE)
-- ====================================================================
local _pauseVimUntil = 0      -- Timestamp do którego VIM ustępuje miejsca kliknięciu gracza
local _sendingVim    = false  -- True gdy bot właśnie wysyła VIM click

-- Sprawdza czy dany punkt ekranu leży na GUI bota
local function isOverOurGui(cx, cy)
    if MainFrame and MainFrame.Visible then
        local pos = MainFrame.AbsolutePosition
        local sz = MainFrame.AbsoluteSize
        if cx >= (pos.X - 5) and cx <= (pos.X + sz.X + 5) and cy >= (pos.Y - 5) and cy <= (pos.Y + sz.Y + 5) then
            return true
        end
    end
    return false
end

-- Sprawdza czy dany punkt ekranu trafia w interaktywny przycisk gry lub otwarte menu w Menus
local function isInteractiveGuiAtPos(cx, cy)
    local ok, res = pcall(function()
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg or not pg.GetGuiObjectsAtPosition then return false end
        local objs = pg:GetGuiObjectsAtPosition(cx, cy)
        if not objs then return false end
        for _, obj in ipairs(objs) do
            if obj:IsA("GuiButton") and obj.Visible and obj.Active ~= false then
                return true
            end
            if obj:IsA("TextBox") and obj.Visible then
                return true
            end
            if obj:IsA("ScrollingFrame") and obj.Visible then
                return true
            end
            local p = obj
            while p and p ~= pg do
                if p.Name == "Menus" and obj.Visible and (obj:IsA("GuiButton") or (obj:IsA("Frame") and obj.BackgroundTransparency < 0.95)) then
                    return true
                end
                p = p.Parent
            end
        end
        return false
    end)
    return ok and res
end

-- Znajduje czysty punkt na ekranie, który trafia w pień drzewa i omija wszelkie GUI
local function getCleanClickPoint(treeFolder)
    local cam = Workspace.CurrentCamera
    if not cam then return 120, 250 end
    local vp = cam.ViewportSize

    -- 1. Spróbuj lewą lub górną część pnia drzewa w projekcji 3D
    if treeFolder then
        local pPos = getTreePosition(treeFolder)
        if pPos then
            local offsets = {
                Vector3.new(-4, 0, 0),
                Vector3.new(0, 5, 0),
                Vector3.new(4, 0, 0),
                Vector3.new(-6, 2, 0),
            }
            for _, off in ipairs(offsets) do
                local sPos, onScreen = cam:WorldToViewportPoint(pPos + off)
                if onScreen and not isInteractiveGuiAtPos(sPos.X, sPos.Y) and not isOverOurGui(sPos.X, sPos.Y) then
                    return sPos.X, sPos.Y
                end
            end
        end
    end

    -- 2. Lista bezpiecznych współrzędnych 2D (lewa strona i góra ekranu - z dala od menu gry i GUI bota)
    local screenCandidates = {
        Vector2.new(vp.X * 0.12, vp.Y * 0.50),
        Vector2.new(vp.X * 0.15, vp.Y * 0.35),
        Vector2.new(vp.X * 0.15, vp.Y * 0.65),
        Vector2.new(vp.X * 0.50, vp.Y * 0.12),
        Vector2.new(vp.X * 0.08, vp.Y * 0.50),
    }

    for _, pt in ipairs(screenCandidates) do
        if not isInteractiveGuiAtPos(pt.X, pt.Y) and not isOverOurGui(pt.X, pt.Y) then
            return pt.X, pt.Y
        end
    end

    return vp.X * 0.10, vp.Y * 0.50
end

-- Bezpieczny VIM click:
-- Zapewnia ciągłe bicie drzewa, przekierowując kliknięcie poza obszary GUI
local function safeVimClick(cx, cy, treeFolder)
    -- Jeśli gracz właśnie kliknął prawdziwą myszką, daj 120ms na rejestrację jego kliku w GUI
    if tick() < _pauseVimUntil then return end

    -- Upewnij się, że punkt uderzenia leży w czystym obszarze 3D (omija menu gry i GUI bota)
    if isInteractiveGuiAtPos(cx, cy) or isOverOurGui(cx, cy) then
        cx, cy = getCleanClickPoint(treeFolder)
    end

    _sendingVim = true
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true,  game, 1)
        task.wait(0.012)
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
    end)
    _sendingVim = false
end

-- ====================================================================
-- 10. CYKL BICIA
-- ====================================================================
local function performHitCycle(treeFolder, durationSec)
    local primPos = getTreePosition(treeFolder)
    if not primPos then return false end

    if not isTreeAlive(treeFolder) then
        return false
    end

    expandTreeHitbox(treeFolder)
    disableCharacterRaycastBlocking()

    local start = tick()
    local cam = Workspace.CurrentCamera

    while (tick() - start) < durationSec do
        if not ScriptActive or not Settings.AutoFarm then
            restoreCamera()
            return false
        end

        -- Przerwij jeśli mapa została wykluczona w trakcie bicia
        local curMap = getTreeMapName(treeFolder):lower()
        if Settings.ExcludedMaps[curMap] then
            restoreCamera()
            return false
        end

        -- Sukces jeśli drzewo padło
        if not isTreeAlive(treeFolder) then
            restoreCamera()
            return true
        end

        if Settings.CameraMode == "ThirdPerson" then
            lockCameraToTree(treeFolder)
        end

        -- Oblicz pozycje klikniecia
        local vp = cam.ViewportSize
        local clickX, clickY
        if Settings.CameraMode == "Free" then
            local sPos, onScreen = cam:WorldToViewportPoint(primPos)
            clickX = onScreen and sPos.X or (vp.X / 2)
            clickY = onScreen and sPos.Y or (vp.Y / 2)
        else
            clickX = vp.X / 2
            clickY = vp.Y / 2
        end

        -- Przekieruj kliknięcie na czysty punkt jeśli cel jest przysłonięty przez GUI
        if isInteractiveGuiAtPos(clickX, clickY) or isOverOurGui(clickX, clickY) then
            clickX, clickY = getCleanClickPoint(treeFolder)
        end

        safeVimClick(clickX, clickY, treeFolder)

        task.wait(Settings.HitRate)
    end

    restoreCamera()
    return not isTreeAlive(treeFolder)
end

local function chopTargetTreeWithSteps(treeFolder)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end

    local primPos = getTreePosition(treeFolder)
    local dist = primPos and math.floor((hrp.Position - primPos).Magnitude) or 0
    local mMap = getTreeMapName(treeFolder)
    Stats.CurrentTarget = string.format("%s [%s] (%dm)", treeFolder.Name, mMap, dist)

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

    -- FAZA 2: Pierwszy krok w przód (0.6 studa) + 1.2s
    Stats.Status = "Krok w przód -> Faza 2 (1.2s)..."
    stepForwardTowardsTree(treeFolder, 0.6)
    dead = performHitCycle(treeFolder, Settings.PhaseDuration)
    if dead or not Settings.AutoFarm or not ScriptActive then
        if dead then
            skipTrees[treeFolder] = tick() + 15
            Stats.TreesChopped = Stats.TreesChopped + 1
            Stats.Status = "Ścięto po kroku!"
            task.wait(0.05)
            return true
        end
        return false
    end

    -- FAZA 3: Drugi krok w przód (0.6 studa) + 1.2s
    Stats.Status = "Drugi krok w przód -> Faza 3 (1.2s)..."
    stepForwardTowardsTree(treeFolder, 0.6)
    dead = performHitCycle(treeFolder, Settings.PhaseDuration)
    if dead or not Settings.AutoFarm or not ScriptActive then
        if dead then
            skipTrees[treeFolder] = tick() + 15
            Stats.TreesChopped = Stats.TreesChopped + 1
            Stats.Status = "Ścięto po 2. kroku!"
            task.wait(0.05)
            return true
        end
        return false
    end

    -- FAZA 4: Dobijanie twardych drzew o dużym HP
    if isTreeBeingDamaged() and isTreeAlive(treeFolder) then
        Stats.Status = "Twarde drzewo (duże HP) - dobijam..."
        dead = performHitCycle(treeFolder, 6.0)
        if dead then
            skipTrees[treeFolder] = tick() + 15
            Stats.TreesChopped = Stats.TreesChopped + 1
            Stats.Status = "Dobito twarde drzewo!"
            task.wait(0.05)
            return true
        end
    end

    -- FAZA 5: Oporne drzewo -> 60s ignorowania
    Stats.Status = "Oporne drzewo! Ignoruję na 60s..."
    skipTrees[treeFolder] = tick() + 60
    task.wait(0.05)
    return false
end

-- ====================================================================
-- 11. PANIC KILL I ZARZĄDZANIE PROCESAMI
-- ====================================================================
local ToggleBtn = nil
local ScreenGui = nil

local function purgeAllGuis()
    local names = {"RCU_TreeFarmUI", "RCU_TreeTesterUI"}
    for _, name in ipairs(names) do
        pcall(function()
            if gethui then
                for _, c in ipairs(gethui():GetChildren()) do
                    if c.Name == name then c:Destroy() end
                end
            end
        end)
        pcall(function()
            if CoreGui then
                for _, c in ipairs(CoreGui:GetChildren()) do
                    if c.Name == name then c:Destroy() end
                end
            end
        end)
        pcall(function()
            local pg = LP:FindFirstChild("PlayerGui")
            if pg then
                for _, c in ipairs(pg:GetChildren()) do
                    if c.Name == name then c:Destroy() end
                end
            end
        end)
    end
end

local function panicKillAll()
    ScriptActive = false
    Settings.AutoFarm = false

    restoreCamera()
    restoreCharacterRaycastBlocking()

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

    for _, t in ipairs(ScriptThreads) do
        pcall(function()
            if typeof(t) == "thread" then
                task.cancel(t)
            end
        end)
    end
    table.clear(ScriptThreads)

    for _, conn in ipairs(ScriptConnections) do
        pcall(function()
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end)
    end
    table.clear(ScriptConnections)

    purgeAllGuis()

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "RCU Tree Farm",
            Text = "[PANIC KILL] Zatrzymano wszystkie wątki i usunięto skrypt!",
            Duration = 5,
        })
    end)
end

if getgenv then
    getgenv().RCU_PanicKill = panicKillAll
end

-- ====================================================================
-- 12. INTERFEJS UŻYTKOWNIKA (GUI Z PANELEM WYKLUCZANIA MAP)
-- ====================================================================
purgeAllGuis()

ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RCU_TreeFarmUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true  -- Zapobiega "przebijaniu" klikniec bota przez GUI

local uiParent = (gethui and gethui()) or CoreGui or LP:WaitForChild("PlayerGui")
ScreenGui.Parent = uiParent

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 290, 0, 568)
MainFrame.Position = UDim2.new(1, -305, 0, 35)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(55, 65, 85)
MainStroke.Thickness = 1.5
MainStroke.Parent = MainFrame

-- Pasek tytułowy
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 36)
Header.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -75, 1, 0)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.Text = "🌲 RCU WOODCUTTER"
Title.TextColor3 = Color3.fromRGB(255, 215, 0)
Title.TextSize = 12
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent = Header

local KillBtn = Instance.new("TextButton")
KillBtn.Size = UDim2.new(0, 60, 0, 24)
KillBtn.Position = UDim2.new(1, -68, 0, 6)
KillBtn.Text = "✕ KILL"
KillBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
KillBtn.TextSize = 10
KillBtn.Font = Enum.Font.GothamBold
KillBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
KillBtn.BorderSizePixel = 0
KillBtn.Parent = Header

local KillCorner = Instance.new("UICorner")
KillCorner.CornerRadius = UDim.new(0, 5)
KillCorner.Parent = KillBtn

KillBtn.MouseButton1Click:Connect(panicKillAll)

-- Wiersz Statusu
local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size = UDim2.new(1, -20, 0, 18)
StatusLbl.Position = UDim2.new(0, 10, 0, 42)
StatusLbl.Text = "Status: Inicjalizacja..."
StatusLbl.TextColor3 = Color3.fromRGB(180, 220, 255)
StatusLbl.TextSize = 10
StatusLbl.Font = Enum.Font.GothamMedium
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.BackgroundTransparency = 1
StatusLbl.Parent = MainFrame

-- Wiersz Celu
local TargetLbl = Instance.new("TextLabel")
TargetLbl.Size = UDim2.new(1, -20, 0, 18)
TargetLbl.Position = UDim2.new(0, 10, 0, 60)
TargetLbl.Text = "Cel: Brak"
TargetLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
TargetLbl.TextSize = 10
TargetLbl.Font = Enum.Font.Gotham
TargetLbl.TextXAlignment = Enum.TextXAlignment.Left
TargetLbl.BackgroundTransparency = 1
TargetLbl.Parent = MainFrame

-- Wiersz Ściętych Drzew i Otwartych Jajek
local ChoppedLbl = Instance.new("TextLabel")
ChoppedLbl.Size = UDim2.new(0.5, -10, 0, 18)
ChoppedLbl.Position = UDim2.new(0, 10, 0, 78)
ChoppedLbl.Text = "Ścięte: 0"
ChoppedLbl.TextColor3 = Color3.fromRGB(100, 255, 120)
ChoppedLbl.TextSize = 10
ChoppedLbl.Font = Enum.Font.GothamBold
ChoppedLbl.TextXAlignment = Enum.TextXAlignment.Left
ChoppedLbl.BackgroundTransparency = 1
ChoppedLbl.Parent = MainFrame

local EggsLbl = Instance.new("TextLabel")
EggsLbl.Size = UDim2.new(0.5, -10, 0, 18)
EggsLbl.Position = UDim2.new(0.5, 5, 0, 78)
EggsLbl.Text = "Jajka 250M: 0"
EggsLbl.TextColor3 = Color3.fromRGB(255, 215, 120)
EggsLbl.TextSize = 10
EggsLbl.Font = Enum.Font.GothamBold
EggsLbl.TextXAlignment = Enum.TextXAlignment.Left
EggsLbl.BackgroundTransparency = 1
EggsLbl.Parent = MainFrame

-- Wiersz Wykluczonych Map
local ExcludedLbl = Instance.new("TextLabel")
ExcludedLbl.Size = UDim2.new(1, -20, 0, 18)
ExcludedLbl.Position = UDim2.new(0, 10, 0, 96)
ExcludedLbl.Text = "Wykluczone: Brak (rąbię wszystko)"
ExcludedLbl.TextColor3 = Color3.fromRGB(150, 220, 160)
ExcludedLbl.TextSize = 9
ExcludedLbl.Font = Enum.Font.GothamBold
ExcludedLbl.TextXAlignment = Enum.TextXAlignment.Left
ExcludedLbl.BackgroundTransparency = 1
ExcludedLbl.Parent = MainFrame

-- Przycisk Auto Farm
local FarmBtn = Instance.new("TextButton")
FarmBtn.Size = UDim2.new(1, -20, 0, 28)
FarmBtn.Position = UDim2.new(0, 10, 0, 116)
FarmBtn.Text = "AUTO FARM: WŁĄCZONY"
FarmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FarmBtn.TextSize = 11
FarmBtn.Font = Enum.Font.GothamBold
FarmBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 60)
FarmBtn.BorderSizePixel = 0
FarmBtn.Parent = MainFrame

local FarmCorner = Instance.new("UICorner")
FarmCorner.CornerRadius = UDim.new(0, 6)
FarmCorner.Parent = FarmBtn

FarmBtn.MouseButton1Click:Connect(function()
    Settings.AutoFarm = not Settings.AutoFarm
    if Settings.AutoFarm then
        FarmBtn.Text = "AUTO FARM: WŁĄCZONY"
        FarmBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 60)
    else
        FarmBtn.Text = "AUTO FARM: WYŁĄCZONY"
        FarmBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
        restoreCamera()
    end
end)

-- Przycisk Wyciągnięcia Siekiery
local AxeBtn = Instance.new("TextButton")
AxeBtn.Size = UDim2.new(0.48, -10, 0, 24)
AxeBtn.Position = UDim2.new(0, 10, 0, 148)
AxeBtn.Text = "🪓 EKWIPUJ AXE"
AxeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AxeBtn.TextSize = 9
AxeBtn.Font = Enum.Font.GothamBold
AxeBtn.BackgroundColor3 = Color3.fromRGB(160, 90, 30)
AxeBtn.BorderSizePixel = 0
AxeBtn.Parent = MainFrame

local AxeCorner = Instance.new("UICorner")
AxeCorner.CornerRadius = UDim.new(0, 6)
AxeCorner.Parent = AxeBtn

AxeBtn.MouseButton1Click:Connect(function()
    Stats.Status = "Wyciągam Sakura Axe..."
    task.spawn(equipSakuraAxe)
end)

-- Przycisk Trybu Kamery (3rd Person vs Wolna)
local CamBtn = Instance.new("TextButton")
CamBtn.Size = UDim2.new(0.52, -10, 0, 24)
CamBtn.Position = UDim2.new(0.48, 5, 0, 148)
CamBtn.Text = "KAMERA: WOLNA"
CamBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CamBtn.TextSize = 9
CamBtn.Font = Enum.Font.GothamBold
CamBtn.BackgroundColor3 = Color3.fromRGB(110, 60, 150)
CamBtn.BorderSizePixel = 0
CamBtn.Parent = MainFrame

local CamCorner = Instance.new("UICorner")
CamCorner.CornerRadius = UDim.new(0, 6)
CamCorner.Parent = CamBtn

CamBtn.MouseButton1Click:Connect(function()
    if Settings.CameraMode == "ThirdPerson" then
        Settings.CameraMode = "Free"
        CamBtn.Text = "KAMERA: WOLNA"
        CamBtn.BackgroundColor3 = Color3.fromRGB(110, 60, 150)
        restoreCamera()
    else
        Settings.CameraMode = "Free"
        CamBtn.Text = "KAMERA: WOLNA"
        CamBtn.BackgroundColor3 = Color3.fromRGB(110, 60, 150)
    end
end)

-- Przycisk Auto-Otwierania Jajka 250M (Zdalny RE[3])
local EggBtn = Instance.new("TextButton")
EggBtn.Size = UDim2.new(1, -20, 0, 24)
EggBtn.Position = UDim2.new(0, 10, 0, 176)
EggBtn.Text = "🥚 AUTO EGG 250M: WYŁĄCZONY"
EggBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
EggBtn.TextSize = 10
EggBtn.Font = Enum.Font.GothamBold
EggBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
EggBtn.BorderSizePixel = 0
EggBtn.Parent = MainFrame

local EggCorner = Instance.new("UICorner")
EggCorner.CornerRadius = UDim.new(0, 6)
EggCorner.Parent = EggBtn

EggBtn.MouseButton1Click:Connect(function()
    Settings.AutoOpenEggs = not Settings.AutoOpenEggs
    if Settings.AutoOpenEggs then
        EggBtn.Text = "🥚 AUTO EGG 250M: WŁĄCZONY (17x)"
        EggBtn.BackgroundColor3 = Color3.fromRGB(35, 130, 55)
    else
        EggBtn.Text = "🥚 AUTO EGG 250M: WYŁĄCZONY"
        EggBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
    end
end)

-- Przycisk Rozwijania / Zwijania Panelu Map
local isMapPanelOpen = true
local MapToggleBtn = Instance.new("TextButton")
MapToggleBtn.Size = UDim2.new(1, -20, 0, 24)
MapToggleBtn.Position = UDim2.new(0, 10, 0, 204)
MapToggleBtn.Text = "🗺️ WYKLUCZONE MAPY [▲ ZWIŃ]"
MapToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MapToggleBtn.TextSize = 9
MapToggleBtn.Font = Enum.Font.GothamBold
MapToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 60, 80)
MapToggleBtn.BorderSizePixel = 0
MapToggleBtn.Parent = MainFrame

local MapToggleCorner = Instance.new("UICorner")
MapToggleCorner.CornerRadius = UDim.new(0, 6)
MapToggleCorner.Parent = MapToggleBtn

-- ====================================================================
-- PANEL WYKLUCZANIA MAP (SCROLLING LISTA)
-- ====================================================================
local MapPanel = Instance.new("Frame")
MapPanel.Name = "MapPanel"
MapPanel.Size = UDim2.new(1, -20, 0, 300)
MapPanel.Position = UDim2.new(0, 10, 0, 232)
MapPanel.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
MapPanel.BorderSizePixel = 0
MapPanel.Parent = MainFrame

local MapPanelCorner = Instance.new("UICorner")
MapPanelCorner.CornerRadius = UDim.new(0, 8)
MapPanelCorner.Parent = MapPanel

local MapPanelHeader = Instance.new("TextLabel")
MapPanelHeader.Size = UDim2.new(1, -10, 0, 24)
MapPanelHeader.Position = UDim2.new(0, 8, 0, 2)
MapPanelHeader.BackgroundTransparency = 1
MapPanelHeader.Text = "Zaznacz mapy do ominięcia:"
MapPanelHeader.TextColor3 = Color3.fromRGB(180, 195, 215)
MapPanelHeader.TextSize = 10
MapPanelHeader.Font = Enum.Font.GothamBold
MapPanelHeader.TextXAlignment = Enum.TextXAlignment.Left
MapPanelHeader.Parent = MapPanel

-- Wiersz przyciskow: WLACZ WSZYSTKIE / WYLACZ WSZYSTKIE / RESET
local BtnRow = Instance.new("Frame")
BtnRow.Size = UDim2.new(1, -8, 0, 24)
BtnRow.Position = UDim2.new(0, 4, 0, 28)
BtnRow.BackgroundTransparency = 1
BtnRow.Parent = MapPanel

local EnableAllBtn = Instance.new("TextButton")
EnableAllBtn.Size = UDim2.new(0.42, -2, 1, 0)
EnableAllBtn.Position = UDim2.new(0, 0, 0, 0)
EnableAllBtn.Text = "✅ WLACZ WSZYSTKIE"
EnableAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
EnableAllBtn.TextSize = 7
EnableAllBtn.Font = Enum.Font.GothamBold
EnableAllBtn.BackgroundColor3 = Color3.fromRGB(35, 110, 55)
EnableAllBtn.BorderSizePixel = 0
EnableAllBtn.Parent = BtnRow

local EACorner = Instance.new("UICorner")
EACorner.CornerRadius = UDim.new(0, 4)
EACorner.Parent = EnableAllBtn

local DisableAllBtn = Instance.new("TextButton")
DisableAllBtn.Size = UDim2.new(0.42, -2, 1, 0)
DisableAllBtn.Position = UDim2.new(0.42, 2, 0, 0)
DisableAllBtn.Text = "✖ WYLACZ WSZYSTKIE"
DisableAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DisableAllBtn.TextSize = 7
DisableAllBtn.Font = Enum.Font.GothamBold
DisableAllBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
DisableAllBtn.BorderSizePixel = 0
DisableAllBtn.Parent = BtnRow

local DACorner = Instance.new("UICorner")
DACorner.CornerRadius = UDim.new(0, 4)
DACorner.Parent = DisableAllBtn

local ClearExclusionsBtn = Instance.new("TextButton")
ClearExclusionsBtn.Size = UDim2.new(0.16, -2, 1, 0)
ClearExclusionsBtn.Position = UDim2.new(0.84, 2, 0, 0)
ClearExclusionsBtn.Text = "RESET"
ClearExclusionsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearExclusionsBtn.TextSize = 7
ClearExclusionsBtn.Font = Enum.Font.GothamBold
ClearExclusionsBtn.BackgroundColor3 = Color3.fromRGB(60, 70, 90)
ClearExclusionsBtn.BorderSizePixel = 0
ClearExclusionsBtn.Parent = BtnRow

local ClearCorner = Instance.new("UICorner")
ClearCorner.CornerRadius = UDim.new(0, 4)
ClearCorner.Parent = ClearExclusionsBtn

local MapScroll = Instance.new("ScrollingFrame")
MapScroll.Size = UDim2.new(1, -8, 1, -58)
MapScroll.Position = UDim2.new(0, 4, 0, 56)
MapScroll.BackgroundTransparency = 1
MapScroll.BorderSizePixel = 0
MapScroll.ScrollBarThickness = 5
MapScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 100, 130)
MapScroll.Parent = MapPanel

local MapListLayout = Instance.new("UIListLayout")
MapListLayout.SortOrder = Enum.SortOrder.LayoutOrder
MapListLayout.Padding = UDim.new(0, 3)
MapListLayout.Parent = MapScroll

local function updateExcludedSummary()
    local list = {}
    for k, v in pairs(Settings.ExcludedMaps) do
        if v then
            table.insert(list, k:sub(1, 1):upper() .. k:sub(2):lower())
        end
    end
    table.sort(list)
    if #list == 0 then
        ExcludedLbl.Text = "Wykluczone: Brak (rąbię wszystko)"
        ExcludedLbl.TextColor3 = Color3.fromRGB(150, 220, 160)
    else
        ExcludedLbl.Text = "Wykluczone: " .. table.concat(list, ", ") .. string.format(" (%d)", #list)
        ExcludedLbl.TextColor3 = Color3.fromRGB(255, 120, 120)
    end
end

local function populateMapList()
    for _, c in ipairs(MapScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    local maps = discoverAllMapsWithTrees()
    local rowHeight = 26
    MapScroll.CanvasSize = UDim2.new(0, 0, 0, #maps * (rowHeight + 3) + 8)

    for idx, mapName in ipairs(maps) do
        local lk = mapName:lower()
        local isExcluded = (Settings.ExcludedMaps[lk] == true)

        local row = Instance.new("Frame")
        row.Name = mapName
        row.LayoutOrder = idx
        row.Size = UDim2.new(1, -6, 0, rowHeight)
        row.BackgroundColor3 = isExcluded and Color3.fromRGB(48, 24, 28) or Color3.fromRGB(28, 33, 44)
        row.BorderSizePixel = 0
        row.Parent = MapScroll

        local rCorner = Instance.new("UICorner")
        rCorner.CornerRadius = UDim.new(0, 5)
        rCorner.Parent = row

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -95, 1, 0)
        nameLabel.Position = UDim2.new(0, 8, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = "🗺️ " .. mapName
        nameLabel.TextColor3 = isExcluded and Color3.fromRGB(255, 130, 130) or Color3.fromRGB(240, 245, 255)
        nameLabel.TextSize = 11
        nameLabel.Font = Enum.Font.GothamMedium
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row

        local toggleMapBtn = Instance.new("TextButton")
        toggleMapBtn.Size = UDim2.new(0, 80, 0, 20)
        toggleMapBtn.Position = UDim2.new(1, -85, 0.5, -10)
        toggleMapBtn.BackgroundColor3 = isExcluded and Color3.fromRGB(180, 45, 45) or Color3.fromRGB(40, 120, 60)
        toggleMapBtn.BorderSizePixel = 0
        toggleMapBtn.Text = isExcluded and "✕ OMIJAJ" or "RĄB (ON)"
        toggleMapBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        toggleMapBtn.TextSize = 9
        toggleMapBtn.Font = Enum.Font.GothamBold
        toggleMapBtn.Parent = row

        local cCorner = Instance.new("UICorner")
        cCorner.CornerRadius = UDim.new(0, 4)
        cCorner.Parent = toggleMapBtn

        toggleMapBtn.MouseButton1Click:Connect(function()
            Settings.ExcludedMaps[lk] = not Settings.ExcludedMaps[lk]
            if not Settings.ExcludedMaps[lk] then
                Settings.ExcludedMaps[lk] = nil
            end
            local nowExcluded = (Settings.ExcludedMaps[lk] == true)
            toggleMapBtn.Text = nowExcluded and "✕ OMIJAJ" or "RĄB (ON)"
            toggleMapBtn.BackgroundColor3 = nowExcluded and Color3.fromRGB(180, 45, 45) or Color3.fromRGB(40, 120, 60)
            row.BackgroundColor3 = nowExcluded and Color3.fromRGB(48, 24, 28) or Color3.fromRGB(28, 33, 44)
            nameLabel.TextColor3 = nowExcluded and Color3.fromRGB(255, 130, 130) or Color3.fromRGB(240, 245, 255)
            updateExcludedSummary()
        end)
    end

    updateExcludedSummary()
end

populateMapList()

ClearExclusionsBtn.MouseButton1Click:Connect(function()
    table.clear(Settings.ExcludedMaps)
    populateMapList()
end)

EnableAllBtn.MouseButton1Click:Connect(function()
    table.clear(Settings.ExcludedMaps)
    populateMapList()
end)

DisableAllBtn.MouseButton1Click:Connect(function()
    table.clear(Settings.ExcludedMaps)
    local maps = discoverAllMapsWithTrees()
    for _, mapName in ipairs(maps) do
        Settings.ExcludedMaps[mapName:lower()] = true
    end
    populateMapList()
end)

MapToggleBtn.MouseButton1Click:Connect(function()
    isMapPanelOpen = not isMapPanelOpen
    if isMapPanelOpen then
        populateMapList()
        MainFrame.Size = UDim2.new(0, 290, 0, 568)
        MapPanel.Visible = true
        MapToggleBtn.Text = "🗺️ WYKLUCZONE MAPY [▲ ZWIŃ]"
        MapToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 60, 80)
    else
        MainFrame.Size = UDim2.new(0, 290, 0, 263)
        MapPanel.Visible = false
        MapToggleBtn.Text = "🗺️ WYKLUCZ MAPY [▼ ROZWIŃ]"
        MapToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 48, 65)
    end
end)

-- Stopka
local Footer = Instance.new("TextLabel")
Footer.Size = UDim2.new(1, -20, 0, 20)
Footer.Position = UDim2.new(0, 10, 1, -24)
Footer.Text = "[End] = Panic Kill | [Right Ctrl] = Menu"
Footer.TextColor3 = Color3.fromRGB(130, 135, 150)
Footer.TextSize = 9
Footer.Font = Enum.Font.Gotham
Footer.BackgroundTransparency = 1
Footer.Parent = MainFrame

-- Toggle GUI
addConnection(UserInputService.InputBegan:Connect(function(input, gpe)
    -- Wykryj prawdziwe kliknięcie myszką gracza:
    -- Dajemy 120ms na czystą rejestrację kliku w GUI, po czym bot natychmiast bije dalej
    if input.UserInputType == Enum.UserInputType.MouseButton1 and not _sendingVim then
        _pauseVimUntil = tick() + 0.12
    end

    if input.KeyCode == Enum.KeyCode.RightControl then
        MainFrame.Visible = not MainFrame.Visible
    elseif input.KeyCode == Enum.KeyCode.End or input.KeyCode == Enum.KeyCode.KeypadOne then
        panicKillAll()
    end
end))

-- Pętla aktualizacji GUI
addThread(task.spawn(function()
    while ScriptActive do
        pcall(function()
            StatusLbl.Text = "Status: " .. Stats.Status
            TargetLbl.Text = "Cel: " .. Stats.CurrentTarget
            ChoppedLbl.Text = "Ścięte: " .. tostring(Stats.TreesChopped)
            EggsLbl.Text = string.format("Jajka (17x): %d", Stats.EggsOpened)
        end)
        task.wait(0.2)
    end
end))

-- ====================================================================
-- 12b. WĄTEK W TLE: ZDALNE OTWIERANIE JAJKA 250M (RE[3] BEZ TELEPORTACJI)
-- ====================================================================
addThread(task.spawn(function()
    while ScriptActive do
        if Settings.AutoOpenEggs then
            local rem = getEggRemote()
            if rem then
                pcall(function()
                    rem:FireServer(Settings.EggName, 2)
                    Stats.EggsOpened = Stats.EggsOpened + 17
                end)
            end
            task.wait(Settings.EggHatchRate)
        else
            task.wait(0.4)
        end
    end
end))

-- ====================================================================
-- 13. GŁÓWNA PĘTLA BOTA (MAIN FARM LOOP)
-- ====================================================================
addThread(task.spawn(function()
    task.wait(1.0)
    Stats.Status = "Sprawdzam siekierę..."

    while ScriptActive do
        if not Settings.AutoFarm then
            Stats.Status = "Wstrzymany (pauza)"
            restoreCamera()
            task.wait(0.4)
        else
            -- 1. Upewnij się, że siekiera jest w ręku
            if Settings.AutoEquipAxe and not isAxeEquipped() then
                Stats.Status = "Ekwipuję Sakura Axe..."
                equipSakuraAxe()
                task.wait(0.3)
            end

            -- 2. Wybierz najbliższe dostępne żywe drzewo (z pominięciem wykluczonych map!)
            local targetTree = getNearestAliveTree()
            if not targetTree then
                Stats.Status = "Brak drzew na dozwolonych mapach..."
                Stats.CurrentTarget = "Brak"
                restoreCamera()
                task.wait(0.5)
            else
                -- 3. Teleport przed pień (2.8 studa, naturalny widok 3. osoby)
                Stats.Status = "Teleportuję do drzewa..."
                local tpSuccess = teleportToTree(targetTree)
                if not tpSuccess then
                    skipTrees[targetTree] = tick() + 10
                    restoreCamera()
                    task.wait(0.1)
                else
                    -- 4. Bicie z krokami i dobijaniem twardszych drzew
                    chopTargetTreeWithSteps(targetTree)
                end
            end
        end
        task.wait(0.04)
    end
    restoreCamera()
end))

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "RCU Woodcutter",
        Text = "Wystartowano! Panel wykluczania map aktywny. [End] = Kill",
        Duration = 5,
    })
end)
