if not lib.checkDependency('ox_lib', '3.30.0', true) then return end

lib.locale()

local utils = require 'client.utils'
local state = require 'client.state'
local options = require 'client.api'.getTargetOptions()

require 'client.debug'
require 'client.defaults'
require 'client.compat.qtarget'

local function safeRegisterCommand(name, callback, opts)
    if type(lib.registerCommand) == 'function' then
        local ok, err = pcall(lib.registerCommand, name, callback, opts)
        if ok then
            return
        end
        print(('ox_target: lib.registerCommand failed, falling back to RegisterCommand: %s'):format(tostring(err)))
    end

    RegisterCommand(name, callback, false)
end

local SendNuiMessage = SendNuiMessage
local GetEntityCoords = GetEntityCoords
local GetEntityType = GetEntityType
local HasEntityClearLosToEntity = HasEntityClearLosToEntity
local GetEntityBoneIndexByName = GetEntityBoneIndexByName
local GetEntityBonePosition_2 = GetEntityBonePosition_2
local GetEntityModel = GetEntityModel
local IsDisabledControlJustPressed = IsDisabledControlJustPressed
local DisableControlAction = DisableControlAction
local DisablePlayerFiring = DisablePlayerFiring
local GetModelDimensions = GetModelDimensions
local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords
local currentTarget = {}
local currentMenu
local menuChanged
local menuHistory = {}
local nearbyZones

local themeMenuOpen = false

local themeMenuOptions = {
    { label = 'Green',  args = 'green',  icon = 'circle', iconColor = '#8cff50', theme = { primary = '#80ff49', light = '#a5ff66', bright = '#d4ff99', rgb = '128, 255, 73',  icon = '#8cff50' } },
    { label = 'Gold',   args = 'gold',   icon = 'circle', iconColor = '#ffd700', theme = { primary = '#ffd700', light = '#ffeb99', bright = '#ffeb99', rgb = '255, 215, 0',   icon = '#ffd700' } },
    { label = 'Blue',   args = 'blue',   icon = 'circle', iconColor = '#1e90ff', theme = { primary = '#00bfff', light = '#1e90ff', bright = '#87ceeb', rgb = '0, 191, 255',   icon = '#1e90ff' } },
    { label = 'Purple', args = 'purple', icon = 'circle', iconColor = '#ee82ee', theme = { primary = '#da70d6', light = '#ee82ee', bright = '#ff69b4', rgb = '218, 112, 214', icon = '#ee82ee' } },
    { label = 'Red',    args = 'red',    icon = 'circle', iconColor = '#ff6b6b', theme = { primary = '#ff4444', light = '#ff6b6b', bright = '#ff8888', rgb = '255, 68, 68',   icon = '#ff6b6b' } },
    { label = 'Cyan',   args = 'cyan',   icon = 'circle', iconColor = '#00ffff', theme = { primary = '#00ffff', light = '#00eeee', bright = '#7ffbff', rgb = '0, 255, 255',   icon = '#00ffff' } },
    { label = 'Orange', args = 'orange', icon = 'circle', iconColor = '#ffaa44', theme = { primary = '#ff8800', light = '#ffaa44', bright = '#ffcc88', rgb = '255, 136, 0',   icon = '#ffaa44' } },
    { label = 'Pink',   args = 'pink',   icon = 'circle', iconColor = '#ff85c2', theme = { primary = '#ff69b4', light = '#ff85c2', bright = '#ffb3d9', rgb = '255, 105, 180', icon = '#ff85c2' } },
    { label = 'White',  args = 'white',  icon = 'circle', iconColor = '#f0f0f0', theme = { primary = '#e0e0e0', light = '#f0f0f0', bright = '#ffffff', rgb = '224, 224, 224', icon = '#f0f0f0' } },
    { label = 'Teal',   args = 'teal',   icon = 'circle', iconColor = '#00cccc', theme = { primary = '#00b4b4', light = '#00cccc', bright = '#66dddd', rgb = '0, 180, 180',   icon = '#00cccc' } },
}

