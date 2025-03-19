addon.name      = 'rWarnings'
addon.author    = 'Rag'
addon.version   = '0.0.1'
addon.desc      = 'Displays mobs beginning spellcasts and using abilities as UI text objects'
addon.link      = 'https://github.com/yzyii'

require('common')
require ('rwarningslib')
local chat = require('chat')
local settings = require('settings')
local gdi = require('gdifonts.include')
local scaling = require('scaling')
local priority = require('priority')
local screenCenter = {
    x = scaling.window.w / 2,
    y = scaling.window.h / 2,
}

local defaultSettings = T{
    fade_after = 4,
    fade_duration = 1,
    font_spacing = 1.5,
    font_color_priority = 0xFFFFD700,
    font_color_priority_alt = 0xFF3F00FF,
    font_color_default = 0xFFFFFFFF,
    display_priority_only = false,
    use_alt_priority_font_color = false,
    font = {
        font_alignment = gdi.Alignment.Center,
        font_family = 'Consolas',
        font_flags = gdi.FontFlags.Bold,
        font_height = 36,
        outline_color = 0xFF000000,
        outline_width = 2,
    },
    x_offset = 0,
    y_offset = 50,
}

local loadedSettings = nil

local messages = {
    [1] = nil,
    [2] = nil,
    [3] = nil,
    [4] = nil,
    [5] = nil,
}

this_chunk = nil;
this_chunk_sequences = T{ };
last_chunk_sequences = T{ };
local function is_duplicate(e)
    if (this_chunk ~= e.chunk_data) then
        this_chunk = e.chunk_data;
        last_chunk_sequences = this_chunk_sequences;
        this_chunk_sequences = T{ };
    end

    this_sequence = struct.unpack("H", e.data, 2 + 1);

    if (this_chunk_sequences:contains(this_sequence)) then
        return true;
    end

    this_chunk_sequences:append(this_sequence);

    if (last_chunk_sequences:contains(this_sequence)) then
        return true;
    end

    return false;
end

local function copy(t)
  local t2 = {}
  for k,v in pairs(t) do
    t2[k] = v
  end
  return t2
end

local function initialise()
    for i = 1,5 do
        local font = copy(loadedSettings.font)
        font.position_x = screenCenter.x + loadedSettings.x_offset
        font.position_y = screenCenter.y - loadedSettings.y_offset + (i - 1) * font.font_height * loadedSettings.font_spacing
        messages[i] = { fontobj = gdi:create_object(font), expiry = nil }
    end
end

local function updateFade(obj)
    local maxAlpha = 1
    local minAlpha = 0
    local fadeDuration = loadedSettings.fade_duration
    local fadeAfter = loadedSettings.fade_after

    local elapsed = math.max(0, os.clock() - obj.expiry)
    local alpha = math.max(minAlpha, maxAlpha - (maxAlpha * (elapsed / fadeDuration)))

    obj.fontobj:set_opacity(alpha)

    if alpha == minAlpha then
        obj.expiry = nil
    end
end

ashita.events.register('load', 'rwarnings_load', function()
    loadedSettings = settings.load(defaultSettings)
    initialise()
end)

ashita.events.register('unload', 'rwarnings_unload', function()
    gdi:destroy_interface()
    settings.save()
end)

