-- respect term colors
vim.o.termguicolors = false
vim.cmd("highlight Normal ctermbg=NONE ctermfg=NONE")

-- cursor line for the current line highlit to work
vim.wo.cursorline = true
vim.o.linespace = 0   -- line spacing between rows
vim.o.numberwidth = 3

-- line num
vim.wo.relativenumber = false
vim.wo.number = true
vim.cmd("highlight LineNr ctermfg=Blue ctermbg=NONE")           -- normal lines
vim.cmd("highlight CursorLineNr ctermfg=Yellow ctermbg=NONE gui=bold") -- current line

vim.api.nvim_set_hl(0, "MyTodo", { fg="#ff5555", bold=true })
vim.cmd("syntax match MyTodo /TODO:/ containedin=ALL")
