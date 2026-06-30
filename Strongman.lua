local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ReplicatedFirst    = game:GetService("ReplicatedFirst")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local VirtualUser        = game:GetService("VirtualUser")
local LocalPlayer        = Players.LocalPlayer

local connections = {}
local function track(c) connections[#connections + 1] = c; return c end

----------------------------------------------------------------------
-- Hashed-remote resolver (executor-agnostic, zero dependencies)
-- Every networked remote is named MD5(friendlyName .. JobId) and stored
-- flat in ReplicatedStorage. We compute that name with a built-in MD5,
-- so resolution needs no require / hookmetamethod / getnamecallmethod
-- and works on the weakest injectors exactly like on the strongest.
----------------------------------------------------------------------
local function md5(msg)
    local K = {
        0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
        0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
        0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
        0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
        0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
        0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
        0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
        0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391,
    }
    local S = {
        7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
        5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
        4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
        6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21,
    }
    local band,bor,bxor,bnot,lrotate = bit32.band,bit32.bor,bit32.bxor,bit32.bnot,bit32.lrotate
    local a0,b0,c0,d0 = 0x67452301,0xefcdab89,0x98badcfe,0x10325476
    local bitLen = #msg * 8
    msg = msg .. "\128"
    while (#msg % 64) ~= 56 do msg = msg .. "\0" end
    local function w32le(n) return string.char(n%256, math.floor(n/256)%256, math.floor(n/65536)%256, math.floor(n/16777216)%256) end
    msg = msg .. w32le(bitLen % 0x100000000) .. w32le(math.floor(bitLen / 0x100000000) % 0x100000000)
    for chunk = 1, #msg, 64 do
        local M = {}
        for j = 0, 15 do
            local p = chunk + j*4
            local b1,b2,b3,b4 = string.byte(msg, p, p+3)
            M[j] = b1 + b2*256 + b3*65536 + b4*16777216
        end
        local A,B,C,D = a0,b0,c0,d0
        for i = 0, 63 do
            local F,g
            if i < 16 then F = bor(band(B,C), band(bnot(B),D)); g = i
            elseif i < 32 then F = bor(band(D,B), band(bnot(D),C)); g = (5*i+1)%16
            elseif i < 48 then F = bxor(bxor(B,C),D); g = (3*i+5)%16
            else F = bxor(C, bor(B, bnot(D))); g = (7*i)%16 end
            F = (F + A + K[i+1] + M[g]) % 0x100000000
            A = D; D = C; C = B
            B = (B + lrotate(F, S[i+1])) % 0x100000000
        end
        a0=(a0+A)%0x100000000; b0=(b0+B)%0x100000000; c0=(c0+C)%0x100000000; d0=(d0+D)%0x100000000
    end
    local function hexle(n)
        local s = ""
        for i = 0, 3 do s = s .. string.format("%02x", math.floor(n/(256^i))%256) end
        return s
    end
    return hexle(a0)..hexle(b0)..hexle(c0)..hexle(d0)
end

local function resolveRemote(friendly)
    local jid = game.JobId
    local name = md5(friendly .. (jid == "" and "00000000-0000-0000-0000-000000000000" or jid))
    return ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 6)
end

----------------------------------------------------------------------
-- Game bindings
----------------------------------------------------------------------
local function optreq(inst)
    if typeof(inst) ~= "Instance" then return nil end
    local ok, m = pcall(require, inst)
    return ok and m or nil
end

local function findPath(root, ...)
    local node = root
    for _, seg in ipairs({ ... }) do
        if typeof(node) ~= "Instance" then return nil end
        node = node:FindFirstChild(seg)
        if not node then return nil end
    end
    return node
end

local Items, ItemCat, PetSys
local function bindModules()
    Items   = Items   or optreq(findPath(workspace, "Lib", "Items", "TGSItems"))
    ItemCat = ItemCat or optreq(findPath(workspace, "Lib", "Items", "ItemCategoryEnum"))
    PetSys  = PetSys  or optreq(findPath(workspace, "Lib", "PetSystem", "TGSPetSystem"))
end
bindModules()

local CURRENCY_TARGET = "Currency_Knivsta"   -- 3 Knivsta = 1 Energy
local RATIO           = 3
local GIVE_KEY        = "Default"

----------------------------------------------------------------------
-- Remote registry
----------------------------------------------------------------------
local R = {}
local function bind()
    R.conv      = R.conv      or resolveRemote("CurrencyConverter_ExchangeCurrencyFund")
    R.strength  = R.strength  or resolveRemote("StrongMan_UpgradeStrength")
    R.workout   = R.workout   or resolveRemote("StrongmanWorkout_SetIsWorkingOut")
    R.rebirth   = R.rebirth   or resolveRemote("StrongMan_Rebirth")
    R.powerMax  = R.powerMax  or resolveRemote("BuyPowerUpgradeMax")
    R.roll      = R.roll      or resolveRemote("TGSPetShopRoll")
    R.petEquip  = R.petEquip  or resolveRemote("TGSPetSystem_EquipPet")
    R.petSell   = R.petSell   or resolveRemote("TGSPetSystem_SellMultiPets")
    R.petComb   = R.petComb   or resolveRemote("TGSPetSystem_CombinePets")
    R.spClaim   = R.spClaim   or resolveRemote("TGSSeasonPets_ClaimPet")
    R.spToggle  = R.spToggle  or resolveRemote("TGSSeasonPets_ToggleSeasonPet")
    R.session   = R.session   or resolveRemote("TGSSimpleSessionRewards_ClaimSessionRewardRemote")
    R.trailer   = R.trailer   or resolveRemote("TrailerReward_ClaimTrailerReward")
    R.community = R.community  or resolveRemote("CommunityRewards_claim")
    R.promo     = R.promo     or ReplicatedStorage:FindFirstChild("PromoCodeRequest")
    R.daily     = R.daily     or ReplicatedStorage:FindFirstChild("RepeatableRewards_Claim")
end
task.spawn(bind)
task.spawn(function()
    for _ = 1, 12 do
        bindModules()
        if Items and ItemCat and PetSys then break end
        task.wait(0.75)
    end
end)

----------------------------------------------------------------------
-- Stat readers
----------------------------------------------------------------------
local function readItem(cat, key)
    if not Items or not ItemCat then return nil end
    local ok, v = pcall(Items.GetItemInfo, LocalPlayer, cat, key)
    if ok and type(v) == "number" then return v end
    return nil
end
local function readEnergy()   return readItem(ItemCat and ItemCat.Currency, "Default") end
local function readKnivsta()  return readItem(ItemCat and ItemCat.Currency, "Knivsta") end
local function readStrength() return readItem(ItemCat and ItemCat.Stat, "Default") end
local function readRebirth()  return readItem(ItemCat and ItemCat.Stat, "Rebirth") end

----------------------------------------------------------------------
-- Amount parsing: 1k · 1000 · 1.5m · 1sx · 1sp · 2kk · 1 000 000
----------------------------------------------------------------------
local SUFFIX = {
    [""] = 1,
    k = 1e3, m = 1e6, b = 1e9, t = 1e12,
    qd = 1e15, qn = 1e18, sx = 1e21, sp = 1e24, oc = 1e27, no = 1e30,
    dc = 1e33, ud = 1e36, dd = 1e39, td = 1e42, qad = 1e45, qnd = 1e48,
    sxd = 1e51, spd = 1e54, ocd = 1e57, nod = 1e60,
    vg = 1e63, uvg = 1e66, dvg = 1e69, tvg = 1e72, qavg = 1e75,
    qnvg = 1e78, sxvg = 1e81, spvg = 1e84, ocvg = 1e87, novg = 1e90,
    kk = 1e6, kkk = 1e9, q = 1e15, qa = 1e15, qi = 1e18,
    thousand = 1e3, million = 1e6, billion = 1e9, trillion = 1e12,
}

-- Hard ceiling for energy. The converter mints energy through Knivsta at a
-- 1:3 ratio, so the server transiently holds 3x the requested energy. Past
-- maxDouble/3 that intermediate value overflows to inf, which then corrupts
-- the save (DataStore cannot store inf/nan). We cap a hair below that edge:
-- 5.9e307 * 3 = 1.77e308, safely under maxDouble (1.7977e308).
local SAFE_MAX = 5.9e307

local function parseAmount(input)
    if type(input) ~= "string" then return nil end
    local s = input:lower():gsub("%s+", ""):gsub(",", ""):gsub("_", "")
    if s == "" then return nil end
    if s == "max" or s == "макс" or s == "inf" or s == "∞" then return SAFE_MAX end
    local total
    local mant, exp = s:match("^(%d*%.?%d+)e([%+%-]?%d+)$")
    if mant then
        total = tonumber(mant .. "e" .. exp)
    else
        local num, suf = s:match("^(%d*%.?%d+)([a-z]*)$")
        if not num then return nil end
        local mult = SUFFIX[suf]
        if not mult then return nil end
        local n = tonumber(num)
        if not n then return nil end
        total = n * mult
    end
    if not total or total ~= total or total <= 0 then return nil end
    if total > SAFE_MAX then total = SAFE_MAX end
    if total >= 1e15 then return total end
    return math.floor(total + 0.5)
end

local SCALE = {
    {1e90,"NoVg"},{1e87,"OcVg"},{1e84,"SpVg"},{1e81,"SxVg"},{1e78,"QnVg"},{1e75,"QaVg"},
    {1e72,"TVg"},{1e69,"DVg"},{1e66,"UVg"},{1e63,"Vg"},{1e60,"NoD"},{1e57,"OcD"},
    {1e54,"SpD"},{1e51,"SxD"},{1e48,"QnD"},{1e45,"QaD"},{1e42,"Td"},{1e39,"Dd"},
    {1e36,"Ud"},{1e33,"Dc"},{1e30,"No"},{1e27,"Oc"},{1e24,"Sp"},{1e21,"Sx"},
    {1e18,"Qn"},{1e15,"Qd"},{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"},
}

local function fmt(n)
    if type(n) ~= "number" then return "?" end
    if n ~= n then return "∞" end
    if n == math.huge then return "∞" end
    for _, e in ipairs(SCALE) do
        if n >= e[1] then return string.format("%.2f%s", n / e[1], e[2]) end
    end
    return tostring(math.floor(n))
end

----------------------------------------------------------------------
-- Currency: mint Knivsta via sign-bypass, then convert to energy
----------------------------------------------------------------------
local State = { alive = true, autoRebirth = false, autoHatch = false, busy = {} }

local function ensureKnivsta(needKnivsta)
    if not R.conv then return end
    if (readKnivsta() or 0) >= needKnivsta then return end
    local energy = readEnergy() or 0
    if energy == math.huge or energy ~= energy then energy = 0 end
    local mint = (energy + needKnivsta / RATIO + 1e6) * RATIO
    pcall(function() R.conv:InvokeServer(CURRENCY_TARGET, -mint) end)
    task.wait(0.55)
end

local function giveEnergy(target)
    if not R.conv then return false, 0 end
    if target > SAFE_MAX then target = SAFE_MAX end
    local needKnivsta = target * RATIO
    ensureKnivsta(needKnivsta)
    local ok = pcall(function() R.conv:InvokeServer(CURRENCY_TARGET, needKnivsta) end)
    return ok, ok and target or 0
end

----------------------------------------------------------------------
-- Strength delivery. The server SUMS the cost of every strength level it
-- grants, looping once per requested count and once per rebirth tier; a
-- single huge count makes it loop tens of millions of times and freezes
-- the server. We cap each call to a measured no-freeze budget and deliver
-- the total across cooldown-spaced calls — progress shown live.
----------------------------------------------------------------------
local hookActive = true
local onStrengthCaptured

local function setStrengthRemote(remote)
    local wasEmpty = (R.strength == nil)
    R.strength = remote
    hookActive = false
    if wasEmpty and onStrengthCaptured then pcall(onStrengthCaptured) end
end

local function installStrengthHook()
    if not (hookmetamethod and getnamecallmethod) then return end
    local function wrap(f) return (newcclosure and newcclosure(f)) or f end
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        if hookActive then
            if R.strength then
                hookActive = false
            elseif getnamecallmethod() == "InvokeServer" then
                local a1, a2 = ...
                if type(a1) == "number" and a2 == GIVE_KEY then
                    local ok, cls = pcall(function() return self.ClassName end)
                    if ok and cls == "RemoteFunction" then setStrengthRemote(self) end
                end
            end
        end
        return oldNamecall(self, ...)
    end))
