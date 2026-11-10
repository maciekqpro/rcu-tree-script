-- ====================================================================
-- 🕵️ RCU PARADOX MERCHANT DEEP SPY & PACKET SNIFFER (v1.0)
-- ====================================================================
-- Skrypt przygotowany specjalnie do analizy Paradox Merchanta:
--   1. Przechwytuje KAŻDE wywołanie InvokeServer / FireServer (metoda, remote, argumenty, zwrot)
--   2. Skanuje okno Players.LocalPlayer.PlayerGui.MainUI.Menus.ParadoxMerchantFrame
--   3. Śledzi kliknięcia we wszystkie przyciski zakupu w oknie Merchanta
--   4. Przeszukuje usługi Knit i kontrolery powiązane z Paradox Merchantem
--   5. Automatycznie kopiuje raport do schowka Windows po wykryciu zakupu!
-- ====================================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")

local LP = Players.LocalPlayer
local logs = {}
local totalCapturedEvents = 0
local liveLogLabel = nil

local function log(txt)
    local line = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(txt or ""))
    table.insert(logs, line)
    print("[PARADOX SPY] " .. tostring(txt or ""))
    if liveLogLabel and liveLogLabel.Parent then
        pcall(function()
            local recent = {}
            local startIdx = math.max(1, #logs - 15)
            for i = startIdx, #logs do
                table.insert(recent, logs[i])
            end
            liveLogLabel.Text = table.concat(recent, "\n")
        end)
    end
end

local function copyReport()
    local full = table.concat(logs, "\n")
    local ok = false
    if type(setclipboard) == "function" then
        ok = pcall(setclipboard, full)
    elseif type(toclipboard) == "function" then
        ok = pcall(toclipboard, full)
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Paradox Spy",
            Text = ok and "Raport skopiowany do schowka (Ctrl+V)!" or "Błąd kopiowania do schowka!",
            Duration = 4,
        })
    end)
    return full
end

log("====================================================================")
log("  RCU PARADOX MERCHANT SPY URUCHOMIONY — " .. os.date("%Y-%m-%d %H:%M:%S"))
log("====================================================================")

-- Funkcja pomocnicza: rekurencyjna serializacja tabel do czytelnego formatu
local function serializeValue(val, depth)
    depth = depth or 0
    if depth > 4 then return "<zbyt głębokie zagnieżdżenie>" end
    local t = typeof(val)
    if t == "string" then
        return string.format("%q", val)
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "Instance" then
        return string.format("<Instance: %s (%s)>", val:GetFullName(), val.ClassName)
    elseif t == "table" then
        local parts = {}
        local count = 0
        for k, v in pairs(val) do
            count = count + 1
            if count > 30 then
                table.insert(parts, "... (obcięto)")
                break
            end
            local kStr = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or string.format("[%s]", serializeValue(k, depth + 1))
            table.insert(parts, string.format("%s = %s", kStr, serializeValue(v, depth + 1)))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return string.format("<%s: %s>", t, tostring(val))
    end
end

-- ====================================================================
-- [1] PRZECHWYTYWANIE PAKIETÓW SIECIOWYCH (HOOK NAMECALL / INVOKESERVER / FIRESERVER)
-- ====================================================================
log("\n[1] INSTALACJA PAKIETU SNIFFERA SIECIOWEGO (__namecall / remotes)...")

