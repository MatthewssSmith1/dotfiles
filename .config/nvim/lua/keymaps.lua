local set = vim.keymap.set

set('n', '<C-s>', ':w<CR>', { desc = 'Save file' })

set('n', '<leader>x', '<cmd>source %<CR>', { desc = 'Execute the current file' })

set('n', '<Esc>', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlights with <Esc>' })

set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

set('n', '<leader>t', '<cmd>terminal<CR>', { desc = '[T]erminal mode' })

set('n', '<left>', '<cmd>echo "Use h instead"<CR>')
set('n', '<right>', '<cmd>echo "Use l instead"<CR>')
set('n', '<up>', '<cmd>echo "Use k instead"<CR>')
set('n', '<down>', '<cmd>echo "Use j instead"<CR>')

set('n', '<M-,>', '<c-w>5<', { desc = 'Increase split width' })
set('n', '<M-.>', '<c-w>5>', { desc = 'Decrease split width' })
set('n', '<M-t>', '<C-W>+', { desc = '[T]aller split' })
set('n', '<M-s>', '<C-W>-', { desc = '[S]maller split' })

set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- NOTE: Terminal keymaps
set('t', '<C-h>', '<C-\\><C-n><C-w><C-h>', { desc = 'Move focus to the left window' })
set('t', '<C-l>', '<C-\\><C-n><C-w><C-l>', { desc = 'Move focus to the right window' })
set('t', '<C-j>', '<C-\\><C-n><C-w><C-j>', { desc = 'Move focus to the lower window' })
set('t', '<C-k>', '<C-\\><C-n><C-w><C-k>', { desc = 'Move focus to the upper window' })

set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

local function floaterm(key, action)
  local cmd = '<cmd>Floaterm' .. action .. '<CR>'
  local opts = { desc = action .. ' floating temrinal' }

  vim.keymap.set({ 'n', 'i', 'v' }, key, cmd, opts)
  vim.keymap.set('t', key, '<C-\\><C-n>' .. cmd, opts)
end
floaterm('<M-i>', 'New')
floaterm('<M-j>', 'Toggle')
floaterm('<M-h>', 'Prev')
floaterm('<M-l>', 'Next')
floaterm('<M-g>', 'First')
floaterm('<M-;>', 'Last')
vim.keymap.set('t', '<M-x>', '<C-\\><C-n><cmd>FloatermKill<CR>', { desc = 'Kill floating terminal' })

-- NOTE: Auto Commands
--  Highlight when yanking (copying) text
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- vim: ts=2 sts=2 sw=2 et