end

task.spawn(function()
    for _ = 1, 12 do
        if R.strength then return end
        task.wait(0.5)
    end
    if not R.strength then installStrengthHook() end
end)

local STRENGTH_CALL_BUDGET = 40000000000

local function setServerWorkout(state)
    if R.workout then pcall(function() R.workout:FireServer(state) end) end
end

local function giveStrength(target, onProgress)
    local remote = R.strength
    if not remote then return false, 0, true end
    local char = LocalPlayer.Character
    local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))

    local wasWorkingOut = root and root.Anchored
    if root and not wasWorkingOut then
        root.Anchored = true
        setServerWorkout(true)
        task.wait(0.25)
    end

    local affordIters = math.max(1, math.min(math.floor((readRebirth() or 0) * 0.01), 50000))
    local perCall = math.max(1, math.floor(STRENGTH_CALL_BUDGET / affordIters))

    local remaining = math.max(1, math.floor(target))
    local delivered = 0
    local cd = 0.7
    local fails, calls = 0, 0
    local MAX_CALLS = 30
    while remaining > 0 and State.alive do
        local chunk = math.min(remaining, perCall)
        local ok, res = pcall(function() return remote:InvokeServer(chunk, GIVE_KEY) end)
        if ok and res == true then
            delivered = delivered + chunk
            remaining = remaining - chunk
            calls = calls + 1
            fails = 0
            if onProgress then pcall(onProgress, delivered) end
            if calls >= MAX_CALLS then break end
            task.wait(cd)
        else
            fails = fails + 1
            if fails >= 6 then break end
            cd = math.min(cd + 0.12, 1.2)
            task.wait(cd)
        end
    end

    if root and not wasWorkingOut then
        setServerWorkout(false)
        root.Anchored = false
    end
    return delivered > 0, delivered
end

local FAST_MAX_ITERS = 250000000000000000000

local function giveStrengthFast(target)
    local remote = R.strength
    if not remote then return false, 0, true end
    local char = LocalPlayer.Character
    local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))
    local wasWorkingOut = root and root.Anchored
    if root and not wasWorkingOut then
        root.Anchored = true
        setServerWorkout(true)
        task.wait(0.25)
    end

    local affordIters = math.max(1, math.min(math.floor((readRebirth() or 0) * 0.01), 50000))
    local count = math.min(math.max(1, math.floor(target)),
        math.max(1, math.floor(FAST_MAX_ITERS / affordIters)))

    local function fire()
        local ok, r = pcall(function() return remote:InvokeServer(count, GIVE_KEY) end)
        if ok then return r end
        return nil
    end
    local res = fire()
    if res ~= true then task.wait(0.25); res = fire() end

    if root and not wasWorkingOut then
        setServerWorkout(false)
        root.Anchored = false
    end
    local success = res == true
    return success, success and count or 0
end

----------------------------------------------------------------------
-- Rebirth. Cost is paid in Strength; each rebirth = +10% energy/coin
-- multiplier permanently. We pump strength a few bounded fast-calls then
-- fire the bulk rebirth, which grants every rebirth the strength affords.
----------------------------------------------------------------------
local function rebirthOnce()
    if R.rebirth then pcall(function() R.rebirth:FireServer() end) end
end

local function rebirthCycle(pumps)
    local root = LocalPlayer.Character and LocalPlayer.Character.PrimaryPart
    for _ = 1, math.max(1, pumps) do
        if not State.alive then return end
        giveStrengthFast(1e30)
        task.wait(0.2)
    end
    rebirthOnce()
    if root then setServerWorkout(false); root.Anchored = false end
    task.wait(2.15)
end

----------------------------------------------------------------------
-- Promo codes (plain-named RemoteFunction). Codes live server-side, so
-- we submit a candidate list; each returns (success, message).
----------------------------------------------------------------------
local PROMO_CODES = {
    "speedygains2000","time4gains","happyvalentinespump",
    "shazam!furyofthegods","shazam!","learnthe","strongman","season1",
    "1500likes","5000likes","10000likes","10000","25k","10m","100m","400m",
    "strongmansim","update","release","like","sub",
}

local function redeemCodes(report)
    if not R.promo then if report then report("PromoCodeRequest не найден", true) end return end
    local good = 0
    for _, code in ipairs(PROMO_CODES) do
        if not State.alive then break end
        local ok, success = pcall(function() return R.promo:InvokeServer(code) end)
        if ok and success == true then good = good + 1 end
        if report then report("Промокоды: " .. code .. "  (рабочих " .. good .. ")") end
        task.wait(0.35)
    end
    if report then report("Промокоды готовы — рабочих: " .. good .. " ✅", false, true) end
