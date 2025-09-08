require('Foobar/lib/musicutil-extended')

local UI = {
    current_font = 1,
    max_visible_items = 5,
    fonts = {
		{ name = "04B_03", face = 1, size = 8 },        -- 1
		{ name = "ALEPH", face = 2, size = 8 },         -- 2   
		{ name = "tom-thumb", face = 25, size = 6 },    -- 3
		{ name = "creep", face = 26, size = 16 },       -- 4
		{ name = "ctrld", face = 27, size = 10 },       -- 5
		{ name = "ctrld", face = 28, size = 10 },       -- 6
		{ name = "ctrld", face = 29, size = 13 },       -- 7 
		{ name = "ctrld", face = 30, size = 13 },       -- 8
		{ name = "ctrld", face = 31, size = 13 },       -- 9
		{ name = "ctrld", face = 32, size = 13 },       -- 10
		{ name = "ctrld", face = 33, size = 16 },       -- 11
		{ name = "ctrld", face = 34, size = 16 },       -- 12
		{ name = "ctrld", face = 35, size = 16 },       -- 13 
		{ name = "ctrld", face = 36, size = 16 },       -- 14
		{ name = "scientifica", face = 37, size = 11 }, -- 15
		{ name = "scientifica", face = 38, size = 11 }, -- 16
		{ name = "scientifica", face = 39, size = 11 }, -- 17
		{ name = "ter", face = 40, size = 12 },         -- 18
		{ name = "ter", face = 41, size = 12 },         -- 19
		{ name = "ter", face = 42, size = 14 },         -- 20
		{ name = "ter", face = 43, size = 14 },         -- 21
		{ name = "ter", face = 44, size = 14 },         -- 22
		{ name = "ter", face = 45, size = 16 },         -- 23
		{ name = "ter", face = 46, size = 16 },         -- 24
		{ name = "ter", face = 47, size = 16 },         -- 25
		{ name = "ter", face = 48, size = 18 },         -- 26
		{ name = "ter", face = 49, size = 18 },         -- 27
		{ name = "ter", face = 50, size = 20 },         -- 28
		{ name = "ter", face = 51, size = 20 },         -- 29
		{ name = "ter", face = 52, size = 22 },         -- 30
		{ name = "ter", face = 53, size = 22 },         -- 31
		{ name = "ter", face = 54, size = 24 },         -- 32
		{ name = "ter", face = 55, size = 24 },         -- 33
		{ name = "ter", face = 56, size = 28 },         -- 34
		{ name = "ter", face = 57, size = 28 },         -- 35
		{ name = "ter", face = 58, size = 32 },         -- 36
		{ name = "ter", face = 59, size = 32 },         -- 37
		{ name = "unscii", face = 60, size = 16 },      -- 38
		{ name = "unscii", face = 61, size = 16 },      -- 39
		{ name = "unscii", face = 62, size = 8 },       -- 40
		{ name = "unscii", face = 63, size = 8 },       -- 41
		{ name = "unscii", face = 64, size = 8 },       -- 42
		{ name = "unscii", face = 65, size = 8 },       -- 43
		{ name = "unscii", face = 66, size = 16 },      -- 44
		{ name = "unscii", face = 67, size = 8 }        -- 45
    },
    default = {
        style = {
            color = 15,
            background = 0,
            spacing = 10,
            font = 1,
            align = 'left',
            stroke = 1,
            aa = 0,
            line_join = 'square',
            line_width = 1,
        }
    }
}


-- Use a menu item, selected by context key and cursor position
-- Set font and size to avoid aliasing
function UI:set_font(n)
    self.current_font = n
	screen.font_face(self.fonts[n].face)
	screen.font_size(self.fonts[n].size)
end

function UI:get_font_size()
    return self.fonts[self.current_font].size
end

-- Merge style tables, with override taking precedence
function UI:merge_style(default_style, override_style)
    if not override_style then
        return default_style
    end
    
    local merged = {}
    -- Start with default style
    for key, value in pairs(default_style) do
        merged[key] = value
    end
    
    -- Override with provided style values
    for key, value in pairs(override_style) do
        merged[key] = value
    end
    
    return merged
end



-- Draws

function UI:draw_chord(select, x, y)
	x = x or 60
	y = y or 14
	local scale = App.scale[select]
	local chord = scale.chord
	if chord and #scale.intervals > 2 then
		local name = chord.name
		local root = chord.root + scale.root
		local bass = scale.root

		screen.level(15)
		UI:set_font(37)
		screen.move(x, y + 12)
		screen.text(musicutil.note_num_to_name(root))
		local name_offset = screen.text_extents(musicutil.note_num_to_name(root)) + x
		UI:set_font(9)

		screen.move(name_offset, y)
		screen.text(name)
		screen.fill()

		if bass ~= root then
			screen.move(name_offset, y + 12)
			screen.text("/" .. musicutil.note_num_to_name(bass))
		end
	end
end

function UI:draw_chord_small(select, x, y)
	x = x or 60
	y = y or 46
	local scale = App.scale[select]
	local chord = scale.chord
	if chord and #scale.intervals > 2 then
		local name = chord.name
		local root = chord.root + scale.root
		local bass = scale.root

		screen.level(15)
		UI:set_font(1)
		screen.move(x, y)
		screen.text(musicutil.note_num_to_name(root) .. name)
		screen.fill()
	end
