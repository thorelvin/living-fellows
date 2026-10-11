SurvivorCompanion = { GameplayUtil = {}, OddballAnimals = {} }
local U = SurvivorCompanion.GameplayUtil
SC_ANIMAL_SPAWN_FIXTURE = { squares = {}, animals = {}, nextId = 1000 }
local F = SC_ANIMAL_SPAWN_FIXTURE

function U.call(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return nil, false end
    local okay, value = pcall(fn, object, ...)
    return okay and value or nil, okay
end
function U.gridSquare(x, y, z)
    return F.squares[tostring(x) .. ":" .. tostring(y)
        .. ":" .. tostring(z or 0)]
end
function U.isClearActorSpawnSquare(square)
    return square ~= nil and square.chair ~= true
end
function U.nowMs() return 1000 end
function U.position(value)
    return value and value.x, value and value.y, value and value.z
end
function F.square(x, y, z, room)
    local square = { x = x, y = y, z = z or 0, room = room }
    function square:getRoom() return self.room end
    F.squares[x .. ":" .. y .. ":" .. (z or 0)] = square
    return square
end

local cell = { animals = F.animals }
function cell:getAnimals() return self.animals end
function getCell() return cell end
AnimalDefinitions = { getDef = function()
    return { getBreedByName = function(_, breed) return breed end }
end }
function addAnimal(_, x, y, z, kind, breed)
    F.nextId = F.nextId + 1
    local animal = { x = x, y = y, z = z, kind = kind,
        breed = breed, id = F.nextId, data = {} }
    function animal:setCustomName(name) self.name = name end
    function animal:setWild(wild) self.wild = wild end
    function animal:getModData() return self.data end
    function animal:addToWorld() self.added = true end
    function animal:removeFromWorld() self.removed = true end
    function animal:getAnimalID() return self.id end
    function animal:getOnlineID() return -1 end
    F.animals[#F.animals + 1] = animal
    return animal
end