end

----------------------------------------------------------------------
-- Season pets — ClaimPet has no eligibility gate at all.
----------------------------------------------------------------------
local SEASON_PETS = {
    "Stalactort","RhinoBoy","Rex","Darnello","Pupador","FroolevMusic","Pitit",
    "Tazuni","Grizzelord","Fowl","Grumz1","Grumz2","Hyptad1","Froolev","Scarecrow",
}

local function equipBestSeasonPet()
    local folder = findPath(workspace, "Lib", "Seasons", "SeasonPetSettings")
    if not folder then return end
    local best, bestScore = nil, -1
    for _, n in ipairs(SEASON_PETS) do
        local m = folder:FindFirstChild(n)
        if m then
            local ok, s = pcall(require, m)
            if ok and type(s) == "table" then
                local score = (tonumber(s.EnergyGain) or 0) + (tonumber(s.WorkoutGain) or 0)
                    + (tonumber(s.SeasonXPMultiplier) or 0) + (tonumber(s.WorkoutSpeedMultiplier) or 0)
                if score > bestScore then bestScore = score; best = n end
            end
        end
    end
    if best and R.spToggle then pcall(function() R.spToggle:InvokeServer(best) end) end
    return best
end

local function claimAllSeasonPets(report)
    if not R.spClaim then if report then report("Сезон-петы: remote не найден", true) end return end
    for i, n in ipairs(SEASON_PETS) do
        if not State.alive then break end
        pcall(function() R.spClaim:InvokeServer(n) end)
        if report then report("Сезон-петы: " .. i .. "/" .. #SEASON_PETS) end
        task.wait(0.15)
    end
    local best = equipBestSeasonPet()
    if report then report("Сезон-петы забраны, надет: " .. (best or "—") .. " ✅", false, true) end
end

----------------------------------------------------------------------
-- Power upgrade (Strength), max level. Paid in energy (which is endless).
----------------------------------------------------------------------
local function maxPower(report)
    if not R.powerMax then if report then report("Power upgrade: remote не найден", true) end return end
    giveEnergy(1e9)
    local ok, count = pcall(function() return R.powerMax:InvokeServer("Strength") end)
    if ok then
        report(("Power upgrade: куплено уровней %s ✅"):format(tostring(count or 0)), false, true)
    else
        report("Power upgrade не прошёл (нет серверного модуля)", true)
    end
end

----------------------------------------------------------------------
-- One-shot reward sweep
----------------------------------------------------------------------
local function claimRewards(report)
    local n = 0
    if R.trailer then pcall(function() R.trailer:InvokeServer("MLC") end); n = n + 1; task.wait(0.2) end
    if R.session then pcall(function() R.session:FireServer() end); n = n + 1; task.wait(0.2) end
    if R.community then
        pcall(function() R.community:InvokeServer("SeasonSummer", "Tier3") end); task.wait(0.2)
        pcall(function() R.community:InvokeServer("SeasonSummer", "Tier7") end); n = n + 1; task.wait(0.2)
    end
    if R.daily then pcall(function() R.daily:InvokeServer("DailyGroupReward") end); n = n + 1; task.wait(0.2) end
    if report then report("Награды собраны (" .. n .. " источников) ✅", false, true) end
end

----------------------------------------------------------------------
-- Pets: hatch / sell junk / equip best / combine duplicates
----------------------------------------------------------------------
local RARITY = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

local function ownedPets()
    if not PetSys or not PetSys.GetOwnedPets then return {} end
    local ok, m = pcall(PetSys.GetOwnedPets, LocalPlayer)
    if not ok or type(m) ~= "table" then return {} end
    local arr = {}
    for _, p in pairs(m) do arr[#arr + 1] = p end
    return arr
end

local function idSet(getter)
    local s = {}
    if PetSys and PetSys[getter] then
        local ok, a = pcall(PetSys[getter], LocalPlayer)
        if ok and type(a) == "table" then
            for _, v in pairs(a) do
                if type(v) == "string" then s[v] = true
                elseif type(v) == "table" and v.Id then s[v.Id] = true end
            end
        end
    end
    return s
end

local function petCounts()
    local cnt, mx = 0, 30
    if PetSys then
        pcall(function() cnt = PetSys.GetOwnedPetCount(LocalPlayer) or cnt end)
        pcall(function() mx = PetSys.MaxOwnedPetCount(LocalPlayer) or mx end)
    end
    return cnt, mx
end

local function sellJunk(maxRarity)
    if not R.petSell then return end
    local eq, lk = idSet("GetEquippedPetIds"), idSet("GetLockedPets")
    local batch = {}
    local function flush()
        if #batch > 0 then
            local b = batch; batch = {}
            pcall(function() R.petSell:InvokeServer(b) end)
            task.wait(0.6)
        end
    end
    for _, p in ipairs(ownedPets()) do
        if not eq[p.Id] and not lk[p.Id] and (RARITY[p.Rarity] or 1) <= maxRarity then
            batch[#batch + 1] = { Id = p.Id, Name = p.Name, Rarity = p.Rarity }
            if #batch >= 40 then flush() end
        end
    end
    flush()
end

local function equipBestPets()
    if not R.petEquip then return end
    local cap = 2
    pcall(function() cap = PetSys.MaxEquippedPetCount(LocalPlayer) or cap end)
    local eq = idSet("GetEquippedPetIds")
    local equipped = 0
    for _ in pairs(eq) do equipped = equipped + 1 end
    local list = ownedPets()
    table.sort(list, function(a, b) return (RARITY[a.Rarity] or 1) > (RARITY[b.Rarity] or 1) end)
    for _, p in ipairs(list) do
        if equipped >= cap then break end
        if not eq[p.Id] then
            pcall(function() R.petEquip:InvokeServer(p.Id) end)
            equipped = equipped + 1
            task.wait(0.55)
        end
    end
end

local function combineDups()
    if not R.petComb then return end
    local groups = {}
    for _, p in ipairs(ownedPets()) do
        if p.Rarity ~= "Legendary" then
            local key = tostring(p.Name) .. "|" .. tostring(p.Rarity)
            groups[key] = groups[key] or {}
            table.insert(groups[key], p)
        end
    end
    for _, list in pairs(groups) do
        if not State.alive then return end
        local sample = list[1]
        local req = 6
        pcall(function() req = PetSys.RequiredCombine(LocalPlayer, sample) or req end)
        if #list >= req then
            pcall(function() R.petComb:FireServer({ Id = sample.Id, Name = sample.Name, Rarity = sample.Rarity }) end)
            task.wait(3.1)
        end
    end
end

local function hatchLoop(getShop, getRate)
    while State.autoHatch and State.alive do
        local cnt, mx = petCounts()
        if cnt >= mx - 1 then
            combineDups()
            sellJunk(1)
            if select(1, petCounts()) >= mx - 1 then sellJunk(2) end
            equipBestPets()
        end
        if R.roll then pcall(function() R.roll:InvokeServer(getShop()) end) end
        local rate = math.clamp(getRate(), 1, 20)
        task.wait(1 / rate)
    end
end

----------------------------------------------------------------------
-- Teleport targets (client-side; the strength gate is bypassed since
-- movement is a local PivotTo)
----------------------------------------------------------------------
local function gatherTeleports()
    local list = {}
    local folder = ReplicatedFirst:FindFirstChild("Teleporters")
    if folder then
        for _, d in ipairs(folder:GetDescendants()) do
            local id = d:FindFirstChild("TeleportID")
            if id and d:IsA("BasePart") then
                local req = d:FindFirstChild("StatRequired")
                local nice = d.Name:gsub("AreaTarget", ""):gsub("Target", "")
                list[#list + 1] = { name = nice, part = d, req = req and req.Value or 0 }
            end
        end
    end
    table.sort(list, function(a, b) return a.req < b.req end)
    return list
end

local function teleportTo(part)
    local char = LocalPlayer.Character
    if char and part then
        pcall(function() char:PivotTo(part.CFrame * CFrame.new(0, 5, 0)) end)
    end
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local function resolveParent()
	local ok, h = pcall(function() return gethui() end)
	if ok and typeof(h) == "Instance" then return h end
	local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and cg then return cg end
	return LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
end

local function maxEnergy()
	if not R.conv then return false end
	giveEnergy(SAFE_MAX)
	return true
end

local W, H = 382, 486

local P = {
	bg = Color3.fromRGB(16, 17, 27),
	panel = Color3.fromRGB(20, 22, 34),
	card = Color3.fromRGB(26, 28, 42),
	card2 = Color3.fromRGB(34, 37, 54),
	card3 = Color3.fromRGB(45, 49, 72),
	stroke = Color3.fromRGB(60, 65, 98),
	txt = Color3.fromRGB(236, 238, 250),
	dim = Color3.fromRGB(151, 157, 188),
	acc = Color3.fromRGB(138, 99, 246),
	acc2 = Color3.fromRGB(99, 108, 246),
	acc3 = Color3.fromRGB(62, 210, 236),
	accTxt = Color3.fromRGB(255, 255, 255),
	ok = Color3.fromRGB(84, 214, 148),
	err = Color3.fromRGB(244, 98, 112),
	work = Color3.fromRGB(240, 190, 96),
}

local T = {
	fast = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	med = TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	slow = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	spring = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	back = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	backFast = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

local brandSeq = ColorSequence.new({
	ColorSequenceKeypoint.new(0, P.acc),
	ColorSequenceKeypoint.new(0.5, P.acc2),
	ColorSequenceKeypoint.new(1, P.acc3),
})

local function new(class, props)
	local inst = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			inst[k] = v
		end
	end
	return inst
end

local function tw(inst, info, goal)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

local function sway(inst, period, goal)
	local info = TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(color, thick, trans)
	return new("UIStroke", { Color = color or P.stroke, Thickness = thick or 1, Transparency = trans or 0 })
end

local function gradient(c1, c2, rot)
	return new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rot or 0 })
end

local function brandGradient(rot)
	return new("UIGradient", { Color = brandSeq, Rotation = rot or 0 })
end

local function pad(parent, t, b, l, r)
	local p = new("UIPadding", {
		PaddingTop = UDim.new(0, t),
		PaddingBottom = UDim.new(0, b or t),
		PaddingLeft = UDim.new(0, l or t),
		PaddingRight = UDim.new(0, r or l or t),
	})
	p.Parent = parent
	return p
end

local orderMap = setmetatable({}, { __mode = "k" })
local function nextOrder(parent)
	local n = (orderMap[parent] or 0) + 1
	orderMap[parent] = n
	return n
end

local EGGS = {"29Superhero","28Bank","27Prison","26Football","25Magic","24Robo","23Mineshaft","22Sewer","21Kitchen","20Asian","19Princess","18Treasury","17Apartment","16WildWest","15DeepSea","14Winter","13Retro","12Dino","11Tropical","10Science","9Candyland","8Space","7Disco","6Steampunk","5Medieval","4Farm","3Arcade","2Food","1Training","LobbyShop"}

local function prettyEgg(s)
	local r = string.gsub(s, "^%d+", "")
	r = string.gsub(r, "(%l)(%u)", "%1 %2")
	return r
end

local LANG = "en"
local binders = {}

local L = {
	en = {
		title = "Telegram: @sigmatik323", subtitle = "Discord @godlimaster",
		tab_gain = "Gain", tab_boosts = "Boosts", tab_pets = "Pets", tab_teleport = "Teleport",
		sec_energy = "Energy", sec_strength = "Strength", sec_rebirth = "Rebirth",
		sec_actions = "Quick actions", sec_egg = "Egg selection", sec_hatch = "Hatching",
		sec_manage = "Manage pets", sec_dest = "Destination",
		l_energy = "Energy amount", l_strength = "Strength amount", l_rate = "Hatch rate per second",
		l_egg = "Egg", l_area = "Area",
		ph_amount = "1m · 5.9e307 · max", ph_strength = "Amount, e.g. 1111111",
		btn_give_energy = "Give energy", btn_safe = "Safe", btn_fast = "Fast",
		btn_rebirth = "Rebirth now", tgl_autoreb = "Auto-rebirth",
		btn_codes = "Redeem all codes", btn_season = "Claim season pets",
		btn_power = "Max energy", btn_rewards = "Claim all rewards",
		tgl_autohatch = "Auto-hatch", btn_equip = "Equip best",
		btn_combine = "Combine dupes", btn_sell = "Sell Common", btn_teleport = "Teleport",
		empty_tp = "No destinations available",
		st_ready = "Ready when you are", st_working = "Working...", st_done = "Done",
		st_error = "Something went wrong", st_busy = "Already running...", st_invalid = "Enter a valid amount",
		st_energy = "Energy sent: %s", st_str_live = "Delivering: %s", st_str_done = "Strength: %s",
		st_reb_done = "Rebirths: %s",
		st_autoreb_on = "Auto-rebirth enabled", st_autoreb_off = "Auto-rebirth disabled",
		st_autohatch_on = "Auto-hatch enabled", st_autohatch_off = "Auto-hatch disabled",
		st_codes_done = "All codes redeemed", st_season_done = "Season pets claimed",
		st_power_done = "Energy reset to zero", st_rewards_done = "Rewards claimed",
		st_equipped = "Best pets equipped", st_combined = "Duplicates combined", st_sold = "Common pets sold",
		st_tp_done = "Teleported to %s", st_tp_none = "No destination selected", st_captured = "Strength source ready",
		tip_close = "Close & unload", tip_hide = "Hide / show (Right Ctrl)", tip_lang = "Switch language",
	},
	ru = {
		title = "Telegram: @sigmatik323", subtitle = "Discord @godlimaster",
		tab_gain = "Ресурсы", tab_boosts = "Бусты", tab_pets = "Питомцы", tab_teleport = "Телепорт",
		sec_energy = "Энергия", sec_strength = "Сила", sec_rebirth = "Перерождение",
		sec_actions = "Быстрые действия", sec_egg = "Выбор яйца", sec_hatch = "Вылупление",
		sec_manage = "Питомцы", sec_dest = "Локация",
		l_energy = "Количество энергии", l_strength = "Количество силы", l_rate = "Вылуплений в секунду",
		l_egg = "Яйцо", l_area = "Локация",
		ph_amount = "1m · 5.9e307 · max", ph_strength = "Кол-во, напр. 1111111",
		btn_give_energy = "Выдать энергию", btn_safe = "Безопасно", btn_fast = "Быстро",
		btn_rebirth = "Переродиться", tgl_autoreb = "Авто-перерождение",
		btn_codes = "Активировать коды", btn_season = "Сезонные питомцы",
		btn_power = "Макс. энергии", btn_rewards = "Забрать награды",
		tgl_autohatch = "Авто-вылупление", btn_equip = "Надеть лучших",
		btn_combine = "Объединить дубли", btn_sell = "Продать обычных", btn_teleport = "Телепортироваться",
		empty_tp = "Нет доступных точек",
		st_ready = "Готово к работе", st_working = "Выполняется...", st_done = "Готово",
		st_error = "Что-то пошло не так", st_busy = "Уже выполняется...", st_invalid = "Введите корректное значение",
		st_energy = "Выдано энергии: %s", st_str_live = "Доставка: %s", st_str_done = "Сила: %s",
		st_reb_done = "Перерождений: %s",
		st_autoreb_on = "Авто-перерождение включено", st_autoreb_off = "Авто-перерождение выключено",
		st_autohatch_on = "Авто-вылупление включено", st_autohatch_off = "Авто-вылупление выключено",
		st_codes_done = "Все коды активированы", st_season_done = "Сезонные питомцы получены",
		st_power_done = "Энергия обнулена", st_rewards_done = "Награды получены",
		st_equipped = "Лучшие питомцы надеты", st_combined = "Дубликаты объединены", st_sold = "Обычные питомцы проданы",
		st_tp_done = "Телепортация: %s", st_tp_none = "Точка не выбрана", st_captured = "Источник силы готов",
		tip_close = "Закрыть и выгрузить", tip_hide = "Скрыть / показать (Right Ctrl)", tip_lang = "Сменить язык",
	},
}

local function tr(key, ...)
	local pack = L[LANG] or L.en
	local s = pack[key]
	if s == nil then s = L.en[key] end
	if s == nil then return key end
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, s, ...)
		if ok then return res end
	end
	return s
end

local function bind(fn)
	binders[#binders + 1] = fn
	pcall(fn)
	return fn
end

local function register(inst, prop, key, ...)
	local args = { ... }
	bind(function()
		inst[prop] = tr(key, table.unpack(args))
	end)
	return inst
end

local setStatus, st, busyGuard, setLang, unload, switchTab, setShownToggle, refreshAreas
local moveIndicator, setActiveVisual
local statusLabel, statusDot, statusBase
local scale, window, content, mini, miniScale
local pillHi, enLbl, ruLbl
local tabButtons = {}
local pages = {}
local currentTab = 1
local indActive = 1
local hidden = false
local lastStatus
local autoRebRunning = false
local hatchRunning = false

local gui = new("ScreenGui", {
	Name = "QolPanel_" .. tostring(math.random(1000, 9999)),
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999999,
	AutoLocalize = false,
})
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
pcall(function() if protect_gui then protect_gui(gui) end end)
gui.Parent = resolveParent()

local holder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(W, H),
	BackgroundTransparency = 1,
	Visible = false,
})
scale = new("UIScale", { Scale = 0.6 })
scale.Parent = holder
holder.Parent = gui

mini = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(196, 46),
	BackgroundColor3 = P.card,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 2,
})
corner(14).Parent = mini
do
	local ms = stroke(P.acc, 1.4, 0.1)
	brandGradient(20).Parent = ms
	ms.Parent = mini
	local mg = gradient(Color3.fromRGB(30, 32, 50), P.card, 90)
	mg.Parent = mini
	local ml = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Text = "tg @sigmatik323",
		TextColor3 = P.txt,
		ZIndex = 3,
	})
	brandGradient(12).Parent = ml
	ml.Parent = mini
