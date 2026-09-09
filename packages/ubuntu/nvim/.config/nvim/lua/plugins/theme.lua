return {
	{
		-- The baseline fork is unavailable; the original repository retains
		-- the exact monokai-pro.nvim commit in lazy-lock.json.
		"gthelding/monokai-pro.nvim",
		url = "https://github.com/loctvl842/monokai-pro.nvim.git",
	},
	{
		"folke/tokyonight.nvim",
		priority = 1000,
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "tokyonight-night",
		},
	},
}
