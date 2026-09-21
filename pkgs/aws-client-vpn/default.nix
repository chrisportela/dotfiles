# AWS Client VPN endpoints that use SAML federated authentication speak a
# modified OpenVPN control channel, so they need an OpenVPN built from AWS's
# published patch (see ./README.md). The patched binary is kept out of $PATH
# under its own name: it cannot talk to a stock OpenVPN server.
{
  lib,
  stdenv,
  openvpn,
  writeShellApplication,
  coreutils,
  gnugrep,
  iproute2,
  python3,
  systemd,
  xdg-utils,
}:

let
  openvpn-aws = openvpn.overrideAttrs (prev: {
    pname = "openvpn-aws";

    patches = (prev.patches or [ ]) ++ [ ./openvpn-aws-2.6.patch ];

    postInstall = (prev.postInstall or "") + ''
      mv "$out/sbin/openvpn" "$out/sbin/openvpn-aws"
      if [ -e "$out/share/man/man8/openvpn.8" ]; then
        mv "$out/share/man/man8/openvpn.8" "$out/share/man/man8/openvpn-aws.8"
      fi
    '';

    # The NixOS OpenVPN tests exercise a stock server, which this build cannot
    # interoperate with.
    passthru = (prev.passthru or { }) // {
      tests = { };
    };

    meta = prev.meta // {
      description = "OpenVPN with AWS's Client VPN control-channel patch";
      mainProgram = "openvpn-aws";
      platforms = lib.platforms.linux;
    };
  });

  # update-systemd-resolved is a shell script; it needs these on PATH.
  resolvedPath = lib.makeBinPath [
    coreutils
    iproute2
    systemd
  ];
in
writeShellApplication {
  name = "aws-client-vpn";

  runtimeInputs = [
    coreutils
    gnugrep
    xdg-utils
  ];

  text = ''
    OPENVPN_AWS=${lib.escapeShellArg (lib.getExe openvpn-aws)}
    SAML_LISTENER=${lib.escapeShellArg "${./saml-listener.py}"}
    PYTHON=${lib.escapeShellArg (lib.getExe python3)}
    RESOLVED_HELPER=${lib.escapeShellArg "${openvpn-aws}/libexec/update-systemd-resolved"}
    RESOLVED_PATH=${lib.escapeShellArg resolvedPath}
    readonly OPENVPN_AWS SAML_LISTENER PYTHON RESOLVED_HELPER RESOLVED_PATH

  ''
  + builtins.readFile ./aws-client-vpn.sh;

  passthru = {
    inherit openvpn-aws;
  };

  meta = {
    description = "Connect to AWS Client VPN endpoints that use SAML federated authentication";
    longDescription = ''
      Drives the two-stage SAML handshake the proprietary AWS VPN Client
      performs: a first connection whose AUTH_FAILED reply carries the identity
      provider URL, a loopback listener that catches the assertion posted back
      by the browser, and a second connection that sends the assertion as the
      OpenVPN password.
    '';
    homepage = "https://docs.aws.amazon.com/vpn/latest/clientvpn-user/";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "aws-client-vpn";
  };
}