end
miniScale = new("UIScale", { Scale = 1 })
miniScale.Parent = mini
mini.Parent = gui
track(mini.Activated:Connect(function() if setShownToggle then setShownToggle() end end))
track(mini.MouseEnter:Connect(function() tw(miniScale, T.fast, { Scale = 1.05 }) end))
track(mini.MouseLeave:Connect(function() tw(miniScale, T.fast, { Scale = 1 }) end))

window = new("Frame", {
	BackgroundColor3 = P.bg,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 1, 0),
	ClipsDescendants = true,
	ZIndex = 1,
})
corner(18).Parent = window
local wStroke = stroke(P.stroke, 1.4, 0.2)
wStroke.Parent = window
gradient(Color3.fromRGB(24, 26, 44), P.bg, 90).Parent = window
window.Parent = holder

local header = new("Frame", { BackgroundTransparency = 1, Active = true, Size = UDim2.new(1, 0, 0, 58), ZIndex = 2 })
header.Parent = window

local titleLbl = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 10),
	Size = UDim2.new(0, 210, 0, 20),
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = P.txt,
	Text = "",
	ZIndex = 3,
})
brandGradient(18).Parent = titleLbl
register(titleLbl, "Text", "title")
titleLbl.Parent = header

local subLbl = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 32),
	Size = UDim2.new(0, 200, 0, 14),
	Font = Enum.Font.GothamMedium,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = P.dim,
	Text = "",
	ZIndex = 3,
})
register(subLbl, "Text", "subtitle")
subLbl.Parent = header

