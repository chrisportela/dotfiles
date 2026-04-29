{
  config,
  lib,
  ...
}:
let
  cfg = config.cafecitocloud;
in
{
  options.cafecitocloud = {
    enable = lib.mkEnableOption "Cafecito Cloud root CA trust";
  };

  config = lib.mkIf cfg.enable {
    security.pki.certificateFiles = [ ./cafecitocloud-root_ca.crt ];
  };
}
