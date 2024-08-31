return {
  {
    'cpea2506/one_monokai.nvim',
    priority = 1000,
    init = function()
      vim.cmd.colorscheme 'one_monokai'
    end,
  },
}
-- vim: ts=2 sts=2 sw=2 et
