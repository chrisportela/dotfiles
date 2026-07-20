{
  lib,
  linkFarm,
  homeActivation,
  devShells,
}:
linkFarm "dotfiles-cache-targets" (
  [
    {
      name = "home-manager";
      path = homeActivation;
    }
  ]
  ++ lib.mapAttrsToList (name: drv: {
    name = "shell-${name}";
    path = drv;
  }) devShells
)
