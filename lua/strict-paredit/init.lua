-- strict-paredit.lua
-- A strict paredit-like plugin for Neovim using treesitter
-- Prevents unbalanced delimiters and handles paired deletion

local M = {}

-- Delimiter pairs
local opening_delims = {
	["("] = ")",
	["["] = "]",
	["{"] = "}",
}

local closing_delims = {
	[")"] = "(",
	["]"] = "[",
	["}"] = "{",
}

-- Symmetric delimiters (same char opens and closes)
local symmetric_delims = {
	['"'] = true,
}

-- Helper: get character at specific buffer position
local function get_char_at(bufnr, row, col)
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if not line or col < 0 or col >= #line then
		return nil
	end
	return line:sub(col + 1, col + 1)
end

-- Helper: get character under cursor (0-indexed column)
local function char_at_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	return get_char_at(bufnr, row, col), row, col
end

-- Helper: get character before cursor
local function char_before_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	if col == 0 then
		return nil, row, col
	end
	return get_char_at(bufnr, row, col - 1), row, col - 1
end

-- Find the matching delimiter using treesitter
-- Returns { open = {row, col}, close = {row, col} } or nil
local function find_delimiter_pair_at(row, col)
	local bufnr = vim.api.nvim_get_current_buf()
	local char = get_char_at(bufnr, row, col)

	if not char then
		return nil
	end
	if not opening_delims[char] and not closing_delims[char] and not symmetric_delims[char] then
		return nil
	end

	-- Get the treesitter node at this position
	local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col } })
	if not ok or not node then
		return nil
	end

	-- Walk up the tree to find a node that encompasses our delimiter
	local current = node
	while current do
		local start_row, start_col, end_row, end_col = current:range()
		-- end_col is exclusive in treesitter

		local start_char = get_char_at(bufnr, start_row, start_col)
		local end_char = get_char_at(bufnr, end_row, end_col - 1)

		-- Check if this node starts and ends with matching delimiters
		if start_char and end_char then
			local is_matching_pair = (opening_delims[start_char] == end_char)
				or (symmetric_delims[start_char] and start_char == end_char)

			if is_matching_pair then
				-- Check if our position is at one of the delimiters
				local at_open = (row == start_row and col == start_col)
				local at_close = (row == end_row and col == end_col - 1)

				if at_open or at_close then
					return {
						open = { row = start_row, col = start_col },
						close = { row = end_row, col = end_col - 1 },
					}
				end
			end
		end

		current = current:parent()
	end

	return nil
end

-- Delete a character at a specific position
local function delete_char_at(bufnr, row, col)
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if not line then
		return
	end

	local new_line = line:sub(1, col) .. line:sub(col + 2)
	vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, { new_line })
end

-- Delete both delimiters of a pair (scheduled to run outside expr mapping context)
local function delete_delimiter_pair(pair, adjust_cursor_after)
	vim.schedule(function()
		local bufnr = vim.api.nvim_get_current_buf()
		local cursor = vim.api.nvim_win_get_cursor(0)

		-- Delete closing first (so positions don't shift for opening if on same line)
		-- But we need to be careful about the order based on position
		local open_row, open_col = pair.open.row, pair.open.col
		local close_row, close_col = pair.close.row, pair.close.col

		if close_row > open_row or (close_row == open_row and close_col > open_col) then
			-- Delete closing first, then opening
			delete_char_at(bufnr, close_row, close_col)
			delete_char_at(bufnr, open_row, open_col)
		else
			-- Delete opening first, then closing
			delete_char_at(bufnr, open_row, open_col)
			delete_char_at(bufnr, close_row, close_col)
		end

		-- Adjust cursor if requested
		if adjust_cursor_after then
			local new_col = cursor[2] - 1
			if new_col < 0 then
				new_col = 0
			end
			vim.api.nvim_win_set_cursor(0, { cursor[1], new_col })
		end
	end)
end

-- Handle opening delimiter in insert mode
local function handle_open_insert(char)
	local closing = opening_delims[char]
	-- Always auto-pair: insert both and place cursor between
	return char .. closing .. "<Left>"
end

-- Handle closing delimiter in insert mode
local function handle_close_insert(char)
	local at_cursor = char_at_cursor()
	if at_cursor == char then
		-- Move over existing closing delimiter
		return "<Right>"
	else
		-- Block insertion - would create unbalanced state
		vim.notify("Strict paredit: cannot insert unmatched " .. char, vim.log.levels.WARN)
		return ""
	end
end

-- Handle string/comment awareness - check if we're in a string or comment
local function in_string_or_comment()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]

	local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col } })
	if not ok or not node then
		return false
	end

	local node_type = node:type()
	-- Common string/comment node types across languages
	local skip_types = {
		"string",
		"string_content",
		"str_lit",
		"string_literal",
		"comment",
		"line_comment",
		"block_comment",
		"regex",
		"regex_lit",
	}

	for _, t in ipairs(skip_types) do
		if node_type == t or node_type:match(t) then
			return true
		end
	end

	return false
