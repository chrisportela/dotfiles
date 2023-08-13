{ pkgs, inputs, ... }: pkgs.rustPlatform.buildRustPackage rec {
  pname = "hush";
  version = "0.1.5a";

  src = inputs.hush;

  cargoSha256 = "sha256-0WYC4ScLNYE1jKEfWeYaBeY1Zl+gQa1Wl7xJK0CI8+I=";

  doCheck = false;

  meta = with pkgs.lib; {
    description = "Hush shell";
    homepage = "https://github.com/hush-shell/hush";
    license = licenses.mit;
    maintainers = [ ];
  };
};
