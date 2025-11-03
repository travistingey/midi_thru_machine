local musicutil = require('Foobar/lib/musicutil-extended')

local UI = {
	current_font = 1,
	max_visible_items = 5,
	fonts = {
		{ name = '04B_03', face = 1, size = 8 }, -- 1
		{ name = 'ALEPH', face = 2, size = 8 }, -- 2
		{ name = 'tom-thumb', face = 25, size = 6 }, -- 3
		{ name = 'creep', face = 26, size = 16 }, -- 4
		{ name = 'ctrld', face = 27, size = 10 }, -- 5
		{ name = 'ctrld', face = 28, size = 10 }, -- 6
		{ name = 'ctrld', face = 29, size = 13 }, -- 7
		{ name = 'ctrld', face = 30, size = 13 }, -- 8
		{ name = 'ctrld', face = 31, size = 13 }, -- 9
		{ name = 'ctrld', face = 32, size = 13 }, -- 10
		{ name = 'ctrld', face = 33, size = 16 }, -- 11
		{ name = 'ctrld', face = 34, size = 16 }, -- 12
		{ name = 'ctrld', face = 35, size = 16 }, -- 13
		{ name = 'ctrld', face = 36, size = 16 }, -- 14
		{ name = 'scientifica', face = 37, size = 11 }, -- 15
		{ name = 'scientifica', face = 38, size = 11 }, -- 16
		{ name = 'scientifica', face = 39, size = 11 }, -- 17
		{ name = 'ter', face = 40, size = 12 }, -- 18
		{ name = 'ter', face = 41, size = 12 }, -- 19
		{ name = 'ter', face = 42, size = 14 }, -- 20
		{ name = 'ter', face = 43, size = 14 }, -- 21
		{ name = 'ter', face = 44, size = 14 }, -- 22
		{ name = 'ter', face = 45, size = 16 }, -- 23
		{ name = 'ter', face = 46, size = 16 }, -- 24
		{ name = 'ter', face = 47, size = 16 }, -- 25
		{ name = 'ter', face = 48, size = 18 }, -- 26
		{ name = 'ter', face = 49, size = 18 }, -- 27
		{ name = 'ter', face = 50, size = 20 }, -- 28
		{ name = 'ter', face = 51, size = 20 }, -- 29
		{ name = 'ter', face = 52, size = 22 }, -- 30
		{ name = 'ter', face = 53, size = 22 }, -- 31
		{ name = 'ter', face = 54, size = 24 }, -- 32
		{ name = 'ter', face = 55, size = 24 }, -- 33
		{ name = 'ter', face = 56, size = 28 }, -- 34
		{ name = 'ter', face = 57, size = 28 }, -- 35
		{ name = 'ter', face = 58, size = 32 }, -- 36
		{ name = 'ter', face = 59, size = 32 }, -- 37
		{ name = 'unscii', face = 60, size = 16 }, -- 38
		{ name = 'unscii', face = 61, size = 16 }, -- 39
		{ name = 'unscii', face = 62, size = 8 }, -- 40
		{ name = 'unscii', face = 63, size = 8 }, -- 41
		{ name = 'unscii', face = 64, size = 8 }, -- 42
		{ name = 'unscii', face = 65, size = 8 }, -- 43
		{ name = 'unscii', face = 66, size = 16 }, -- 44
		{ name = 'unscii', face = 67, size = 8 }, -- 45
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
		},
	},
}

-- UI Helper Functions

-- Sets font to correct size to avoid aliasing
function UI:set_font(n)
	self.current_font = n
	screen.font_face(self.fonts[n].face)
	screen.font_size(self.fonts[n].size)
end

-- Returns the size of the current font
function UI:get_font_size() return self.fonts[self.current_font].size end

-- Merge style tables, with override taking precedence
function UI:merge_style(default_style, override_style)
	if not override_style then return default_style end

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

-- Draw Functions
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
			screen.text('/' .. musicutil.note_num_to_name(bass))
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

	local interval_names = { '\u{2160}', '\u{2171}', '\u{2161}', '\u{2172}', '\u{2162}', '\u{2163}', '\u{2174}', '\u{2164}', '\u{2175}', '\u{2165}', '\u{2176}', '\u{2166}' }

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
	local default_style = { color = 15, spacing = 10, stroke = 1, label_font = 1, value_font = 33 }
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
	screen.move(64, 32)
	screen.text_center(toast_text)
	screen.fill()
end

