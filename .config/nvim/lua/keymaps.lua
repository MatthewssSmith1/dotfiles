local set = vim.keymap.set

set('n', '<C-s>', ':w<CR>', { desc = 'Save file' })

set({ 'n', 'i', 'v' }, '<M-k>', '<Esc>', { desc = 'Easier escape sequence' })

set('n', '<Esc>', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlights with <Esc>' })

set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

set('n', '<left>', '<cmd>echo "Use h instead"<CR>')
set('n', '<right>', '<cmd>echo "Use l instead"<CR>')
set('n', '<up>', '<cmd>echo "Use k instead"<CR>')
set('n', '<down>', '<cmd>echo "Use j instead"<CR>')

set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

set('n', '<M-,>', '<c-w>5<', { desc = 'Increase split width' })
set('n', '<M-.>', '<c-w>5>', { desc = 'Decrease split width' })
set('n', '<M-t>', '<C-W>+', { desc = '[T]aller split' })
set('n', '<M-s>', '<C-W>-', { desc = '[S]maller split' })

set('n', '<leader>x', '<cmd>source %<CR>', { desc = 'Execute the current file' })
set('n', '<leader><leader>x', '<cmd>.lua<CR>', { desc = 'Execute the current line' })

set('n', '<leader>t', '<cmd>terminal<CR>', { desc = '[T]erminal mode' })

-- NOTE: Terminal keymaps
set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

set('t', '<C-h>', '<C-\\><C-n><C-w><C-h>', { desc = 'Move focus to the left window' })
set('t', '<C-l>', '<C-\\><C-n><C-w><C-l>', { desc = 'Move focus to the right window' })
set('t', '<C-j>', '<C-\\><C-n><C-w><C-j>', { desc = 'Move focus to the lower window' })
set('t', '<C-k>', '<C-\\><C-n><C-w><C-k>', { desc = 'Move focus to the upper window' })

local function floaterm(key, cmd)
  local cmd_str = '<cmd>Floaterm' .. cmd .. '<CR>'
  local opts = { desc = cmd .. ' floating temrinal' }

  vim.keymap.set('n', key, cmd_str, opts)
  vim.keymap.set('t', '<C-\\><C-n>' .. cmd_str, cmd, opts)
end
-- floaterm('<M-k>', 'New')
-- floaterm('<M-i>', 'Kill')
-- floaterm('<M-j>', 'Toggle')
-- floaterm('<M-g>', 'First')
-- floaterm('<M-h>', 'Prev')
-- floaterm('<M-l>', 'Next')
-- floaterm('<M-;>', 'Last')

set('n', '<M-i>', '<cmd>FloatermNew<CR>', { desc = 'New floating terminal' })
set('t', '<M-i>', '<C-\\><C-n><cmd>FloatermNew<CR>', { desc = 'New floating terminal' })
set('t', '<M-x>', '<C-\\><C-n><cmd>FloatermKill<CR>', { desc = 'Kill floating terminal' })
set('n', '<M-j>', '<cmd>FloatermToggle<CR>', { desc = 'Toggle floating terminal' })
set('t', '<M-j>', '<C-\\><C-n><cmd>FloatermToggle<CR>', { desc = 'Toggle floating terminal' })

set('n', '<M-g>', '<cmd>FloatermFirst<CR>', { desc = 'First floating terminal' })
set('t', '<M-g>', '<C-\\><C-n><cmd>FloatermFirst<CR>', { desc = 'First floating terminal' })
set('n', '<M-;>', '<cmd>FloatermLast<CR>', { desc = 'Last floating terminal' })
set('t', '<M-;>', '<C-\\><C-n><cmd>FloatermLast<CR>', { desc = 'Last floating terminal' })

set('n', '<M-h>', '<cmd>FloatermPrev<CR>', { desc = 'Previous floating terminal' })
set('t', '<M-h>', '<C-\\><C-n><cmd>FloatermPrev<CR>', { desc = 'Previous floating terminal' })
set('n', '<M-l>', '<cmd>FloatermNext<CR>', { desc = 'Next floating terminal' })
set('t', '<M-l>', '<C-\\><C-n><cmd>FloatermNext<CR>', { desc = 'Next floating terminal' })

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
