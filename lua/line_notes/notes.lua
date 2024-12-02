local M = {}
local notes = {}

local notes_file = vim.fn.stdpath("data") .. "/line_notes.json"

vim.fn.sign_define("LineNote", {
  text = "🗒️",
  texthl = "Comment",
  numhl = "",

})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
  callback = function()
    M.load_notes_for_buffer()
  end,
})


function M.add_note()
  local line = vim.fn.line('.')
  local note = vim.fn.input("Add a note: ")
  local bufnr = vim.api.nvim_get_current_buf()

  if bufnr == -1 or vim.api.nvim_buf_is_valid(bufnr) == false then
    print("Error: Invalid buffer!")
    return
  end

  table.insert(notes, { line = line - 1, note = note, file = vim.fn.expand("%") })

  vim.fn.sign_place(line, "LineNotesGroup", "LineNote", bufnr, { lnum = line })

  M.save_notes()
end

function M.delete_note()
  local line = vim.fn.line('.')
  local bufnr = vim.api.nvim_get_current_buf()

  -- Validate buffer
  if vim.api.nvim_buf_is_valid(bufnr) == false then
    print("Error: Invalid buffer!")
    return
  end

  -- Find and remove the mark
  for idx, mark in ipairs(notes) do
    if mark.file == vim.fn.expand("%") and mark.line == line - 1 then
      table.remove(notes, idx)

      -- Remove the sign for the specific line
      local result = vim.fn.sign_unplace("LineNotesGroup", { id = line, buffer = bufnr })
      if result == nil then
        print("Error: Failed to unplace sign")
      else
        print("Note deleted")
      end

      -- Save notes to persist changes
      M.save_notes()
      return
    end
  end

  print("No note found on this line")
end

function M.load_notes_for_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = vim.fn.expand("%")

  if not notes or type(notes) ~= "table" then
    return
  end

  vim.fn.sign_unplace("LineNotesGroup", { buffer = bufnr })

  for _, mark in ipairs(notes) do
    if mark.file == current_file then
      local lnum = mark.line + 1
      vim.fn.sign_place(lnum, "LineNotesGroup", "LineNote", bufnr, { lnum = lnum })
    end
  end
end

function M.show_note()
  local line = vim.fn.line('.')
  local file = vim.fn.expand("%")

  -- Find the note for the current line and file
  local note_idx = nil
  local original_note = nil
  for idx, mark in ipairs(notes) do
    if mark.file == file and mark.line + 1 == line then
      original_note = mark.note
      note_idx = idx
      break
    end
  end

  if not original_note then
    print("No note found on this line")
    return
  end

  -- Split the original note into lines for the buffer
  local note_lines = vim.split(original_note, "\n", { plain = true })

  -- Create a modifiable buffer for editing the note
  local buf = vim.api.nvim_create_buf(false, true)      -- Create an unlisted, scratch buffer
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile") -- Mark it as a scratch buffer
  vim.api.nvim_buf_set_option(buf, "modifiable", true)  -- Allow modifications
  vim.api.nvim_buf_set_option(buf, "swapfile", false)   -- Prevent swapfile creation

  -- Set the note text in the buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, note_lines)

  -- Open the buffer in a floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 50,
    height = 10,
    row = math.floor((vim.o.lines - 10) / 2),
    col = math.floor((vim.o.columns - 50) / 2),
    style = "minimal",
    border = "rounded",
  })

  -- Save changes back to the notes table and JSON file when the buffer is closed
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      local edited_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local new_note = table.concat(edited_lines, "\n")

      -- Update the note in the table if it has changed
      if note_idx and new_note ~= original_note then
        notes[note_idx].note = new_note
        M.save_notes()
      else
        print("No changes made to the note.")
      end

      -- Close the floating window and buffer
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })

  -- Suppress E382 notifications when the user attempts to write the buffer
  vim.api.nvim_buf_set_keymap(buf, "n", ":w", ":echo 'Cannot save scratch buffers'<CR>",
    { noremap = true, silent = true })
end

function M.save_notes()
  local file = io.open(notes_file, "w")
  if file then
    local encoded = vim.fn.json_encode(notes)
    file:write(encoded)
    file:close()
    print("Notes updated")
  else
    print("Error: Unable to save notes")
  end
end

function M.load_notes()
  local file = io.open(notes_file, "r")
  if file then
    local content = file:read("*a")
    file:close()
    local decoded = vim.fn.json_decode(content)
    if decoded then
      notes = decoded

      local bufnr = vim.api.nvim_get_current_buf()
      vim.fn.sign_unplace("LineNotesGroup", { buffer = bufnr })

      -- Reapply signs for existing notes
      for _, mark in ipairs(notes) do
        -- Check if the mark belongs to the current file
        if mark.file == vim.fn.expand("%") then
          local lnum = mark.line + 1
          vim.fn.sign_place(lnum, "LineNotesGroup", "LineNote", bufnr, { lnum = lnum })
        end
      end
    else
      print("Error: Failed to decode notes!")
    end
  else
    print("No saved notes found")
  end
end

return M