end

function UI:draw_intervals(x, y, major)
	x = x or 0
	y = y or 63
	screen.move(127, 41)
    
	local interval_names = { "\u{2160}", "\u{2171}", "\u{2161}", "\u{2172}", "\u{2162}", "\u{2163}", "\u{2174}", "\u{2164}", "\u{2175}", "\u{2165}", "\u{2176}", "\u{2166}" }
    
	self:set_font(1)
	for i = 1, #interval_names do
		if App.scale[1].bits & (1 << (i - 1)) > 0 then
			screen.level(15)
		else
			screen.level(1)
		end
		screen.move(i * 10 + x, y)
		screen.text_center(interval_names[i])
		screen.fill()
	end
end

function UI:draw_tag(x, y, label, value, style)
    local default_style = {color = 15, spacing = 10, stroke = 1, label_font = 1, value_font = 33}
    style = self:merge_style(default_style, style)
    local x_pos = x
    local y_pos = y - style.stroke
    local width = 30
    local height = 30 - style.stroke
    
    -- rectangle
    screen.level(style.color)
    screen.rect(x_pos, y_pos, width, height)
    screen.aa(0)
    screen.line_join('square')
    screen.line_width(style.stroke)
    screen.stroke()           

    -- label
    screen.move(x_pos + width / 2, y_pos + self:get_font_size() - style.stroke)
    UI:set_font(style.label_font)
    screen.text_center(label)

    -- value
    screen.move(x_pos + width / 2, y_pos + (height - self:get_font_size()) + 4)
    self:set_font(style.value_font)
    screen.text_center(value)

    screen.fill()
end

function UI:draw_toast(toast_text)
    screen.level(15)
    self:set_font(33)
    screen.move(64,32)
    screen.text_center(toast_text)
    screen.fill()
end

function UI:draw_menu(x, y, menu, cursor)
    menu = menu or {}
    cursor = cursor or 1

    -- compute visible range
    local total_items = #menu
    local max_visible = self.max_visible_items
    local start_index, end_index = 1, total_items
    if total_items > max_visible then
        end_index = max_visible
        if cursor > max_visible - 2 then
            if cursor <= total_items - 2 then
                start_index = cursor - 2
                end_index = cursor + 2
            else
                start_index = total_items - max_visible + 1
                end_index = total_items
            end
        end
    end

    for i = start_index, end_index do
        local menu_item = menu[i]
        if menu_item then
            local icon = menu_item.icon or ""
            local label = menu_item.label or ""
            local value = menu_item.value or ""
            local style = menu_item.style
            local is_active = (i == cursor)

            if type(menu_item.label) == "function" then
                label = menu_item.label()
            end

            if type(menu_item.value) == "function" then
                value = menu_item.value()
            end

            -- Calculate visual position (1-based for display)
            local visual_index = i - start_index + 1
            self:draw_menu_item(x, y + (visual_index - 1) * 10, label, value, icon, is_active, style)
        end
    end
end

function UI:draw_menu_item(x, y, label, value, icon, is_active, style)
    local default_style = {
        color = 15, stroke = 1, font = 1, width = 60, inactive_color = 5, icon_color = 15, icon_inactive_color = 5}
    style = self:merge_style(default_style, style)

    
    
    self:set_font(style.font)

	screen.move(x, y)
    if icon then
        if is_active then
            screen.level(style.icon_color)
        else
            screen.level(style.icon_inactive_color)
        end
        screen.text(icon)
    end
    screen.fill()

    -- Adjust color based on active state
    if is_active then
        screen.level(style.color) -- Bright white for active item
    else
        screen.level(style.inactive_color)
    end

    screen.move(x + 6, y)
    screen.text(label)

    screen.move(x + style.width, y)
    screen.text_right(value)
    
    screen.fill()
end

function UI:draw_status()
    -- Track number
	self:set_font(1)
	screen.level(15)
	screen.rect(0, 0, 10, 9)
	screen.fill()
	screen.level(0)
	screen.move(5, 7)
	screen.text_center(App.current_track)
	screen.fill()
    -- track name
	screen.level(15)
	screen.move(15, 7)
	screen.text(App.track[App.current_track].name)

    -- menu rendering is owned by a gridless mode component

end


function UI:draw_tempo()
	if App.playing then
		local beat = 15 - math.floor((App.tick % App.ppqn) / App.ppqn * 16)
		screen.level(beat)
	else
		screen.level(5)
	end

	screen.rect(76, 0, 127, 32)
	screen.fill()

	screen.move(102, 28)
	self:set_font(34)
	screen.level(0)
	screen.text_center(math.floor(clock.get_tempo() + 0.5))
	screen.fill()

	screen.level(0)
    self:set_font(1)

	if App.playing then
		screen.move(124, 7)
		screen.text_right("\u{23f5}") -- play
	else
		screen.move(124, 7)
		screen.text_right("\u{23f8}") -- pause
	end

	screen.move(79, 7)
	local quarter = math.floor(App.tick / App.ppqn)
	local measure = math.floor(quarter / 4) + 1
	local count = math.floor(quarter % 4) + 1
	screen.text(measure .. ":" .. count)
	screen.fill()

	if App.recording then
		screen.move(85, 7)
		screen.text("\u{23fa}") -- record
		screen.fill()
	end
end

return UI