local divider = new("Frame", {
	BackgroundColor3 = P.stroke,
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 14, 0, 57),
	Size = UDim2.new(1, -28, 0, 1),
	ZIndex = 2,
})
divider.Parent = window

local pill = new("Frame", {
	BackgroundColor3 = P.card2,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -78, 0, 12),
	Size = UDim2.new(0, 64, 0, 26),
	ZIndex = 3,
})
corner(13).Parent = pill
stroke(P.stroke, 1, 0.45).Parent = pill
pillHi = new("Frame", {
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	Position = UDim2.new(0, 2, 0, 2),
	Size = UDim2.new(0.5, -3, 1, -4),
	ZIndex = 3,
})
corner(11).Parent = pillHi
brandGradient(0).Parent = pillHi
pillHi.Parent = pill
enLbl = new("TextButton", {
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0.5, 0, 1, 0),
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	Text = "EN",
	TextColor3 = P.accTxt,
	ZIndex = 4,
})
enLbl.Parent = pill
ruLbl = new("TextButton", {
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(0.5, 0, 1, 0),
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	Text = "RU",
	TextColor3 = P.dim,
	ZIndex = 4,
})
ruLbl.Parent = pill
pill.Parent = header

local hideBtn = new("TextButton", {
	AutoButtonColor = false,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -44, 0, 12),
	Size = UDim2.new(0, 26, 0, 26),
	BackgroundColor3 = P.card2,
	BorderSizePixel = 0,
	Text = "",
	ZIndex = 3,
})
corner(8).Parent = hideBtn
stroke(P.stroke, 1, 0.45).Parent = hideBtn
local hideGlyph = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 11, 0, 2),
	BackgroundColor3 = P.dim,
	BorderSizePixel = 0,
	ZIndex = 4,
})
corner(1).Parent = hideGlyph
hideGlyph.Parent = hideBtn
hideBtn.Parent = header

local closeBtn = new("TextButton", {
	AutoButtonColor = false,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.new(0, 26, 0, 26),
	BackgroundColor3 = P.card2,
	BorderSizePixel = 0,
	Text = "",
	ZIndex = 3,
})
corner(8).Parent = closeBtn
local closeStroke = stroke(P.stroke, 1, 0.45)
closeStroke.Parent = closeBtn
local xa = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 12, 0, 2),
	BackgroundColor3 = P.dim,
	BorderSizePixel = 0,
	Rotation = 45,
	ZIndex = 4,
})
corner(1).Parent = xa
xa.Parent = closeBtn
local xb = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 12, 0, 2),
	BackgroundColor3 = P.dim,
	BorderSizePixel = 0,
	Rotation = -45,
	ZIndex = 4,
})
corner(1).Parent = xb
xb.Parent = closeBtn
closeBtn.Parent = header

local tip = new("TextLabel", {
	BackgroundColor3 = P.card2,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.new(0, 168, 0, 26),
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = P.txt,
	TextTransparency = 1,
	Text = "",
	Visible = false,
	TextWrapped = true,
	ZIndex = 60,
})
corner(8).Parent = tip
stroke(P.stroke, 1, 0.3).Parent = tip
tip.Parent = window

local function attachTip(inst, key)
	track(inst.MouseEnter:Connect(function()
		tip.Text = tr(key)
		local bp, wp = inst.AbsolutePosition, window.AbsolutePosition
		local x = math.clamp(bp.X - wp.X + inst.AbsoluteSize.X / 2 - 84, 6, W - 174)
		local y = bp.Y - wp.Y + inst.AbsoluteSize.Y + 6
		tip.Position = UDim2.new(0, x, 0, y)
		tip.Visible = true
		tw(tip, T.fast, { TextTransparency = 0, BackgroundTransparency = 0.05 })
	end))
	track(inst.MouseLeave:Connect(function()
		tw(tip, T.fast, { TextTransparency = 1, BackgroundTransparency = 1 })
		task.delay(0.18, function()
			if tip.TextTransparency >= 1 then tip.Visible = false end
		end)
	end))
end

local tabbar = new("Frame", {
	BackgroundColor3 = P.card,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 12, 0, 66),
	Size = UDim2.new(1, -24, 0, 40),
	ZIndex = 2,
})
corner(12).Parent = tabbar
stroke(P.stroke, 1, 0.5).Parent = tabbar
tabbar.Parent = window

local indicator = new("Frame", {
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	Position = UDim2.new(0, 3, 0, 4),
	Size = UDim2.new(0.25, -6, 1, -8),
	ZIndex = 2,
})
corner(9).Parent = indicator
local indGrad = brandGradient(16)
indGrad.Parent = indicator
indicator.Parent = tabbar

local tabKeys = { "tab_gain", "tab_boosts", "tab_pets", "tab_teleport" }
for i = 1, 4 do
	local idx = i
	local b = new("TextButton", {
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = P.dim,
		Position = UDim2.new(0.25 * (i - 1), 0, 0, 0),
		Size = UDim2.new(0.25, 0, 1, 0),
		ZIndex = 3,
	})
	register(b, "Text", tabKeys[i])
	track(b.Activated:Connect(function() switchTab(idx) end))
	track(b.MouseEnter:Connect(function()
		if indActive ~= idx then tw(b, T.fast, { TextColor3 = P.txt }) end
	end))
	track(b.MouseLeave:Connect(function()
		if indActive ~= idx then tw(b, T.fast, { TextColor3 = P.dim }) end
	end))
	b.Parent = tabbar
	tabButtons[i] = b
end

content = new("Frame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 0, 0, 114),
	Size = UDim2.new(1, 0, 1, -174),
	ClipsDescendants = true,
	ZIndex = 2,
})
content.Parent = window

