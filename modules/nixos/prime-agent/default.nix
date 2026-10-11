{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.prime-agent;

  libraryPath = lib.makeLibraryPath (cfg.libraries ++ cfg.extraLibraries);

  # Symlinks only: every Python stays the unmodified, cached nixpkgs store
  # path (no override, no withPackages), and putting several interpreters in
  # systemPackages directly would collide on bin/python3.
  pythonLinks = pkgs.runCommand "prime-agent-pythons" { } ''
    mkdir -p $out/bin
    ${lib.concatMapStringsSep "\n" (
      p: "ln -s ${p}/bin/python${p.pythonVersion} $out/bin/python${p.pythonVersion}"
    ) cfg.pythons}
    ln -s ${pkgs.python3}/bin/python3 $out/bin/python3
  '';

  # nix-ld does not apply to nixpkgs Pythons (they load extension modules
  # through nix's glibc loader), so manylinux wheels such as numpy need their
  # shared libraries on LD_LIBRARY_PATH. Scope it to prime-agent and its
  # children instead of the whole system. The inner wrapper (uv on PATH,
  # defaults) and the real binary under libexec/ stay untouched.
  wrapped =
    pkgs.runCommand "prime-agent-wrapped"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "prime-agent";
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${cfg.package}/bin/prime-agent $out/bin/prime-agent \
          --suffix LD_LIBRARY_PATH : ${libraryPath}
      '';
in
{
  options.chrisportela.prime-agent = {
    enable = lib.mkEnableOption "prime-agent and a NixOS environment its uv-managed Python kernel and downloaded tools can run in";

    package = lib.mkOption {
      type = lib.types.package;
      # NixOS hosts do not get the home overlays, so fall back to building it
      # from the repo (agent-vms reads ../../../pkgs/claude-code the same way).
      default = pkgs.prime-agent or (pkgs.callPackage ../../../pkgs/prime-agent/default.nix { });
      defaultText = lib.literalExpression "pkgs.prime-agent";
      description = "The prime-agent package to wrap and install.";
    };

    pythons = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        python311
        python312
        python313
        python314
      ];
      defaultText = lib.literalExpression "with pkgs; [ python311 python312 python313 python314 ]";
      description = ''
        Interpreters exposed on PATH as `python3.X`. uv is configured to use
        only these, so keep them unmodified nixpkgs packages (cache hits).
        prime-agent asks for 3.11.
      '';
    };

    libraries = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        zstd
        xz
        bzip2
        openssl
        libffi
        sqlite
        expat
        ncurses
        readline
        libxml2
        libxslt
        glib
        util-linux.lib
      ];
      defaultText = lib.literalExpression "[ stdenv.cc.cc.lib zlib openssl ... ]";
      description = ''
        Shared libraries that downloaded wheels and prebuilt binaries link
        against. Used for prime-agent's LD_LIBRARY_PATH and for nix-ld.
      '';
    };

    extraLibraries = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "with pkgs; [ libGL xorg.libX11 fontconfig ]";
      description = "Additional libraries appended to `libraries` (for example GUI libraries).";
    };

    nixLd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable `programs.nix-ld` with the same libraries, so prebuilt
        executables the agent downloads (uvx tools, npm binaries) run.
      '';
    };

    toolchain.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install a C toolchain (gcc, gnumake, pkg-config, cmake) so uv can build source distributions.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      wrapped
      pythonLinks
      pkgs.uv
      pkgs.git
    ]
    ++ lib.optionals cfg.toolchain.enable (
      with pkgs;
      [
        gcc
        gnumake
        pkg-config
        cmake
      ]
    );

    # uv's system-level config (user and project config, env vars and CLI
    # flags still override it): use the nixpkgs Pythons above and never
    # download python-build-standalone builds.
    environment.etc."uv/uv.toml".text = ''
      python-preference = "only-system"
      python-downloads = "never"
    '';

    programs.nix-ld = lib.mkIf cfg.nixLd.enable {
      enable = true;
      libraries = cfg.libraries ++ cfg.extraLibraries;
    };
  };
}
