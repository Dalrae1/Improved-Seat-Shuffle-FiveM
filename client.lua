local entityEnumerator = {
    __gc = function(enum)
      if enum.destructor and enum.handle then
        enum.destructor(enum.handle)
      end
      enum.destructor = nil
      enum.handle = nil
    end
}
  
local function EnumerateEntities(initFunc, moveFunc, disposeFunc)
    return coroutine.wrap(function()
      local iter, id = initFunc()
      if not id or id == 0 then
        disposeFunc(iter)
        return
      end
      
      local enum = {handle = iter, destructor = disposeFunc}
      setmetatable(enum, entityEnumerator)
      
      local next = true
      repeat
        coroutine.yield(id)
        next, id = moveFunc(iter)
      until not next
      
      enum.destructor, enum.handle = nil, nil
      disposeFunc(iter)
    end)
end

function EnumerateVehicles()
    return EnumerateEntities(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
end

function pairsByKeys (t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0
    local iter = function()
        i = i + 1
        if a[i] == nil then return nil
            else return a[i], t[a[i]]
        end
    end
    return iter
end

function GetClosestVehicles(pos, radius)
    local vehicles = {}
    local sortedVehicles = {}
    for vehicle in EnumerateVehicles() do
        local vp = GetEntityCoords(vehicle)
        local dist = GetDistanceBetweenCoords(vp.x, vp.y, vp.z, pos.x, pos.y, pos.z, true)
        if dist < radius then
            vehicles[dist] = vehicle
        end
    end
    for i,v in pairsByKeys(vehicles) do
        table.insert(sortedVehicles,v)
    end
    return sortedVehicles
end

function getNextAvailablePassengerSeat(veh)
    if GetVehicleModelNumberOfSeats(GetEntityModel(veh)) > 0 then
        for i=0,GetVehicleModelNumberOfSeats(GetEntityModel(veh))-1 do -- Exclude driver
            if IsVehicleSeatFree(veh, i) then
                return i
            end
        end
    end
    return false
end
function getSeatPedIsIn(ped, veh)
    if GetVehicleModelNumberOfSeats(GetEntityModel(veh)) > 0 then
        for i=-1,GetVehicleModelNumberOfSeats(GetEntityModel(veh))-2 do
            if GetPedInVehicleSeat(veh, i) == ped then
                return i
            end
        end
    end
    return false
end

function isPedPlayer(ped)
    for _, player in pairs(GetActivePlayers()) do
        if GetPlayerPed(player) == ped then
            return true
        end
    end
    return false
end
local isShuffling = false
local didActuallyExit = false
local _, group1Hash = AddRelationshipGroup("group1")
local _, group2Hash = AddRelationshipGroup("group2")
local timing = 1
CreateThread(function()
    while true do
        local closestVeh = GetClosestVehicles(GetEntityCoords(PlayerPedId()), 10)[1]
        if closestVeh then
            timing = 1
        else
            timing = 1000
        end
        Wait(1000)
    end
end)
CreateThread(function()
    while true do
        Wait(timing)
        local myPed = PlayerPedId()
        if IsPedInAnyVehicle(myPed, false) then
            local myVehicle = GetVehiclePedIsIn(myPed, false)
            if not isShuffling then
                --[[ Prevent player from being kicked out of back seats ]]
                if IsControlJustPressed(0, 75) then -- F
                    didActuallyExit = true
                    CreateThread(function()
                        repeat Wait(0) until not (GetIsTaskActive(PlayerPedId(), 2))
                        didActuallyExit = false
                    end)
                end
                if not didActuallyExit and GetIsTaskActive(myPed, 2) and not IsControlJustPressed(0, 75) then-- Is exiting a vehicle but did not press F
                    SetPedIntoVehicle(myPed, myVehicle, getSeatPedIsIn(myPed, GetVehiclePedIsIn(myPed, true)))
                end
                --[[ Allow player to get out of vehicle if bugged ]]
                if IsControlJustPressed(0, 75) and IsPedInAnyVehicle(PlayerPedId()) then -- Pressed F and is in vehicle
                    TaskLeaveVehicle(PlayerPedId(), GetVehiclePedIsIn(PlayerPedId(), true), 64)
                end
                --[[ Prevent auto shuffling in an empty vehicle ]]
                if GetPedInVehicleSeat(myVehicle, 0) == PlayerPedId() and GetIsTaskActive(PlayerPedId(), 165) and not isShuffling then
                    SetPedIntoVehicle(PlayerPedId(), myVehicle, 0)
                end
            end
        else
            isShuffling = false
            if GetIsTaskActive(PlayerPedId(), 195) and (IsControlPressed(0,32) or IsControlPressed(0,33) or IsControlPressed(0,34) or IsControlPressed(0,35)) then -- If is trying to move while entering vehicle
                ClearPedTasks(PlayerPedId())
            end
            --[[ Allow player to enter passenger seat when pressing G]]
            if IsControlJustPressed(0, 47) and not IsPedInAnyVehicle(PlayerPedId()) then
                local closestVehicle = GetClosestVehicles(GetEntityCoords(PlayerPedId()), 10.0)[1]
                if closestVehicle then
                    local freeSeat = getNextAvailablePassengerSeat(closestVehicle)
                    if freeSeat then
                        TaskEnterVehicle(PlayerPedId(),closestVehicle, 10.0, freeSeat, 1.0, 0, 0)
                    end
                end
            end
            --[[ Prevent peds from being scared ]]
            if IsPedInAnyVehicle(PlayerPedId(), true) then -- Is trying to get into a vehicle
                SetRelationshipBetweenGroups(0, group1Hash, group2Hash)
                local veh = GetVehiclePedIsEntering(PlayerPedId())
                if DoesEntityExist(veh) then
                    for seatIndex = -1,GetVehicleModelNumberOfSeats(GetEntityModel(veh))-2 do
                        if not IsVehicleSeatFree(veh, seatIndex) then
                            local ped = GetPedInVehicleSeat(veh, seatIndex)
                            if DoesEntityExist(ped) then
                                ClearPedTasks(ped)
                                SetPedRelationshipGroupHash(PlayerPedId(), group1Hash)
                                SetPedRelationshipGroupHash(ped, group2Hash)
                            end
                        end
                    end
                end
            end
        end
    end
end)

RegisterCommand("shuff", function(source, args, raw)
    if not GetIsTaskActive(PlayerPedId(), 165) and IsPedInAnyVehicle(PlayerPedId(), false) then
        isShuffling = true
        ClearRelationshipBetweenGroups(0, group1Hash, group2Hash)
        TaskShuffleToNextVehicleSeat(PlayerPedId(), GetVehiclePedIsIn(PlayerPedId()))
        repeat Wait(0) until not GetIsTaskActive(PlayerPedId(), 165)
        isShuffling = false
    end
end)
