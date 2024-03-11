{ pkgs, src, ... }: pkgs.rustPlatform.buildRustPackage rec {
  pname = "hush";
  version = "0.1.5a";

  inherit src;

  cargoSha256 = "sha256-bm3VAzD3bSAtjyeG4PvMAmPW0N+QPqPHzcZAekKZy5o=";

  doCheck = false;

  meta = with pkgs.lib; {
    description = "Hush shell";
    homepage = "https://github.com/hush-shell/hush";
    license = licenses.mit;
    maintainers = [ ];
  };
}
