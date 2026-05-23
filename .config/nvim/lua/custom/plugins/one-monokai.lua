---@module 'lazy'
---@type LazySpec
return {
  {
    'cpea2506/one_monokai.nvim',
    priority = 1000,
    config = function()
      vim.cmd.colorscheme 'one_monokai'
    end,
  },
}
