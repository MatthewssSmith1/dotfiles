// Omarchy broadcasts SIGUSR2 to clients AND servers when switching themes.
// The client refreshes its palette; a server must not exit on the same signal.
export default {
  id: "dotfiles.opencode.theme-signal",
  setup() {
    const ignoreThemeSignal = () => {};
    process.on("SIGUSR2", ignoreThemeSignal);
    return () => process.off("SIGUSR2", ignoreThemeSignal);
  },
};