function UI:draw_menu(x, y, menu, cursor, opts)
	menu = menu or {}
	cursor = cursor or 1
	opts = opts or {}
	local default_disable_highlight = opts.disable_highlight

	local visible_indices = {}
	for index, item in ipairs(menu) do
		local show = true
		if item and item.can_show ~= nil then
			if type(item.can_show) == 'function' then
				show = item.can_show(item)
			else
				show = item.can_show
			end
		end
		if show ~= false then table.insert(visible_indices, index) end
	end

	local total_visible = #visible_indices
	if total_visible == 0 then return end

	local max_visible = self.max_visible_items
	-- Reserve one row of vertical space at the bottom for helper toast
	local window_rows = math.max(1, max_visible - 1)
	local cursor_position = 1
	for i, idx in ipairs(visible_indices) do
		if idx == cursor then
			cursor_position = i
			break
		end
	end

	local start_pos, end_pos = 1, total_visible
	if total_visible > window_rows then
		end_pos = window_rows
		-- Maintain similar centering behavior but within the reduced window
		if cursor_position > window_rows - 2 then
			if cursor_position <= total_visible - 2 then
				start_pos = cursor_position - 2
				end_pos = start_pos + window_rows - 1
			else
				start_pos = total_visible - window_rows + 1
				end_pos = total_visible
			end
		end
	end

	local rows = end_pos - start_pos + 1
	local last_row_y = y + (rows - 2) * 10
	-- Keep menu rows within the area above helper toast bar (10px height)
	local max_y = 44
	local offset_y = 0
	local is_scrolling = (total_visible > max_visible)
	if (not is_scrolling) and (last_row_y > max_y) then offset_y = max_y - last_row_y end

	for pos = start_pos, end_pos do
		local actual_index = visible_indices[pos]
		local menu_item = menu[actual_index]
		if menu_item then
			local icon = menu_item.icon
			local label = menu_item.label or ''
			local value = menu_item.value or ''
			local style = menu_item.style
			local is_active = (actual_index == cursor)

			if type(menu_item.label) == 'function' then label = menu_item.label() end

			if type(menu_item.value) == 'function' then value = menu_item.value() end

			local visual_index = pos - start_pos + 1
			self.current_item = menu_item
			local item_disable = menu_item.disable_highlight
			if item_disable == nil then item_disable = default_disable_highlight end
			self:draw_menu_item(x, y + offset_y + (visual_index - 1) * 10, label, value, icon, is_active, style, item_disable)
			self.current_item = nil
		end
	end
end

-- Draws a single menu item (row)
function UI:draw_menu_item(x, y, label, value, icon, is_active, style, disable_highlight)
	local default_style = {
		color = 15,
		stroke = 1,
		font = 1,
		width = 127,
		inactive_color = 5,
		icon_color = 15,
		icon_inactive_color = 5,
	}
	style = self:merge_style(default_style, style)

	local icon_offset = 15
	local submenu_offset = 8
	local entry_width = style.width - submenu_offset
	local show_next = false
	-- Measure text widths for icon, label, and value
	local label_w = screen.text_extents(label) or 0
	local value_w = screen.text_extents(value) or 0

	self:set_font(style.font)

	-- Precise underlines using 1px rects
	if is_active and self.current_item and not disable_highlight then
		screen.level(1)
		screen.rect(x, y - 8, style.width, 10)
		screen.fill()
		-- Underline label when this is a combo item (enc2 available)
		if self.current_item.enc2 then
			local label_x = x + icon_offset
			screen.level(5)
			screen.rect(label_x, y + 1, label_w, 1)
			screen.fill()
		end

		-- Underline value when editable (enc3 on item)
		if self.current_item.enc3 or self.current_item.is_editable then
			local value_x_left = x + entry_width - value_w
			screen.level(5)
			screen.rect(value_x_left, y + 1, value_w, 1)
			screen.fill()
		end
	end

	screen.move(x + 5, y)
	if icon then
		-- Icons are bright only when the row is active AND editable; otherwise dim
		local editable = self.current_item and (self.current_item.enc2 or self.current_item.enc3 or self.current_item.is_editable)
		if is_active and editable then
			screen.level(style.icon_color)
		else
			screen.level(style.icon_inactive_color)
		end
		screen.text_center(icon)
	end
	screen.fill()

	-- Adjust color based on active state
	if is_active then
		screen.level(style.color) -- Bright white for active item
	else
		screen.level(style.inactive_color)
	end

	screen.move(x + icon_offset, y)
	screen.text(label)

	screen.move(x + entry_width, y)
	screen.text_right(value)

	-- Optional right-side press icon when item supports on_press and is enabled to press
	local current_item = self.current_item
	local has_pending = current_item and current_item.pending_confirmation

	if has_pending then
		show_next = true
	elseif current_item.has_press then
		-- Only show "next" when the item actually opens a submenu.
		-- Prefer explicit flag; fallback to label convention ('\u{25ba}') used for submenus.
		local opens_submenu = false
		if current_item.has_submenu and type(current_item.has_submenu) == 'function' then
			opens_submenu = current_item.has_submenu()
		else
			opens_submenu = current_item.has_submenu == true
		end

		if opens_submenu then
			show_next = true
			if current_item.can_press ~= nil then
				if type(current_item.can_press) == 'function' then show_next = current_item.can_press() end
			end
		end
	end

	if show_next then
		local next_icon = has_pending and '?' or '\u{25ba}'
		local press_x = 127
		if is_active then
			screen.level(style.icon_color)
		else
			screen.level(style.icon_inactive_color)
		end
		screen.move(press_x, y)
		screen.text_right(next_icon)
		screen.fill()
	end

	-- Optional per-item draw hooks
	if self.current_item and self.current_item.draw then pcall(self.current_item.draw, self.current_item, x, y, is_active) end

	if self.current_item and self.current_item.draw_buttons then pcall(self.current_item.draw_buttons, self.current_item, x, y, is_active) end