end

-- Handle symmetric delimiter (like ") in insert mode
local function handle_symmetric_insert(char)
	local at_cursor = char_at_cursor()
	if at_cursor == char then
		-- Move over existing delimiter
		return "<Right>"
	elseif in_string_or_comment() then
		-- Inside a string, insert escaped version
		return "\\" .. char
	else
		-- Insert pair
		return char .. char .. "<Left>"
	end
end

-- Handle backspace in insert mode
local function handle_backspace()
	local char, row, col = char_before_cursor()

	if not char then
		return "<BS>"
	end

	-- Check if it's a delimiter
	if opening_delims[char] or closing_delims[char] or symmetric_delims[char] then
		local pair = find_delimiter_pair_at(row, col)

		if pair then
			-- Delete both delimiters (with cursor adjustment)
			delete_delimiter_pair(pair, true)
			return ""
		else
			-- No matching pair found, block deletion
			vim.notify("Strict paredit: cannot delete unmatched delimiter", vim.log.levels.WARN)
			return ""
		end
	end

	return "<BS>"
end

-- Handle delete key in insert mode (delete char at cursor)
local function handle_delete()
	local char, row, col = char_at_cursor()

	if not char then
		return "<Del>"
	end

	if opening_delims[char] or closing_delims[char] or symmetric_delims[char] then
		local pair = find_delimiter_pair_at(row, col)

		if pair then
			delete_delimiter_pair(pair, false)
			return ""
		else
			vim.notify("Strict paredit: cannot delete unmatched delimiter", vim.log.levels.WARN)
			return ""
		end
	end

	return "<Del>"
end

-- Handle x in normal mode
local function handle_x_normal()
	local char, row, col = char_at_cursor()

	if not char then
		return "x"
	end

	if opening_delims[char] or closing_delims[char] or symmetric_delims[char] then
		local pair = find_delimiter_pair_at(row, col)

		if pair then
			delete_delimiter_pair(pair, false)
			return ""
		else
			vim.notify("Strict paredit: cannot delete unmatched delimiter", vim.log.levels.WARN)
			return ""
		end
	end

	return "x"
end

-- Handle X in normal mode (delete char before cursor)
local function handle_X_normal()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]

	if col == 0 then
		return "X"
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local char = get_char_at(bufnr, row, col - 1)

	if not char then
		return "X"
	end

	if opening_delims[char] or closing_delims[char] or symmetric_delims[char] then
		local pair = find_delimiter_pair_at(row, col - 1)

		if pair then
			delete_delimiter_pair(pair, true)
			return ""
		else
			vim.notify("Strict paredit: cannot delete unmatched delimiter", vim.log.levels.WARN)
			return ""
		end
	end

	return "X"
end

-- Handle s in normal mode (substitute char)
local function handle_s_normal()
	local char, row, col = char_at_cursor()

	if char and (opening_delims[char] or closing_delims[char] or symmetric_delims[char]) then
		vim.notify("Strict paredit: cannot substitute delimiter", vim.log.levels.WARN)
		return ""
	end

	return "s"
end

