{ pkgs, lib, ... }: {
  programs.neovim = {
    enable = lib.mkDefault true;
    viAlias = lib.mkDefault true;
    vimAlias = lib.mkDefault true;
    vimdiffAlias = lib.mkDefault true;
    extraConfig = ''
      set nocompatible
      set nobackup
    '';
    plugins = with pkgs.vimPlugins; [ vim-nix ];
  };
}