local function openThemeMenu()
    if state.isActive() then return end

    themeMenuOpen = true
    state.setNuiFocus(true, true)
    state.setActive(true)
    SendNuiMessage(json.encode({ event = 'visible', state = true }))

    CreateThread(function()
        while state.isActive() do
            DisablePlayerFiring(cache.playerId, true)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 8, true)
            DisableControlAction(0, 9, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 322, true)

            if IsDisabledControlJustPressed(0, 194) or IsDisabledControlJustPressed(0, 322) then
                themeMenuOpen = false
                state.setNuiFocus(false, false)
                state.setActive(false)
                SendNuiMessage('{"event": "visible", "state": false}')
            end

            Wait(0)
        end
    end)

    CreateThread(function()
        Wait(50)
        local savedTheme = GetResourceKvpString('ox_target_theme') or 'green'
        local opts = {}
        for i, opt in ipairs(themeMenuOptions) do
            opts[i] = {
                label    = opt.label,
                args     = opt.args,
                icon     = opt.args == savedTheme and 'fa-circle-check' or 'fa-circle',
                iconColor = opt.iconColor,
                theme    = opt.theme,
            }
        end
        SendNuiMessage(json.encode({
            event = 'setTarget',
            header = 'ox_target Theme',
            options = { themes = opts },
        }))
    end)
end

-- Load saved theme on startup
CreateThread(function()
    Wait(1000) -- Wait for NUI to load
    local savedTheme = GetResourceKvpString('ox_target_theme')

    if savedTheme then
        for i = 1, 3 do
            SendNuiMessage(json.encode({ event = 'setTheme', theme = savedTheme }))
            Wait(500)
        end
    end
end)

-- Toggle ox_target, instead of holding the hotkey
local toggleHotkey = GetConvarInt('ox_target:toggleHotkey', 0) == 1
local mouseButton = GetConvarInt('ox_target:leftClick', 1) == 1 and 24 or 25
local debug = GetConvarInt('ox_target:debug', 0) == 1
local vec0 = vec3(0, 0, 0)

---@param option OxTargetOption
---@param distance number
---@param endCoords vector3
---@param entityHit? number
---@param entityType? number
---@param entityModel? number | false
local function shouldHide(option, distance, endCoords, entityHit, entityType, entityModel)
    if option.menuName ~= currentMenu then
        return true
    end

    if distance > (option.distance or 7) then
        return true
    end

    if option.groups and not utils.hasPlayerGotGroup(option.groups) then
        return true
    end

    if option.items and not utils.hasPlayerGotItems(option.items, option.anyItem) then
        return true
    end

    local bone = entityModel and option.bones or nil

    if bone then
        ---@cast entityHit number
        ---@cast entityType number
        ---@cast entityModel number

        local _type = type(bone)

        if _type == 'string' then
            local boneId = GetEntityBoneIndexByName(entityHit, bone)

            if boneId ~= -1 and #(endCoords - GetEntityBonePosition_2(entityHit, boneId)) <= 2 then
                bone = boneId
            else
                return true
            end
        elseif _type == 'table' then
            local closestBone, boneDistance

            for j = 1, #bone do
                local boneId = GetEntityBoneIndexByName(entityHit, bone[j])

                if boneId ~= -1 then
                    local dist = #(endCoords - GetEntityBonePosition_2(entityHit, boneId))

                    if dist <= (boneDistance or 1) then
                        closestBone = boneId
                        boneDistance = dist
                    end
                end
            end

            if closestBone then
                bone = closestBone
            else
                return true
            end
        end
    end

    local offset = entityModel and option.offset or nil

    if offset then
        ---@cast entityHit number
        ---@cast entityType number
        ---@cast entityModel number

        if not option.absoluteOffset then
            local min, max = GetModelDimensions(entityModel)
            offset = (max - min) * offset + min
        end

        offset = GetOffsetFromEntityInWorldCoords(entityHit, offset.x, offset.y, offset.z)

        if #(endCoords - offset) > (option.offsetSize or 1) then
            return true
        end
    end

    if option.canInteract then
        local success, resp = pcall(option.canInteract, entityHit, distance, endCoords, option.name, bone)
        return not success or not resp
    end
end

