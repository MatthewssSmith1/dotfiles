return {
  {
    'cpea2506/one_monokai.nvim',
    priority = 1000,
    init = function()
      vim.cmd.colorscheme 'one_monokai'
    end,
  },
}