for i = 1, 4 do
	local pg = new("ScrollingFrame", {
		Active = true,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.fromScale((i == 1) and 0 or 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = P.acc,
		ScrollBarImageTransparency = 0.35,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = (i == 1),
		ZIndex = 2,
	})
	local lay = new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center })
	lay.Parent = pg
	pad(pg, 12, 14, 12, 12)
	track(lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		pg.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 22)
	end))
	pg.Parent = content
	pages[i] = pg
end

local statusCard = new("Frame", {
	BackgroundColor3 = P.card,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 12, 1, -50),
	Size = UDim2.new(1, -24, 0, 42),
	ZIndex = 2,
})
corner(11).Parent = statusCard
stroke(P.stroke, 1, 0.5).Parent = statusCard
gradient(P.card2, P.card, 90).Parent = statusCard
statusCard.Parent = window

statusDot = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundColor3 = P.dim,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 13, 0.5, 0),
	Size = UDim2.new(0, 8, 0, 8),
	ZIndex = 3,
})
corner(4).Parent = statusDot
statusDot.Parent = statusCard

statusBase = UDim2.new(0, 28, 0, 0)
statusLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = statusBase,
	Size = UDim2.new(1, -40, 1, 0),
	Font = Enum.Font.GothamSemibold,
	TextSize = 12.5,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	TextColor3 = P.txt,
	Text = "",
	TextWrapped = true,
	ZIndex = 3,
})
statusLabel.Parent = statusCard

setStatus = function(text, color)
	if not statusLabel then return end
	local c = color or P.dim
	statusLabel.Text = text
	statusLabel.TextColor3 = c
	tw(statusDot, T.med, { BackgroundColor3 = c })
	statusLabel.TextTransparency = 1
	statusLabel.Position = statusBase + UDim2.fromOffset(0, 5)
	tw(statusLabel, T.med, { TextTransparency = 0, Position = statusBase })
end

st = function(key, color, ...)
	lastStatus = { key = key, color = color, args = { ... } }
	setStatus(tr(key, ...), color)
end

busyGuard = function(key, fn)
	if State.busy[key] then
		st("st_busy", P.work)
		return
	end
	State.busy[key] = true
	task.spawn(function()
		local ok = pcall(fn)
		State.busy[key] = false
		if not ok then st("st_error", P.err) end
	end)
end

local function report() end

local function ripple(btn)
	local r = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.74,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
	corner(999).Parent = r
	r.Parent = btn
	local s = math.max(btn.AbsoluteSize.X, btn.AbsoluteSize.Y) * 2.1
	tw(r, T.slow, { Size = UDim2.fromOffset(s, s), BackgroundTransparency = 1 })
	task.delay(0.5, function() pcall(function() r:Destroy() end) end)
end

local function makeButton(parent, key, primary, onClick, sizeOverride)
	local btn = new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = primary and P.acc or P.card2,
		BorderSizePixel = 0,
		Size = sizeOverride or UDim2.new(1, 0, 0, 38),
		Text = "",
		ClipsDescendants = true,
	})
	corner(10).Parent = btn
	local sc = new("UIScale", { Scale = 1 })
	sc.Parent = btn
	if primary then brandGradient(18).Parent = btn end
	local base = primary and 0.25 or 0.5
	local strk = stroke(primary and P.acc or P.stroke, 1, base)
	strk.Parent = btn
	local lbl = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = primary and P.accTxt or P.txt,
		Text = "",
		ZIndex = 3,
	})
	register(lbl, "Text", key)
	lbl.Parent = btn
	track(btn.MouseEnter:Connect(function()
		tw(sc, T.fast, { Scale = 1.03 })
		tw(strk, T.fast, { Transparency = math.max(base - 0.3, 0), Color = primary and P.acc3 or P.acc })
	end))
	track(btn.MouseLeave:Connect(function()
		tw(sc, T.fast, { Scale = 1 })
		tw(strk, T.fast, { Transparency = base, Color = primary and P.acc or P.stroke })
	end))
	track(btn.MouseButton1Down:Connect(function() tw(sc, T.fast, { Scale = 0.96 }) end))
	track(btn.MouseButton1Up:Connect(function() tw(sc, T.backFast, { Scale = 1.03 }) end))
	track(btn.Activated:Connect(function()
		ripple(btn)
		if onClick then onClick() end
	end))
	if parent then
		btn.LayoutOrder = nextOrder(parent)
		btn.Parent = parent
	end
	return btn
end

local function makeInput(parent, labelKey, default, placeholderKey)
	local wrap = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56) })
	local lbl = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 2, 0, 0),
		Size = UDim2.new(1, -4, 0, 16),
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = P.dim,
		Text = "",
	})
	register(lbl, "Text", labelKey)
	lbl.Parent = wrap
	local box = new("TextBox", {
		BackgroundColor3 = P.card2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 36),
		Font = Enum.Font.GothamSemibold,
		TextSize = 15,
		TextColor3 = P.txt,
		PlaceholderColor3 = P.dim,
		Text = default or "",
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	corner(9).Parent = box
	pad(box, 0, 0, 12, 12)
	local strk = stroke(P.stroke, 1, 0.5)
	strk.Parent = box
	box.Parent = wrap
	if placeholderKey then register(box, "PlaceholderText", placeholderKey) end
	track(box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > 18 then box.Text = string.sub(box.Text, 1, 18) end
	end))
	track(box.Focused:Connect(function() tw(strk, T.fast, { Transparency = 0, Color = P.acc }) end))
	track(box.FocusLost:Connect(function() tw(strk, T.fast, { Transparency = 0.5, Color = P.stroke }) end))
	wrap.LayoutOrder = nextOrder(parent)
	wrap.Parent = parent
	return box
end

local function makeToggle(parent, labelKey, onSet)
	local row = new("TextButton", { BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Size = UDim2.new(1, 0, 0, 34) })
	local lbl = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 2, 0, 0),
		Size = UDim2.new(1, -62, 1, 0),
		Font = Enum.Font.GothamSemibold,
		TextSize = 13.5,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = P.txt,
		Text = "",
		ZIndex = 3,
	})
	register(lbl, "Text", labelKey)
	lbl.Parent = row
	local trackf = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = P.card3,
		BorderSizePixel = 0,
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 48, 0, 24),
		ZIndex = 3,
	})
	corner(12).Parent = trackf
	local ts = stroke(P.stroke, 1, 0.5)
	ts.Parent = trackf
	trackf.Parent = row
	local fill = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 3,
	})
	corner(12).Parent = fill
	brandGradient(0).Parent = fill
	fill.Parent = trackf
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = P.txt,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.new(0, 18, 0, 18),
		ZIndex = 4,
	})
	corner(9).Parent = knob
	knob.Parent = trackf
	local state = false
	local function apply(anim)
		if state then
			tw(ts, T.fast, { Transparency = 1 })
			tw(fill, T.fast, { BackgroundTransparency = 0 })
			tw(knob, anim and T.spring or T.fast, { Position = UDim2.new(1, -21, 0.5, 0), BackgroundColor3 = P.accTxt })
		else
			tw(ts, T.fast, { Transparency = 0.5 })
			tw(fill, T.fast, { BackgroundTransparency = 1 })
			tw(knob, anim and T.spring or T.fast, { Position = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = P.txt })
		end
	end
	apply(false)
	track(row.Activated:Connect(function()
		state = not state
		apply(true)
		if onSet then onSet(state) end
	end))
	row.LayoutOrder = nextOrder(parent)
	row.Parent = parent
	return { set = function(v) state = v and true or false; apply(true) end, get = function() return state end }
end

local function smallBtn(parent, w, h)
	local b = new("TextButton", {
		BackgroundColor3 = P.card2,
		BorderSizePixel = 0,
		Size = UDim2.new(0, w, 0, h),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
	})
	corner(8).Parent = b
	local strk = stroke(P.stroke, 1, 0.5)
	strk.Parent = b
	local sc = new("UIScale", { Scale = 1 })
	sc.Parent = b
	track(b.MouseEnter:Connect(function() tw(strk, T.fast, { Transparency = 0, Color = P.acc }) end))
	track(b.MouseLeave:Connect(function() tw(strk, T.fast, { Transparency = 0.5, Color = P.stroke }) end))
	track(b.MouseButton1Down:Connect(function() tw(sc, T.fast, { Scale = 0.9 }) end))
	track(b.MouseButton1Up:Connect(function() tw(sc, T.backFast, { Scale = 1 }) end))
	b.Parent = parent
	return b
end

