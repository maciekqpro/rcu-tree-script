--[[
    ═══════════════════════════════════════════════════════════════════
    💥 RCU BURST HATCH TESTER (Test podwójnego otwarcia w 0ms)
    ═══════════════════════════════════════════════════════════════════
    Sprawdza czy serwer przyjmie 2 lub 3 pakiety w tym samym ułamku sekundy:
      [TEST 1x] -> 1 pakiet (17 jajek)
      [TEST 2x] -> 2 pakiety w 0ms (34 jajka)
      [TEST 3x] -> 3 pakiety w 0ms (51 jajek)
    ═══════════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local LP = Players.LocalPlayer

-- Znajdź Egg Remote (RE[3])
local function getEggRemote()
    local knitServices = ReplicatedStorage:FindFirstChild("Packages") 
        and ReplicatedStorage.Packages:FindFirstChild("Knit")
        and ReplicatedStorage.Packages.Knit:FindFirstChild("Services")
    if knitServices then
        for _, s in ipairs(knitServices:GetChildren()) do
            local rp = s:FindFirstChild("RP")
            if rp and rp:FindFirstChild("globalEgg") then
                local re = s:FindFirstChild("RE")
                if re and re:GetChildren()[3] then
                    return re:GetChildren()[3]
                end
            end
        end
    end
    return nil
end

local rem = getEggRemote()
if not rem then
    warn("[BURST TESTER] Nie znaleziono RE[3] do otwierania jajek!")
    return
end

-- Usunięcie starego GUI testowego jeśli istnieje
pcall(function()
    local old = (gethui and gethui()) or CoreGui or LP:FindFirstChild("PlayerGui")
    if old:FindFirstChild("RCU_BurstTesterUI") then
        old.RCU_BurstTesterUI:Destroy()
    end
end)

-- Tworzenie eleganckiego mini GUI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RCU_BurstTesterUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = (gethui and gethui()) or CoreGui or LP:WaitForChild("PlayerGui")

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 270, 0, 210)
Main.Position = UDim2.new(0.5, -135, 0.4, -105)
Main.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(60, 70, 90)
Stroke.Thickness = 1.5
Stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 0, 32)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "💥 RCU BURST HATCH TESTER"
Title.TextColor3 = Color3.fromRGB(255, 215, 0)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 11
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 22)
CloseBtn.Position = UDim2.new(1, -38, 0, 5)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = Main

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 4)
CloseCorner.Parent = CloseBtn
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

local LogLbl = Instance.new("TextLabel")
LogLbl.Size = UDim2.new(1, -20, 0, 32)
LogLbl.Position = UDim2.new(0, 10, 0, 34)
LogLbl.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
LogLbl.Text = "Gotowy! Zapamiętaj ile masz petów w eq i kliknij test."
LogLbl.TextColor3 = Color3.fromRGB(180, 220, 255)
LogLbl.Font = Enum.Font.GothamMedium
LogLbl.TextSize = 9
LogLbl.TextWrapped = true
LogLbl.BorderSizePixel = 0
LogLbl.Parent = Main

local LogCorner = Instance.new("UICorner")
LogCorner.CornerRadius = UDim.new(0, 5)
LogCorner.Parent = LogLbl

local function createBtn(text, yPos, color, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 32)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.BackgroundColor3 = color
    btn.BorderSizePixel = 0
    btn.Parent = Main

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 6)
    bCorner.Parent = btn

    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- Przycisk 1: Pojedyncze (17)
createBtn("1. TEST 1x (Zwykłe 17 jajek)", 74, Color3.fromRGB(40, 120, 60), function()
    LogLbl.Text = "Wysyłam 1x pakiet (17 jajek)..."
    rem:FireServer("250M", 2)
    LogLbl.Text = "[OK] Wysłano 1x! Sprawdź czy przybyło dokładnie +17 petów."
    print("[BURST TEST] Wysłano 1x pakiet (17 jajek)")
end)

-- Przycisk 2: Podwójne w 0ms (34)
createBtn("2. TEST 2x BURST w 0ms (Powinno być 34)", 114, Color3.fromRGB(0, 130, 200), function()
    LogLbl.Text = "Wysyłam 2x pakiet w tej samej milisekundzie..."
    rem:FireServer("250M", 2)
    rem:FireServer("250M", 2)
    LogLbl.Text = "[OK] Wysłano 2x w 0ms! Czy w eq masz +17 czy +34 pety?"
    print("[BURST TEST] Wysłano 2x pakiet w 0ms (34 jajka)")
end)

-- Przycisk 3: Potrójne w 0ms (51)
createBtn("3. TEST 3x BURST w 0ms (Powinno być 51)", 154, Color3.fromRGB(160, 60, 160), function()
    LogLbl.Text = "Wysyłam 3x pakiet w tej samej milisekundzie..."
    rem:FireServer("250M", 2)
    rem:FireServer("250M", 2)
    rem:FireServer("250M", 2)
    LogLbl.Text = "[OK] Wysłano 3x w 0ms! Czy w eq masz +17, czy +51 petów?"
    print("[BURST TEST] Wysłano 3x pakiet w 0ms (51 jajek)")
end)

print("[BURST TESTER] Załadowano pomyślnie! Okienko na środku ekranu.")
