{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.chrisportela.aws-client-vpn;
in
{
  options.chrisportela.aws-client-vpn = {
    enable = lib.mkEnableOption "the AWS Client VPN (SAML) client";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.aws-client-vpn;
      defaultText = lib.literalExpression "pkgs.aws-client-vpn";
      description = "Package providing the aws-client-vpn command.";
    };

    awscli = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the AWS CLI, which `aws-client-vpn --endpoint` uses to export a
        profile from an endpoint. Not needed when the .ovpn profile is supplied
        by hand.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ] ++ lib.optional cfg.awscli pkgs.awscli2;

    # openvpn needs /dev/net/tun; it is usually autoloaded, but a headless or
    # minimal host may not have pulled the module in yet.
    boot.kernelModules = [ "tun" ];
  };
}