local function startTargeting()
    if state.isDisabled() or state.isActive() or IsNuiFocused() or IsPauseMenuActive() then return end

    state.setActive(true)

    local flag = 511
    local hit, entityHit, endCoords, distance, lastEntity, entityType, entityModel, hasTarget, zonesChanged
    local zones = {}

    CreateThread(function()
        local dict, texture = utils.getTexture()
        local lastCoords

        while state.isActive() do
            lastCoords = endCoords == vec0 and lastCoords or endCoords or vec0

            if debug then
                DrawMarker(28, lastCoords.x, lastCoords.y, lastCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.2,
                    0.2,
                    ---@diagnostic disable-next-line: param-type-mismatch
                    255, 42, 24, 100, false, false, 0, true, false, false, false)
            end

            utils.drawZoneSprites(dict, texture)
            DisablePlayerFiring(cache.playerId, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            if state.isNuiFocused() then
                DisableControlAction(0, 1, true)   -- Mouse look X
                DisableControlAction(0, 2, true)   -- Mouse look Y
                DisableControlAction(0, 8, true)   -- Move backward
                DisableControlAction(0, 9, true)   -- Move forward
                DisableControlAction(0, 24, true)  -- Attack/LMB (prevents kick on click)
                DisableControlAction(0, 322, true) -- ESC key (prevent pause menu)

                if IsDisabledControlJustPressed(0, 194) or IsDisabledControlJustPressed(0, 322) then
                    state.setNuiFocus(false, false)
                end

                if not hasTarget or options and IsDisabledControlJustPressed(0, 25) then
                    state.setNuiFocus(false, false)
                end
            elseif hasTarget and IsDisabledControlJustPressed(0, mouseButton) then
                state.setNuiFocus(true, true)
            end

            Wait(0)
        end

        SetStreamedTextureDictAsNoLongerNeeded(dict)
    end)

    while state.isActive() do
        if not state.isNuiFocused() and lib.progressActive() then
            state.setActive(false)
            break
        end

        local playerCoords = GetEntityCoords(cache.ped)
        hit, entityHit, endCoords = lib.raycast.fromCamera(flag, 4, 20)
        distance = #(playerCoords - endCoords)

        if entityHit ~= 0 and entityHit ~= lastEntity then
            local success, result = pcall(GetEntityType, entityHit)
            entityType = success and result or 0
        end

        if entityType == 0 then
            local _flag = flag == 511 and 26 or 511
            local _hit, _entityHit, _endCoords = lib.raycast.fromCamera(_flag, 4, 20)
            local _distance = #(playerCoords - _endCoords)

            if _distance < distance then
                flag, hit, entityHit, endCoords, distance = _flag, _hit, _entityHit, _endCoords, _distance

                if entityHit ~= 0 then
                    local success, result = pcall(GetEntityType, entityHit)
                    entityType = success and result or 0
                end
            end
        end

        nearbyZones, zonesChanged = utils.getNearbyZones(endCoords)

        local entityChanged = entityHit ~= lastEntity
        local newOptions = (zonesChanged or entityChanged or menuChanged) and true

        if entityHit > 0 and entityChanged then
            currentMenu = nil

            if flag ~= 511 then
                entityHit = HasEntityClearLosToEntity(entityHit, cache.ped, 7) and entityHit or 0
            end

            if lastEntity ~= entityHit and debug then
                if lastEntity then
                    SetEntityDrawOutline(lastEntity, false)
                end

                if entityType ~= 1 then
                    SetEntityDrawOutline(entityHit, true)
                end
            end

            if entityHit > 0 then
                local success, result = pcall(GetEntityModel, entityHit)
                entityModel = success and result
            end
        end

        if hasTarget and (zonesChanged or entityChanged and hasTarget > 1) then
            SendNuiMessage('{"event": "leftTarget"}')

            if entityChanged then options:wipe() end

            if debug and lastEntity > 0 then SetEntityDrawOutline(lastEntity, false) end

            hasTarget = false
        end

        if newOptions and entityModel and entityHit > 0 then
            options:set(entityHit, entityType, entityModel)
        end

        lastEntity = entityHit
        currentTarget.entity = entityHit
        currentTarget.coords = endCoords
        currentTarget.distance = distance
        local hidden = 0
        local totalOptions = 0

        for k, v in pairs(options) do
            local optionCount = #v
            local dist = k == '__global' and 0 or distance
            totalOptions += optionCount

            for i = 1, optionCount do
                local option = v[i]
                local hide = shouldHide(option, dist, endCoords, entityHit, entityType, entityModel)

                if option.hide ~= hide then
                    option.hide = hide
                    newOptions = true
                end

                if hide then hidden += 1 end
            end
        end

        if zonesChanged then table.wipe(zones) end

        for i = 1, #nearbyZones do
            local zoneOptions = nearbyZones[i].options
            local optionCount = #zoneOptions
            totalOptions += optionCount
            zones[i] = zoneOptions

            for j = 1, optionCount do
                local option = zoneOptions[j]
                local hide = shouldHide(option, distance, endCoords, entityHit)

                if option.hide ~= hide then
                    option.hide = hide
                    newOptions = true
                end

                if hide then hidden += 1 end
            end
        end

        if newOptions then
            if hasTarget == 1 and (totalOptions - hidden) > 1 then
                hasTarget = true
            end

            if hasTarget and hidden == totalOptions then
                if hasTarget and hasTarget ~= 1 then
                    hasTarget = false
                    SendNuiMessage('{"event": "leftTarget"}')
                end
            elseif menuChanged or hasTarget ~= 1 and hidden ~= totalOptions then
                hasTarget = options.size

                if currentMenu and options.__global[1]?.name ~= 'builtin:goback' then
                    table.insert(options.__global, 1,
                        {
                            icon = 'fa-solid fa-circle-chevron-left',
                            label = locale('go_back'),
                            name = 'builtin:goback',
                            menuName = currentMenu,
                            openMenu = 'home'
                        })
                end

                SendNuiMessage(json.encode({
                    event = 'setTarget',
                    options = options,
                    zones = zones,
                }, { sort_keys = true }))
            end

            menuChanged = false
        end

        if toggleHotkey and IsPauseMenuActive() then
            state.setActive(false)
        end

        if not hasTarget or hasTarget == 1 then
            flag = flag == 511 and 26 or 511
        end

        Wait(hit and 50 or 100)
    end

    if lastEntity and debug then
        SetEntityDrawOutline(lastEntity, false)
    end

    state.setNuiFocus(false)
    SendNuiMessage('{"event": "visible", "state": false}')
    table.wipe(currentTarget)
    options:wipe()

    if nearbyZones then table.wipe(nearbyZones) end
end

do
    ---@type KeybindProps
    local keybind = {
        name = 'ox_target',
        defaultKey = GetConvar('ox_target:defaultHotkey', 'LMENU'),
        defaultMapper = 'keyboard',
        description = locale('toggle_targeting'),
    }

    if toggleHotkey then
        function keybind:onPressed()
            if state.isActive() then
                return state.setActive(false)
            end

            return startTargeting()
        end
    else
        keybind.onPressed = startTargeting

        function keybind:onReleased()
            state.setActive(false)
        end
    end

    lib.addKeybind(keybind)
end

---@generic T
---@param option T
---@param server? boolean
---@return T
local function getResponse(option, server)
    local response = table.clone(option)
    response.entity = currentTarget.entity
    response.zone = currentTarget.zone
    response.coords = currentTarget.coords
    response.distance = currentTarget.distance

    if server then
        response.entity = response.entity ~= 0 and NetworkGetEntityIsNetworked(response.entity) and
            NetworkGetNetworkIdFromEntity(response.entity) or 0
    end

    response.icon = nil
    response.groups = nil
    response.items = nil
    response.canInteract = nil
    response.onSelect = nil
    response.export = nil
    response.event = nil
    response.serverEvent = nil
    response.command = nil

    return response
end

RegisterNUICallback('select', function(data, cb)
    cb(1)

    if data[1] == 'themes' then
        local theme = themeMenuOptions[data[2]]

        if theme then
            SetResourceKvp('ox_target_theme', theme.args)
            SendNuiMessage(json.encode({ event = 'setTheme', theme = theme.args }))
            lib.notify({ description = ('Theme changed to: %s'):format(theme.label), type = 'success' })
        end

        themeMenuOpen = false
        state.setNuiFocus(false)
        state.setActive(false)
        SendNuiMessage('{"event": "visible", "state": false}')
        return
    end

    local zone = data[3] and nearbyZones[data[3]]

    ---@type OxTargetOption?
    local option = zone and zone.options[data[2]] or options[data[1]][data[2]]

    if option then
        if option.openMenu then
            local menuDepth = #menuHistory

            if option.name == 'builtin:goback' then
                option.menuName = option.openMenu
                option.openMenu = menuHistory[menuDepth]

                if menuDepth > 0 then
                    menuHistory[menuDepth] = nil
                end
            else
                menuHistory[menuDepth + 1] = currentMenu
            end

            menuChanged = true
            currentMenu = option.openMenu ~= 'home' and option.openMenu or nil

            options:wipe()
        else
            state.setNuiFocus(false)
            CreateThread(function()
                Wait(200) -- Grace period after option select to prevent accidental actions
                if IsNuiFocused() then
                    state.setNuiFocus(false)
                end
            end)
        end

        currentTarget.zone = zone?.id

        if option.onSelect then
            option.onSelect(option.qtarget and currentTarget.entity or getResponse(option))
        elseif option.export then
            exports[option.resource or zone.resource][option.export](nil, getResponse(option))
        elseif option.event then
            TriggerEvent(option.event, getResponse(option))
        elseif option.serverEvent then
            TriggerServerEvent(option.serverEvent, getResponse(option, true))
        elseif option.command then
            ExecuteCommand(option.command)
        end

        if option.menuName == 'home' then return end
    end

    if not option?.openMenu and IsNuiFocused() then
        state.setActive(false)
    end
end)

RegisterNUICallback('close', function(data, cb)
    cb(1)
    if themeMenuOpen then
        themeMenuOpen = false
        state.setActive(false)
        SendNuiMessage('{"event": "visible", "state": false}')
    end
    state.setNuiFocus(false, false)
end)

-- Theme menu
safeRegisterCommand('target', function()
    openThemeMenu()
end, { help = 'Open the ox_target theme selector' })

lib.registerContext({
    id = 'targettheme_menu',
    title = 'ox_target Theme',
    options = {
        { label = 'Green', args = 'green', icon = 'circle', iconColor = '80ff49', close = true, onSelect = function(args)
            SetResourceKvp('ox_target_theme', 'green')
            SendNuiMessage(json.encode({ event = 'setTheme', theme = 'green' }))
            lib.notify({ description = 'Theme changed to: Green', type = 'success' })
        end },
        { label = 'Gold', args = 'gold', icon = 'circle', iconColor = 'ffd700', close = true, onSelect = function(args)
            SetResourceKvp('ox_target_theme', 'gold')
            SendNuiMessage(json.encode({ event = 'setTheme', theme = 'gold' }))
            lib.notify({ description = 'Theme changed to: Gold', type = 'success' })
        end },
        { label = 'Blue', args = 'blue', icon = 'circle', iconColor = '00bfff', close = true, onSelect = function(args)
            SetResourceKvp('ox_target_theme', 'blue')
            SendNuiMessage(json.encode({ event = 'setTheme', theme = 'blue' }))
            lib.notify({ description = 'Theme changed to: Blue', type = 'success' })
        end },
        { label = 'Purple', args = 'purple', icon = 'circle', iconColor = 'da70d6', close = true, onSelect = function(args)
            SetResourceKvp('ox_target_theme', 'purple')
            SendNuiMessage(json.encode({ event = 'setTheme', theme = 'purple' }))
            lib.notify({ description = 'Theme changed to: Purple', type = 'success' })
        end },
        { label = 'Red', args = 'red', icon = 'circle', iconColor = 'ff4444', close = true, onSelect = function(args)
            SetResourceKvp('ox_target_theme', 'red')
            SendNuiMessage(json.encode({ event = 'setTheme', theme = 'red' }))
            lib.notify({ description = 'Theme changed to: Red', type = 'success' })
        end },
        { label = 'Cyan', args = 'cyan', icon = 'circle', iconColor = '00ffff', close = true, onSelect = function(args)
            SetResourceKvp('ox_target_theme', 'cyan')
            SendNuiMessage(json.encode({ event = 'setTheme', theme = 'cyan' }))
            lib.notify({ description = 'Theme changed to: Cyan', type = 'success' })
        end },
    }
})