local hookSuccess = false
pcall(function()
    local rawMeta = getrawmetatable and getrawmetatable(game)
    local setReadOnly = setreadonly or make_writeable
    local oldNamecall = nil
    local oldIndex = nil

    if rawMeta and type(hookmetamethod) == "function" then
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = { ... }

            if (method == "InvokeServer" or method == "FireServer") and typeof(self) == "Instance" then
                local remoteName = self.Name
                local remotePath = self:GetFullName()
                local rLower = remoteName:lower()
                local pLower = remotePath:lower()

                local isRelevant = rLower:find("paradox") or rLower:find("merchant") or rLower:find("buy")
                    or rLower:find("shop") or rLower:find("purchase") or pLower:find("paradox")
                    or pLower:find("merchant") or pLower:find("anna") or pLower:find("knit")

                if isRelevant then
                    totalCapturedEvents = totalCapturedEvents + 1
                    local caller = (debug and debug.info and debug.info(2, "sl")) or "nieznany caller"
                    local serializedArgs = serializeValue(args)

                    log(string.format("🎯 [WYKRYTO SIECIOWE WYWOŁANIE #%d]", totalCapturedEvents))
                    log(string.format("   Metoda: %s | Remote: %s", method, remoteName))
                    log(string.format("   Ścieżka: %s", remotePath))
                    log(string.format("   Caller: %s", tostring(caller)))
                    log(string.format("   Argumenty (%d): %s", #args, serializedArgs))

                    -- Pokaż powiadomienie na ekranie i skopiuj do schowka
                    pcall(function()
                        copyReport()
                        StarterGui:SetCore("SendNotification", {
                            Title = "🎯 PARADOX SPY: WYKRYTO PAKIET!",
                            Text = string.format("%s:%s()", remoteName, method),
                            Duration = 6,
                        })
                    end)
                end
            end

            return oldNamecall(self, ...)
        end))
        hookSuccess = true
        log("  -> [SUKCES] hookmetamethod(__namecall) zainstalowany poprawnie!")
    elseif rawMeta and type(hookfunction) == "function" then
        -- Fallback: bezpośredni hook na RemoteFunction.InvokeServer i RemoteEvent.FireServer
        local oldInvoke = hookfunction(Instance.new("RemoteFunction").InvokeServer, newcclosure(function(self, ...)
            local args = { ... }
            log(string.format("🎯 [RemoteFunction:InvokeServer] %s | Args: %s", self:GetFullName(), serializeValue(args)))
            pcall(copyReport)
            return oldInvoke(self, ...)
        end))
        local oldFire = hookfunction(Instance.new("RemoteEvent").FireServer, newcclosure(function(self, ...)
            local args = { ... }
            log(string.format("🎯 [RemoteEvent:FireServer] %s | Args: %s", self:GetFullName(), serializeValue(args)))
            pcall(copyReport)
            return oldFire(self, ...)
        end))
        hookSuccess = true
        log("  -> [SUKCES] hookfunction na InvokeServer / FireServer zainstalowany poprawnie!")
    end
end)

if not hookSuccess then
    log("  -> [UWAGA] Executor nie wspiera hookmetamethod ani hookfunction — sniffing pakietów ograniczony do getgc i zdarzeń GUI!")
end

-- ====================================================================
-- [2] SKANOWANIE USŁUG KNIT I GETGC W POSZUKIWANIU PARADOX
-- ====================================================================
log("\n[2] SKANOWANIE USŁUG KNIT I PAMIĘCI GETGC:")
pcall(function()
    if type(getgc) == "function" then
        local foundKnitObjects = {}
        for _, obj in ipairs(getgc(true)) do
            if type(obj) == "table" then
                local oName = rawget(obj, "Name") or rawget(obj, "_name") or ""
                local hasBuy = false
                local methods = {}
                for k, v in pairs(obj) do
                    if type(k) == "string" and type(v) == "function" then
                        local kl = k:lower()
                        if kl:find("paradox") or kl:find("merchant") or kl:find("buy") or kl:find("shop") or kl:find("purchase") then
                            hasBuy = true
                            table.insert(methods, k)
                        end
                    end
                end
                if hasBuy or (type(oName) == "string" and (oName:lower():find("paradox") or oName:lower():find("merchant"))) then
                    log(string.format("  -> ZNALEZIONO OBIEKT GC: '%s' | Metody: %s", tostring(oName), table.concat(methods, ", ")))
                end
            end
        end
    end
end)