local function glyph(parent, vertical)
	local g = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 11, 0, 2),
		BackgroundColor3 = P.txt,
		BorderSizePixel = 0,
		ZIndex = 4,
	})
	corner(1).Parent = g
	g.Parent = parent
	if vertical then
		local v = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 2, 0, 11),
			BackgroundColor3 = P.txt,
			BorderSizePixel = 0,
			ZIndex = 4,
		})
		corner(1).Parent = v
		v.Parent = parent
	end
	return g
end

local function chevron(parent, left)
	local holderF = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	holderF.Parent = parent
	local a = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, left and 1 or -1, 0.5, -3),
		Size = UDim2.new(0, 9, 0, 2),
		BackgroundColor3 = P.acc3,
		BorderSizePixel = 0,
		Rotation = left and -45 or 45,
		ZIndex = 4,
	})
	corner(1).Parent = a
	a.Parent = holderF
	local b = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, left and 1 or -1, 0.5, 3),
		Size = UDim2.new(0, 9, 0, 2),
		BackgroundColor3 = P.acc3,
		BorderSizePixel = 0,
		Rotation = left and 45 or -45,
		ZIndex = 4,
	})
	corner(1).Parent = b
	b.Parent = holderF
	return holderF
end

local function makeStepper(parent, labelKey, minV, maxV, default)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34) })
	local lbl = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 2, 0, 0),
		Size = UDim2.new(1, -112, 1, 0),
		Font = Enum.Font.GothamSemibold,
		TextSize = 13.5,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = P.txt,
		Text = "",
		ZIndex = 3,
	})
	register(lbl, "Text", labelKey)
	lbl.Parent = row
	local value = math.clamp(default, minV, maxV)
	local minus = smallBtn(row, 28, 28)
	minus.Position = UDim2.new(1, -100, 0.5, -14)
	glyph(minus, false)
	local plus = smallBtn(row, 28, 28)
	plus.Position = UDim2.new(1, -28, 0.5, -14)
	glyph(plus, true)
	local valBox = new("TextLabel", {
		BackgroundColor3 = P.card2,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -68, 0.5, -14),
		Size = UDim2.new(0, 38, 0, 28),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = P.txt,
		Text = tostring(value),
		ZIndex = 3,
	})
	corner(8).Parent = valBox
	stroke(P.stroke, 1, 0.5).Parent = valBox
	valBox.Parent = row
	local function refresh()
		valBox.Text = tostring(value)
		valBox.TextTransparency = 0.55
		tw(valBox, T.fast, { TextTransparency = 0 })
	end
	track(minus.Activated:Connect(function() value = math.clamp(value - 1, minV, maxV) refresh() end))
	track(plus.Activated:Connect(function() value = math.clamp(value + 1, minV, maxV) refresh() end))
	row.LayoutOrder = nextOrder(parent)
	row.Parent = parent
	return { get = function() return value end }
end

local function makeSelector(parent, captionKey, getCount, getLabel, emptyKey)
	local wrap = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50) })
	local cap = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 2, 0, 0),
		Size = UDim2.new(1, -4, 0, 14),
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = P.dim,
		Text = "",
		ZIndex = 3,
	})
	register(cap, "Text", captionKey)
	cap.Parent = wrap
	local left = smallBtn(wrap, 32, 30)
	left.Position = UDim2.new(0, 0, 0, 18)
	chevron(left, true)
	local right = smallBtn(wrap, 32, 30)
	right.Position = UDim2.new(1, -32, 0, 18)
	chevron(right, false)
	local center = new("TextLabel", {
		BackgroundColor3 = P.card2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 38, 0, 18),
		Size = UDim2.new(1, -76, 0, 30),
		Font = Enum.Font.GothamSemibold,
		TextSize = 13,
		TextColor3 = P.txt,
		Text = "",
		ClipsDescendants = true,
		TextWrapped = false,
		ZIndex = 3,
	})
	corner(8).Parent = center
	stroke(P.stroke, 1, 0.5).Parent = center
	pad(center, 0, 0, 8, 8)
	center.Parent = wrap
	local index = 1
	local function setCenter(t)
		center.Text = t
		center.TextTransparency = 0.6
		tw(center, T.fast, { TextTransparency = 0 })
	end
	local function refresh()
		local n = getCount()
		if n <= 0 then
			index = 1
			setCenter(emptyKey and tr(emptyKey) or "-")
			return
		end
		if index > n then index = n end
		if index < 1 then index = 1 end
		setCenter(getLabel(index))
	end
	track(left.Activated:Connect(function()
		local n = getCount()
		if n <= 0 then return end
		index = index - 1
		if index < 1 then index = n end
		refresh()
	end))
	track(right.Activated:Connect(function()
		local n = getCount()
		if n <= 0 then return end
		index = index + 1
		if index > n then index = 1 end
		refresh()
	end))
	bind(function() refresh() end)
	wrap.LayoutOrder = nextOrder(parent)
	wrap.Parent = parent
	return { getIndex = function() return index end, refresh = refresh }
end

local function makeCard(parent, titleKey)
	local card = new("Frame", {
		BackgroundColor3 = P.card,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 2,
	})
	corner(14).Parent = card
	stroke(P.stroke, 1, 0.5).Parent = card
	gradient(Color3.fromRGB(30, 32, 50), P.card, 90).Parent = card
	pad(card, 12, 12, 12, 12)
	local list = new("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder })
	list.Parent = card
	card.LayoutOrder = nextOrder(parent)
	card.Parent = parent
	track(list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		card.Size = UDim2.new(1, 0, 0, list.AbsoluteContentSize.Y + 24)
	end))
	if titleKey then
		local t = new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = P.acc3,
			Text = "",
			ZIndex = 3,
		})
		register(t, "Text", titleKey)
		t.LayoutOrder = nextOrder(card)
		t.Parent = card
	end
	return card
end

local function makeRow(parent, h)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h or 38) })
	local l = new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	l.Parent = row
	row.LayoutOrder = nextOrder(parent)
	row.Parent = parent
	return row
end

do
	local gp = pages[1]
	local c1 = makeCard(gp, "sec_energy")
	local energyBox = makeInput(c1, "l_energy", "1m", "ph_amount")
	makeButton(c1, "btn_give_energy", true, function()
		busyGuard("energy", function()
			local target = parseAmount(energyBox.Text)
			if not target then st("st_invalid", P.err) return end
			st("st_working", P.work)
			giveEnergy(target)
			st("st_energy", P.ok, fmt(target))
		end)
	end)

	local c2 = makeCard(gp, "sec_strength")
	local strengthBox = makeInput(c2, "l_strength", "1111111", "ph_strength")
	local row = makeRow(c2, 38)
	makeButton(row, "btn_safe", true, function()
		busyGuard("strength", function()
			local target = parseAmount(strengthBox.Text)
			if not target then st("st_invalid", P.err) return end
			st("st_working", P.work)
			local ok = giveStrength(target, function(delivered)
				st("st_str_live", P.work, fmt(delivered))
			end)
			st("st_str_done", ok and P.ok or P.err, fmt(readStrength() or target))
		end)
	end, UDim2.new(0.5, -4, 1, 0))
	makeButton(row, "btn_fast", false, function()
		busyGuard("strengthfast", function()
			local target = parseAmount(strengthBox.Text)
			if not target then st("st_invalid", P.err) return end
			st("st_working", P.work)
			local ok, given = giveStrengthFast(target)
			st("st_str_done", ok and P.ok or P.err, fmt(given or readStrength() or target))
		end)
	end, UDim2.new(0.5, -4, 1, 0))

	local c3 = makeCard(gp, "sec_rebirth")
	makeButton(c3, "btn_rebirth", true, function()
		busyGuard("rebirth", function()
			st("st_working", P.work)
			rebirthCycle(6)
			st("st_reb_done", P.ok, fmt(readRebirth() or 0))
		end)
	end)
	makeToggle(c3, "tgl_autoreb", function(on)
		State.autoRebirth = on
		if on then
			st("st_autoreb_on", P.ok)
			if not autoRebRunning then
				autoRebRunning = true
				task.spawn(function()
					while State.autoRebirth and State.alive do
						pcall(rebirthCycle, 6)
						task.wait(0.2)
					end
					autoRebRunning = false
				end)
			end
		else
			st("st_autoreb_off", P.dim)
		end
	end)
end