ashita.events.register('packet_in', 'rwarnings_packet_in', function (e)
    if (e.id == 0x028) then
        if (is_duplicate(e)) then
            return;
        end
            
        local actionPacket = ParseActionPacket(e)

        if (IsMonster(actionPacket.UserIndex) and (actionPacket.Type == 7 or actionPacket.Type == 8)) then
            local actionMessage = actionPacket.Targets[1].Actions[1].Message
            local monsterId = struct.unpack('L', e.data, 0x05 + 0x01)
            local monsterIndex = bit.band(monsterId, 0x7FF)
            local monsterName = AshitaCore:GetMemoryManager():GetEntity():GetName(monsterIndex)

            local actionName = nil
            if (actionPacket.Type == 7) then
                local tpId = ashita.bits.unpack_be(e.data:totable(), 0, 213, 17)
                if (tpId < 256) then
                    actionName = AshitaCore:GetResourceManager():GetAbilityById(tpId).Name[1]
                else
                    local tempName = AshitaCore:GetResourceManager():GetString('monsters.abilities', tpId - 256)
                    if (tempName ~= nil) then
                        actionName = tempName
                    end
                end
            elseif (actionPacket.Type == 8) then
                local spellId = actionPacket.Targets[1].Actions[1].Param
                local spellResource = AshitaCore:GetResourceManager():GetSpellById(spellId)
                if spellResource then
                    if (spellResource.Name[1] ~= nil) then
                        actionName = spellResource.Name[1]
                    end
                end
            end

            if (actionMessage ~= 0 and monsterName ~= nil and actionName ~= nil and actionName ~= '') then
                local isPrio = priority:contains(actionName)
                if (isPrio or not loadedSettings.display_priority_only) then
                    for i = 1,5 do
                        if (messages[i].expiry == nil) then
                            if (isPrio) then
                                local fontColor = loadedSettings.font_color_priority
                                if (loadedSettings.use_alt_priority_font_color) then
                                    fontColor = loadedSettings.font_color_priority_alt
                                end
                                messages[i].fontobj:set_font_color(fontColor)
                            else
                                messages[i].fontobj:set_font_color(loadedSettings.font_color_default)
                            end

                            local msg = monsterName .. ' - ' .. actionName
                            AshitaCore:GetChatManager():AddChatMessage(39, false, 'WARNING: ' .. msg)
                            messages[i].fontobj:set_text(msg)
                            messages[i].expiry = os.clock() + loadedSettings.fade_after
                            break
                        end
                    end
                end
            end
        end
    end
end)

ashita.events.register('d3d_present', 'rwarnings_d3d_present', function()
    for i = 1,5 do
        if (messages[i].expiry ~= nil) then
            updateFade(messages[i])
        end
    end
end)

ashita.events.register('command', 'rwarnings_command', function (e)
    local args = e.command:args()
    if (#args == 0 or args[1] ~= '/rwarnings') then
        return
    end

    e.blocked = true

    if (#args == 4 and args[2]:any('pos')) then
        local x = tonumber(args[3])
        local y = tonumber(args[4])
        if (x and y) then
            loadedSettings.x_offset = x
            loadedSettings.y_offset = y
            for i = 1,5 do
                local position_x = screenCenter.x + x
                local position_y = screenCenter.y - y + (i - 1) * loadedSettings.font.font_height * loadedSettings.font_spacing
                messages[i].fontobj:set_position_x(position_x)
                messages[i].fontobj:set_position_y(position_y)
            end

            local expiry = os.clock() + loadedSettings.fade_after
            messages[1].fontobj:set_font_color(loadedSettings.font_color_priority)
            messages[1].fontobj:set_text('Messages will be displayed here')
            messages[1].expiry = expiry
            messages[5].fontobj:set_font_color(loadedSettings.font_color_priority)
            messages[5].fontobj:set_text('Have Fun!')
            messages[5].expiry = expiry
        end
        return
    end

    if (#args == 2 and args[2]:any('font')) then
        loadedSettings.use_alt_priority_font_color = not loadedSettings.use_alt_priority_font_color
        print(chat.header('rWarnings') .. chat.message('Use Alternate Priority Font Colour: ' .. tostring(loadedSettings.use_alt_priority_font_color)))
        return
    end

    if (#args == 2 and args[2]:any('prio')) then
        loadedSettings.display_priority_only = not loadedSettings.display_priority_only
        print(chat.header('rWarnings') .. chat.message('Display Priority Actions Only: ' .. tostring(loadedSettings.display_priority_only)))
        return
    end

    print(chat.header('rWarnings') .. chat.message('Note: Edit your list of priority actions in priority.lua'))
    print(chat.header('rWarnings') .. chat.message('/rwarnings font - Toggle the colour of priority actions'))
    print(chat.header('rWarnings') .. chat.message('/rwarnings prio - Toggle displaying priority messages only'))
    print(chat.header('rWarnings') .. chat.message('/rwarnings pos [x_offset] [y_offset] - Reposition UI text (default is 0 50)'))
end)
