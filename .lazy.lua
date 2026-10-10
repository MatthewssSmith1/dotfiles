return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		opts = {
			filesystem = {
				filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
          hide_by_name = {
						"generated",
            ".prettierignore",
          },
					never_show = {
						"pnpm-lock.yaml",
						"pnpm-workspace.yaml",
            ".claude",
            ".git",
            ".gitattributes",
					},
				},
			},
		},
	},
}