do
	local bp = pages[2]
	local c = makeCard(bp, "sec_actions")
	local function boost(key, fn, doneKey)
		busyGuard(key, function()
			st("st_working", P.work)
			fn(report)
			st(doneKey, P.ok)
		end)
	end
	makeButton(c, "btn_codes", true, function() boost("codes", redeemCodes, "st_codes_done") end)
	makeButton(c, "btn_season", false, function() boost("season", claimAllSeasonPets, "st_season_done") end)
	makeButton(c, "btn_power", false, function()
		busyGuard("maxenergy", function()
			st("st_working", P.work)
			maxEnergy()
			st("st_energy", P.ok, fmt(SAFE_MAX))
		end)
	end)
	makeButton(c, "btn_rewards", true, function() boost("rewards", claimRewards, "st_rewards_done") end)
end

do
	local pp = pages[3]
	local c1 = makeCard(pp, "sec_egg")
	local eggSel = makeSelector(c1, "l_egg", function() return #EGGS end, function(i) return prettyEgg(EGGS[i]) end)

	local c2 = makeCard(pp, "sec_hatch")
	local rateApi = makeStepper(c2, "l_rate", 1, 20, 4)
	makeToggle(c2, "tgl_autohatch", function(on)
		State.autoHatch = on
		if on then
			st("st_autohatch_on", P.ok)
			if not hatchRunning then
				hatchRunning = true
				task.spawn(function()
					pcall(function()
						hatchLoop(function() return EGGS[eggSel.getIndex()] end, function() return rateApi.get() end)
					end)
					hatchRunning = false
				end)
			end
		else
			st("st_autohatch_off", P.dim)
		end
	end)

	local c3 = makeCard(pp, "sec_manage")
	makeButton(c3, "btn_equip", true, function()
		busyGuard("equip", function()
			st("st_working", P.work)
			equipBestPets()
			st("st_equipped", P.ok)
		end)
	end)
	local row = makeRow(c3, 38)
	makeButton(row, "btn_combine", false, function()
		busyGuard("combine", function()
			st("st_working", P.work)
			combineDups()
			st("st_combined", P.ok)
		end)
	end, UDim2.new(0.5, -4, 1, 0))
	makeButton(row, "btn_sell", false, function()
		busyGuard("sell", function()
			st("st_working", P.work)
			sellJunk(1)
			st("st_sold", P.ok)
		end)
	end, UDim2.new(0.5, -4, 1, 0))
end

local areas = {}
local tpSel

do
	local tpp = pages[4]
	local c = makeCard(tpp, "sec_dest")
	tpSel = makeSelector(c, "l_area",
		function() return #areas end,
		function(i)
			local a = areas[i]
			if not a then return "-" end
			return tostring(a.name) .. "  (" .. fmt(a.req) .. ")"
		end,
		"empty_tp")
	makeButton(c, "btn_teleport", true, function()
		if #areas == 0 then
			st("st_tp_none", P.err)
			return
		end
		busyGuard("teleport", function()
			local a = areas[tpSel.getIndex()]
			if not a or not a.part then
				st("st_tp_none", P.err)
				return
			end
			teleportTo(a.part)
			st("st_tp_done", P.ok, tostring(a.name))
		end)
	end)
end

refreshAreas = function()
	local ok, res = pcall(gatherTeleports)
	if ok and type(res) == "table" then
		areas = res
	else
		areas = {}
	end
	if tpSel then tpSel.refresh() end
end
refreshAreas()

setActiveVisual = function(i)
	indActive = i
	for j, b in ipairs(tabButtons) do
		tw(b, T.fast, { TextColor3 = (j == i) and P.accTxt or P.dim })
	end
end

moveIndicator = function(i)
	tw(indicator, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0.25, 4, 1, -8) })
	task.delay(0.15, function()
		if indActive == i then
			tw(indicator, T.back, { Size = UDim2.new(0.25, -6, 1, -8) })
		end
	end)
	tw(indicator, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.25 * (i - 1), 3, 0, 4) })
end

switchTab = function(i)
	if not pages[i] or i == currentTab then return end
	local dir = (i > currentTab) and 1 or -1
	local old = currentTab
	local outP, inP = pages[old], pages[i]
	inP.Position = UDim2.fromScale(dir, 0)
	inP.Visible = true
	tw(inP, T.slow, { Position = UDim2.fromScale(0, 0) })
	tw(outP, T.slow, { Position = UDim2.fromScale(-dir, 0) })
	task.delay(0.34, function()
		if currentTab ~= old then outP.Visible = false end
	end)
	currentTab = i
	moveIndicator(i)
	setActiveVisual(i)
	if i == 4 then refreshAreas() end
end

setLang = function(lng)
	if lng == LANG then return end
	LANG = lng
	for _, fn in ipairs(binders) do pcall(fn) end
	local right = (lng == "ru")
	tw(pillHi, T.med, { Position = right and UDim2.new(0.5, 1, 0, 2) or UDim2.new(0, 2, 0, 2) })
	tw(enLbl, T.fast, { TextColor3 = right and P.dim or P.accTxt })
	tw(ruLbl, T.fast, { TextColor3 = right and P.accTxt or P.dim })
	if not hidden then
		scale.Scale = 0.985
		tw(scale, T.spring, { Scale = 1 })
	end
	if lastStatus then
		setStatus(tr(lastStatus.key, table.unpack(lastStatus.args)), lastStatus.color)
	end
end

attachTip(closeBtn, "tip_close")
attachTip(hideBtn, "tip_hide")
attachTip(enLbl, "tip_lang")
attachTip(ruLbl, "tip_lang")

track(enLbl.Activated:Connect(function() setLang("en") end))
track(ruLbl.Activated:Connect(function() setLang("ru") end))

track(closeBtn.MouseEnter:Connect(function()
	tw(closeBtn, T.fast, { BackgroundColor3 = P.err })
	tw(closeStroke, T.fast, { Transparency = 0.1, Color = P.err })
	tw(xa, T.fast, { BackgroundColor3 = P.accTxt })
	tw(xb, T.fast, { BackgroundColor3 = P.accTxt })
end))
track(closeBtn.MouseLeave:Connect(function()
	tw(closeBtn, T.fast, { BackgroundColor3 = P.card2 })
	tw(closeStroke, T.fast, { Transparency = 0.45, Color = P.stroke })
	tw(xa, T.fast, { BackgroundColor3 = P.dim })
	tw(xb, T.fast, { BackgroundColor3 = P.dim })
end))
track(hideBtn.MouseEnter:Connect(function()
	tw(hideBtn, T.fast, { BackgroundColor3 = P.card3 })
	tw(hideGlyph, T.fast, { BackgroundColor3 = P.txt })
end))
track(hideBtn.MouseLeave:Connect(function()
	tw(hideBtn, T.fast, { BackgroundColor3 = P.card2 })
	tw(hideGlyph, T.fast, { BackgroundColor3 = P.dim })
end))
track(hideBtn.Activated:Connect(function() setShownToggle() end))

do
	local dragging, dragStart, startPos = false, nil, nil
	track(header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = holder.Position
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			holder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

local function setHidden(h)
	hidden = h
	if h then
		mini.Position = holder.Position
		tw(scale, T.med, { Scale = 0 })
		tw(window, T.med, { BackgroundTransparency = 1 })
		task.delay(0.24, function()
			if hidden then holder.Visible = false end
		end)
		mini.Visible = true
		miniScale.Scale = 0.7
		tw(miniScale, T.spring, { Scale = 1 })
	else
		holder.Position = mini.Position
		mini.Visible = false
		holder.Visible = true
		scale.Scale = 0.7
		tw(scale, T.spring, { Scale = 1 })
		tw(window, T.med, { BackgroundTransparency = 0 })
	end
end
setShownToggle = function() setHidden(not hidden) end

track(UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.RightControl then
		setShownToggle()
	end
end))

track(LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

onStrengthCaptured = function()
	st("st_captured", P.ok)
end

sway(indGrad, 5.5, { Rotation = 48 })

setActiveVisual(1)
moveIndicator(1)
st("st_ready", P.dim)

holder.Visible = true
scale.Scale = 0.6
tw(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
tw(window, T.med, { BackgroundTransparency = 0 })

unload = function()
	State.alive = false
	State.autoRebirth = false
	State.autoHatch = false
	pcall(function()
		tw(scale, T.med, { Scale = 0.6 })
		tw(window, T.med, { BackgroundTransparency = 1 })
		if mini then mini.Visible = false end
	end)
	task.delay(0.26, function()
		for _, c in ipairs(connections) do
			pcall(function() c:Disconnect() end)
		end
		table.clear(connections)
		pcall(function() gui:Destroy() end)
	end)
end

track(closeBtn.Activated:Connect(function() unload() end))
