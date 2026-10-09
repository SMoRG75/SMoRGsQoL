-- Checks the locale files against the L["..."] keys used in the code.
-- Run from the repository root: lua tests/locales.lua
-- Fails on a translation whose English key is no longer used (stale or
-- mistyped) or whose format specifiers differ from the key. Lists missing
-- translations without failing, since English is the fallback.

local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

-- Every L["..."] literal in a chunk of Lua source.
local function collectKeys(source, into)
    for key in source:gmatch('L%["(.-[^\\])"%]') do
        into[key] = true
    end
    return into
end

local codeFiles, localeFiles = {}, {}
for line in io.lines("SMoRGsQoL.toc") do
    local file = line:gsub("\r$", ""):match("^([^#].-%.lua)%s*$")
    if file and not file:find("^Libs[\\/]") then
        file = file:gsub("\\", "/")
        if file:find("^Locales/") then
            if file ~= "Locales/Locales.lua" then
                localeFiles[#localeFiles + 1] = file
            end
        else
            codeFiles[#codeFiles + 1] = file
        end
    end
end

local used = {}
for _, file in ipairs(codeFiles) do
    collectKeys(readFile(file), used)
end
local usedCount = 0
for _ in pairs(used) do usedCount = usedCount + 1 end

local function specifiers(text)
    local list = {}
    for spec in text:gmatch("%%[%d%.]*[sdf%%]") do
        list[#list + 1] = spec
    end
    return table.concat(list, " ")
end

local failures = 0
for _, file in ipairs(localeFiles) do
    local source = readFile(file)
    local translated, count = {}, 0
    for key, value in source:gmatch('L%["(.-[^\\])"%]%s*=%s*"(.-[^\\])"') do
        count = count + 1
        if translated[key] then
            print(file .. ": duplicate key: " .. key)
            failures = failures + 1
        end
        translated[key] = true
        if not used[key] then
            print(file .. ": key is not used in the code: " .. key)
            failures = failures + 1
        elseif specifiers(key) ~= specifiers(value) then
            print(file .. ": format specifiers differ: " .. key)
            failures = failures + 1
        end
        local colorsKey = select(2, key:gsub("|c%x%x%x%x%x%x%x%x", ""))
        local colorsValue = select(2, value:gsub("|c%x%x%x%x%x%x%x%x", ""))
        if colorsKey ~= colorsValue then
            print(file .. ": color codes differ: " .. key)
            failures = failures + 1
        end
    end
    local missing = {}
    for key in pairs(used) do
        if not translated[key] then missing[#missing + 1] = key end
    end
    table.sort(missing)
    print(string.format("%s: %d of %d keys translated", file, count, usedCount))
    for _, key in ipairs(missing) do
        print("  missing: " .. key)
    end
end

-- Load each locale the way the client does and format every translation.
local function sampleArgs(text)
    local args = {}
    for conv in text:gmatch("%%[%d%.]*([sdf])") do
        args[#args + 1] = conv == "s" and "x" or 1
    end
    return args
end

for _, file in ipairs(localeFiles) do
    local locale = file:match("([%a]+)%.lua$")
    local sqol = {}
    GetLocale = function() return locale end
    assert(loadfile("Locales/Locales.lua"))("SMoRGsQoL", sqol)
    assert(loadfile(file))("SMoRGsQoL", sqol)
    if sqol.L["ON"] == "ON" then
        print(file .. ": translations did not load for " .. locale)
        failures = failures + 1
    end
    for key in pairs(used) do
        local value = sqol.L[key]
        local ok, err = pcall(string.format, value, (table.unpack or unpack)(sampleArgs(key)))
        if not ok then
            print(file .. ": cannot format " .. key .. ": " .. tostring(err))
            failures = failures + 1
        end
    end
end
GetLocale = nil

-- Other locales must not pick up a translation.
local english = {}
assert(loadfile("Locales/Locales.lua"))("SMoRGsQoL", english)
for _, file in ipairs(localeFiles) do
    assert(loadfile(file))("SMoRGsQoL", english)
end
if english.L["ON"] ~= "ON" then
    print("enUS picked up a translation")
    failures = failures + 1
end

if failures > 0 then
    print(failures .. " problem(s) found")
    os.exit(1)
end
print("PASS: locale files match the code")