pcall(function()
    local knitServices = ReplicatedStorage:FindFirstChild("Packages")
        and ReplicatedStorage.Packages:FindFirstChild("Knit")
        and ReplicatedStorage.Packages.Knit:FindFirstChild("Services")
    if knitServices then
        log("  Knit Services w ReplicatedStorage:")
        for _, s in ipairs(knitServices:GetChildren()) do
            local rfCount = s:FindFirstChild("RF") and #s.RF:GetChildren() or 0
            local reCount = s:FindFirstChild("RE") and #s.RE:GetChildren() or 0
            local rpCount = s:FindFirstChild("RP") and #s.RP:GetChildren() or 0
            log(string.format("    - Usługa: %s (RF: %d, RE: %d, RP: %d)", s.Name, rfCount, reCount, rpCount))
        end
    end
end)

-- ====================================================================
-- [3] MONITOROWANIE OKNA PARADOX MERCHANT FRAME I PRZYCISKÓW
-- ====================================================================
log("\n[3] INICJALIZACJA MONITOROWANIA GUI PARADOX MERCHANTA:")

local function inspectAndHookParadoxFrame(frame)
    if not frame then return end
    log(string.format("🔍 [WYKRYTO PARADOX FRAME] Nazwa: %s | Visible: %s", frame.Name, tostring(frame.Visible)))

    -- Zrzucenie wszystkich etykiet i dzieci
    for _, desc in ipairs(frame:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextBox") then
            if desc.Text and desc.Text ~= "" then
                log(string.format("    • [%s] %s = %q", desc.ClassName, desc:GetFullName():gsub(frame:GetFullName() .. "%.", ""), desc.Text))
            end
        end
    end

    -- Hookowanie wszystkich przycisków w oknie
    local btnCount = 0
    for _, desc in ipairs(frame:GetDescendants()) do
        if desc:IsA("GuiButton") then
            btnCount = btnCount + 1
            local btnPath = desc:GetFullName():gsub(frame:GetFullName() .. "%.", "")
            desc.MouseButton1Click:Connect(function()
                log(string.format("👆 [KLIKNIĘCIE W PRZYCISK MERCHANTA]: %s (Text: %q)", btnPath, desc:IsA("TextButton") and desc.Text or ""))
                pcall(function()
                    task.wait(0.1)
                    copyReport()
                end)
            end)
        end
    end
    log(string.format("  -> Podpięto nasłuchiwanie pod %d przycisków w %s!", btnCount, frame.Name))
end

pcall(function()
    local pg = LP:WaitForChild("PlayerGui", 5)
    local mainUI = pg and pg:WaitForChild("MainUI", 5)
    local menus = mainUI and mainUI:WaitForChild("Menus", 5)
    if menus then
        for _, f in ipairs(menus:GetChildren()) do
            if f.Name:lower():find("paradox") or f.Name:lower():find("merchant") then
                inspectAndHookParadoxFrame(f)
                f:GetPropertyChangedSignal("Visible"):Connect(function()
                    log(string.format("👁️ [ZMIANA WIDOCZNOŚCI OKNA] %s.Visible = %s", f.Name, tostring(f.Visible)))
                    if f.Visible then
                        inspectAndHookParadoxFrame(f)
                    end
                end)
            end
        end

        menus.ChildAdded:Connect(function(child)
            if child.Name:lower():find("paradox") or child.Name:lower():find("merchant") then
                task.wait(0.2)
                inspectAndHookParadoxFrame(child)
            end
        end)
    end
end)

-- ====================================================================
-- [4] INTERFEJS GRAFICZNY SPYA NA EKRANIE
-- ====================================================================
pcall(function()
    local oldGui = CoreGui:FindFirstChild("RCU_ParadoxSpyUI") or (LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("RCU_ParadoxSpyUI"))
    if oldGui then oldGui:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "RCU_ParadoxSpyUI"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 999
    sg.Parent = CoreGui:FindFirstChild("RobloxGui") or LP:WaitForChild("PlayerGui")

    local f = Instance.new("Frame")
    f.Name = "MainFrame"
    f.Size = UDim2.new(0, 360, 0, 240)
    f.Position = UDim2.new(0, 20, 0.5, -120)
    f.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    f.BorderSizePixel = 0
    f.Active = true
    f.Draggable = true
    f.Parent = sg

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = f

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(130, 60, 200)
    stroke.Thickness = 1.5
    stroke.Parent = f

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -16, 0, 26)
    title.Position = UDim2.new(0, 8, 0, 6)
    title.BackgroundTransparency = 1
    title.Text = "🕵️ RCU PARADOX MERCHANT SPY"
    title.TextColor3 = Color3.fromRGB(200, 150, 255)
    title.TextSize = 12
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = f

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -16, 0, 18)
    status.Position = UDim2.new(0, 8, 0, 30)
    status.BackgroundTransparency = 1
    status.Text = "🟢 Gotowy! Podejdź do Paradox Merchanta i kup cokolwiek."
    status.TextColor3 = Color3.fromRGB(120, 240, 140)
    status.TextSize = 9
    status.Font = Enum.Font.Gotham
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = f

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 0, 135)
    scroll.Position = UDim2.new(0, 8, 0, 52)
    scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    scroll.BorderSizePixel = 0
    scroll.CanvasSize = UDim2.new(0, 0, 0, 400)
    scroll.ScrollBarThickness = 4
    scroll.Parent = f

    local scrollCorner = Instance.new("UICorner")
    scrollCorner.CornerRadius = UDim.new(0, 6)
    scrollCorner.Parent = scroll

    liveLogLabel = Instance.new("TextLabel")
    liveLogLabel.Size = UDim2.new(1, -8, 1, -8)
    liveLogLabel.Position = UDim2.new(0, 4, 0, 4)
    liveLogLabel.BackgroundTransparency = 1
    liveLogLabel.Text = table.concat(logs, "\n")
    liveLogLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
    liveLogLabel.TextSize = 8
    liveLogLabel.Font = Enum.Font.Code
    liveLogLabel.TextXAlignment = Enum.TextXAlignment.Left
    liveLogLabel.TextYAlignment = Enum.TextYAlignment.Top
    liveLogLabel.TextWrapped = true
    liveLogLabel.Parent = scroll

    -- Przyciski na dole
    local copyBtn = Instance.new("TextButton")
    copyBtn.Size = UDim2.new(0.68, -4, 0, 28)
    copyBtn.Position = UDim2.new(0, 8, 1, -34)
    copyBtn.BackgroundColor3 = Color3.fromRGB(90, 40, 150)
    copyBtn.Text = "📋 KOPIUJ RAPORT (CTRL+V)"
    copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    copyBtn.TextSize = 9
    copyBtn.Font = Enum.Font.GothamBold
    copyBtn.BorderSizePixel = 0
    copyBtn.Parent = f

    local cbCorner = Instance.new("UICorner")
    cbCorner.CornerRadius = UDim.new(0, 6)
    cbCorner.Parent = copyBtn

    copyBtn.MouseButton1Click:Connect(function()
        copyReport()
    end)

    local clearBtn = Instance.new("TextButton")
    clearBtn.Size = UDim2.new(0.30, -4, 0, 28)
    clearBtn.Position = UDim2.new(0.70, 0, 1, -34)
    clearBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    clearBtn.Text = "🗑️ CZYŚĆ"
    clearBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    clearBtn.TextSize = 9
    clearBtn.Font = Enum.Font.GothamBold
    clearBtn.BorderSizePixel = 0
    clearBtn.Parent = f

    local clCorner = Instance.new("UICorner")
    clCorner.CornerRadius = UDim.new(0, 6)
    clCorner.Parent = clearBtn

    clearBtn.MouseButton1Click:Connect(function()
        table.clear(logs)
        log("Wyczyszczono logi. Czekam na zdarzenia Paradox...")
    end)
end)

log("\n=== SPY GOTOWY DO PRACY! PODEJDŹ DO PARADOX MERCHANTA I KUP COKOLWIEK ===")
copyReport()
