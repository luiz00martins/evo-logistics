-- FILE MANIPULATION FUNCTIONS
local function file_exists(filepath)
    local f = io.open(filepath, "r")
    if f ~= nil then 
        io.close(f)
        return true
    end
    return false
end

local function storeFile(filepath, content)
    local writefile = fs.open(filepath, "w")
    writefile.write(content)
    writefile.close()
end

local function downloadfile(filepath, url)
    if not http.checkURL(url) then
        print("ERROR: URL '" .. url .. "' is blocked. Unable to fetch.")
        return false
    end

    local result = http.get(url)
    if result == nil then
        print("ERROR: Unable to reach '" .. url .. "'")
        return false
    end

    storeFile(filepath, result.readAll())
    return true
end

-- MAIN PROGRAM
local args = {...}

local BASE_FOLDER = "/evo-logistics"
local base_url = "https://raw.githubusercontent.com/luiz00martins/evo-logistics/main"
local files = {
    ["init.lua"] = "/init.lua",

    ["core/abstract.lua"] = "/core/abstract.lua",
    ["core/barrel.lua"] = "/core/barrel.lua",
    ["core/bulk.lua"] = "/core/bulk.lua",
    ["core/crafting.lua"] = "/core/crafting.lua",
    ["core/interface.lua"] = "/core/interface.lua",
    ["core/ordered.lua"] = "/core/ordered.lua",
    ["core/shaped.lua"] = "/core/shaped.lua",
    ["core/shapeless.lua"] = "/core/shapeless.lua",
    ["core/standard.lua"] = "/core/standard.lua",

    ["tests/mocks/peripheral.lua"] = "/tests/mocks/peripheral.lua",
    ["tests/logistics.lua"] = "/tests/logistics.lua",
    ["tests/memoized.lua"] = "/tests/memoized.lua",
    ["tests/tests.lua"] = "/tests/tests.lua",

    ["utils/class.lua"] = "/utils/class.lua",
    ["utils/dl_list.lua"] = "/utils/dl_list.lua",
    ["utils/inventories.lua"] = "/utils/inventories.lua",
    ["utils/memoized.lua"] = "/utils/memoized.lua",
    ["utils/queue.lua"] = "/utils/queue.lua",
    ["utils/utils.lua"] = "/utils/utils.lua",
}

if args[1] == "install" or args[1] == nil then
    print("Installing evo-logistics...")
    fs.makeDir(BASE_FOLDER)

    for file_name, path in pairs(files) do
        print("Downloading " .. file_name .. "...")
        if not downloadfile(BASE_FOLDER .. path, base_url .. path) then
            return false
        end
    end
    print("evo-logistics successfully installed!")

elseif args[1] == "update" then
    print("Updating evo-logistics...")
    for file_name, path in pairs(files) do
        print("Updating " .. file_name .. "...")
        if not downloadfile(BASE_FOLDER .. path, base_url .. path) then
            return false
        end
    end
    print("evo-logistics successfully updated!")

elseif args[1] == "remove" then
    print("Removing evo-logistics...")
    fs.delete(BASE_FOLDER)
    print("evo-logistics successfully removed!")

else
    print("Invalid argument: " .. args[1])
    print("Usage: ccpt-install [install|update|remove]")
end