-- Setup keymaps for a buffer
local function setup_buffer_keymaps()
	local opts_expr = { buffer = true, expr = true, replace_keycodes = true }
	local opts_expr_noremap = { buffer = true, expr = true, replace_keycodes = true, noremap = true }

	-- Insert mode: opening delimiters
	for open, _ in pairs(opening_delims) do
		vim.keymap.set("i", open, function()
			if in_string_or_comment() then
				return open
			end
			return handle_open_insert(open)
		end, opts_expr)
	end

	-- Insert mode: closing delimiters
	for close, _ in pairs(closing_delims) do
		vim.keymap.set("i", close, function()
			if in_string_or_comment() then
				return close
			end
			return handle_close_insert(close)
		end, opts_expr)
	end

	-- Insert mode: symmetric delimiters (like ")
	for sym, _ in pairs(symmetric_delims) do
		vim.keymap.set("i", sym, function()
			-- Don't bypass for symmetric delims - we want to handle them at string boundaries
			return handle_symmetric_insert(sym)
		end, opts_expr)
	end

	-- Insert mode: backspace
	vim.keymap.set("i", "<BS>", function()
		-- Check if we're about to delete a symmetric delimiter (like ")
		-- If so, don't bypass even if technically "in string"
		local char_before = char_before_cursor()
		if not symmetric_delims[char_before] and in_string_or_comment() then
			return "<BS>"
		end
		return handle_backspace()
	end, opts_expr)

	-- Insert mode: delete
	vim.keymap.set("i", "<Del>", function()
		local char_at = char_at_cursor()
		if not symmetric_delims[char_at] and in_string_or_comment() then
			return "<Del>"
		end
		return handle_delete()
	end, opts_expr)

	-- Normal mode: x (delete char under cursor)
	vim.keymap.set("n", "x", function()
		local char_at = char_at_cursor()
		if not symmetric_delims[char_at] and in_string_or_comment() then
			return "x"
		end
		return handle_x_normal()
	end, opts_expr_noremap)

	-- Normal mode: X (delete char before cursor)
	vim.keymap.set("n", "X", function()
		local bufnr = vim.api.nvim_get_current_buf()
		local cursor = vim.api.nvim_win_get_cursor(0)
		local char_before = get_char_at(bufnr, cursor[1] - 1, cursor[2] - 1)
		if not symmetric_delims[char_before] and in_string_or_comment() then
			return "X"
		end
		return handle_X_normal()
	end, opts_expr_noremap)

	-- Normal mode: s (substitute - block on delimiters)
	vim.keymap.set("n", "s", function()
		if in_string_or_comment() then
			return "s"
		end
		return handle_s_normal()
	end, opts_expr_noremap)
end

-- Manual commands for when you need to force operations
local function setup_commands()
	vim.api.nvim_create_user_command("StrictPareditForceDelete", function()
		vim.cmd("normal! x")
	end, { desc = "Force delete character (bypass strict paredit)" })

	vim.api.nvim_create_user_command("StrictPareditForceBackspace", function()
		vim.cmd("normal! X")
	end, { desc = "Force backspace (bypass strict paredit)" })
end

-- Main setup function
function M.setup(opts)
	opts = opts or {}

	-- Default filetypes for Lisp-like languages
	local filetypes = opts.filetypes
		or {
			"clojure",
			"fennel",
			"scheme",
			"lisp",
			"racket",
			"janet",
			"hy",
			"lfe",
			"query", -- treesitter queries
		}

	-- Option to show notifications (default true)
	M.notify = opts.notify ~= false

	-- Override notify function if disabled
	if not M.notify then
		local original_notify = vim.notify
		vim.notify = function(msg, level, ...)
			if msg:match("^Strict paredit:") then
				return
			end
			return original_notify(msg, level, ...)
		end
	end

	-- Setup for specified filetypes
	vim.api.nvim_create_autocmd("FileType", {
		pattern = filetypes,
		callback = function()
			setup_buffer_keymaps()
		end,
		group = vim.api.nvim_create_augroup("StrictParedit", { clear = true }),
	})

	setup_commands()

	-- If current buffer matches, set up immediately
	local current_ft = vim.bo.filetype
	for _, ft in ipairs(filetypes) do
		if current_ft == ft then
			setup_buffer_keymaps()
			break
		end
	end
end

-- Utility: manually enable for current buffer
function M.enable()
	setup_buffer_keymaps()
end

-- Utility: check if strict mode would allow an operation
function M.can_delete_at_cursor()
	local char, row, col = char_at_cursor()
	if not char then
		return true
	end
	if not opening_delims[char] and not closing_delims[char] and not symmetric_delims[char] then
		return true
	end
	return find_delimiter_pair_at(row, col) ~= nil
end

return M