end

function UI:draw_status(icon, label)
	icon = icon or App.current_track
	label = label or App.track[App.current_track].name

	self:set_font(1)
	screen.level(15)
	screen.rect(0, 0, 10, 9)
	screen.fill()
	screen.level(0)
	screen.move(5, 7)
	screen.text_center(icon)
	screen.fill()
	screen.level(15)
	screen.move(15, 7)
	screen.text(label)
	screen.fill()
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

	-- MEASURE AND BEAT COUNTER
	screen.move(125, 7)
	local quarter = math.floor(App.tick / App.ppqn)
	local measure = math.floor(quarter / 4) + 1
	local count = math.floor(quarter % 4) + 1
	screen.text_right(measure .. ':' .. count)
	screen.fill()

	-- RECORD BUTTON
	local record_offset = 0
	local left_position = 79

	if App.recording then
		record_offset = 8
		screen.move(left_position, 7)
		screen.text('\u{23fa}') -- record
		screen.fill()
	end

	-- PLAY/PAUSE BUTTON
	if App.playing then
		screen.move(left_position + record_offset, 7)
		screen.text('\u{23f5}') -- play
	else
		screen.move(left_position + record_offset, 7)
		screen.text('\u{23f8}') -- pause
	end
end

function UI:draw_small_tempo()
	if App.playing then
		local beat = 15 - math.floor((App.tick % App.ppqn) / App.ppqn * 16)
		screen.level(beat)
	else
		screen.level(5)
	end

	screen.fill()
	self:set_font(1)

	-- RECORD BUTTON
	local record_offset = 8
	local right_position = 127

	if App.recording then
		screen.move(right_position - record_offset, 7)
		screen.text_right('\u{23fa}') -- record
		screen.fill()
	end

	-- PLAY/PAUSE BUTTON
	if App.playing then
		screen.move(right_position, 7)
		screen.text_right('\u{23f5}') -- play
	else
		screen.move(right_position, 7)
		screen.text_right('\u{23f8}') -- pause
	end
end

function UI:draw_helper_toast(helper_labels, y)
	if not helper_labels then return end

	local order = { 'press_fn_2', 'press_fn_3', 'enc2', 'enc3' }

	local left_text = ''
	local right_text = ''

	local mode = App.mode and App.mode[App.current_mode]
	local current = mode and mode.menu and mode.menu[mode.cursor]

	local height = 10
	local pos_y = y or (64 - height)

	screen.level(0)
	screen.rect(0, pos_y, 128, height)
	screen.fill()

	screen.level(5)
	screen.rect(0, pos_y, 128, 1)
	screen.fill()

	screen.level(15)
	self:set_font(1)

	screen.move(0, pos_y + height - 2)
	if current and current.pending_confirmation then
		screen.text('x')
	elseif helper_labels.alt_press_fn_2 and App.alt_down then
		screen.text(helper_labels.alt_press_fn_2)
	elseif helper_labels.press_fn_2 then
		screen.text(helper_labels.press_fn_2)
	end

	screen.move(30, pos_y + height - 2)
	if current and current.pending_confirmation then
		screen.text_center('confirm')
	elseif helper_labels.alt_press_fn_3 and App.alt_down then
		screen.text_center(helper_labels.alt_press_fn_3)
	elseif helper_labels.press_fn_3 then
		screen.text_center(helper_labels.press_fn_3)
	end

	screen.move(125, pos_y + height - 2)
	if helper_labels.alt_enc3 and App.alt_down then
		screen.text_right(helper_labels.alt_enc3)
	elseif helper_labels.enc3 then
		screen.text_right(helper_labels.enc3)
	end

	screen.move(81, pos_y + height - 2)
	if helper_labels.alt_enc2 and App.alt_down then
		screen.text_center(helper_labels.alt_enc2)
	elseif helper_labels.enc2 then
		screen.text_center(helper_labels.enc2)
	end

	screen.fill()
end

return UI
