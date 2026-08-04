return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		opts = {
			filesystem = {
				filtered_items = {
					always_show = {
						".gitignore",
						".gitconfig",
						".gitconfig.local.example",
						".agents",
						".lazy.lua",
					},
					never_show = {
						"generated",
						"pnpm-lock.yaml",
						"pnpm-workspace.yaml",
					},
				},
			},
		},
	},
}
