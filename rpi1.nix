{
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  nixpkgs.hostPlatform = "armv6l-linux"; # vintage pi
  nixpkgs.buildPlatform = "aarch64-linux"; # cross-compile

  imports = [ "${modulesPath}/installer/sd-card/sd-image-raspberrypi.nix" ];
  disabledModules = [
    "${modulesPath}/profiles/all-hardware.nix"
    "${modulesPath}/profiles/base.nix"
  ];

  system.stateVersion = "25.05";
  system.copySystemConfiguration = true;

  # trim down initrd modules
  boot.supportedFilesystems = lib.mkForce [
    "vfat"
    "ext4"
  ];
  boot.initrd = {
    includeDefaultModules = false;
    kernelModules = [
      "ext4"
      "mmc_block"

      # https://www.raspberrypi.com/documentation/computers/processors.html#bcm2835
      "bcm2835_dma"
      "i2c_bcm2835"
      "vc4" # Broadcom VideoCore 4 graphics driver
    ];
    availableKernelModules = lib.mkForce [
      "mmc_block"
      "usbhid"
      "hid_generic"
    ];
  };
  boot.kernel.sysctl = {
    "vm.swappiness" = 60;
  };

  zramSwap = {
    enable = true;
    priority = 5;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  networking = {
    hostName = "nixos";
    wireless.enable = true;
    wireless.userControlled.enable = true;
    #networkmanager.enable = false;
    #networkmanager.plugins = lib.mkForce [];
    # Prevent host becoming unreachable on wifi after some time.
    #networkmanager.wifi.powersave = false;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
  };

  security.sudo.wheelNeedsPassword = false;

  programs.zsh.enable = true;
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  environment.systemPackages = with pkgs; [
    htop
    util-linux
    kmod
    usbutils
    iproute2
    nftables
    curl
    wget
    browsh
    lynx
  ];

  # Add user to group
  users = {
    groups.admin = { };
    groups.wheel = { };

    users.admin = {
      isNormalUser = true;
      group = "admin";
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      initialPassword = "nimda"; # Need some kind of password to login
    };
  };

  nixpkgs.overlays = [
    (
      final: prev:
      let
        inherit (final.stdenv.hostPlatform) isAarch32;
        isCross = final.stdenv.buildPlatform != final.stdenv.hostPlatform;

        # Fix host arch for armv6 cross compiling
        # https://github.com/NixOS/nixpkgs/pull/402768
        patchUboot =
          drv:
          drv.override (originalArgs: {
            extraPatches =
              originalArgs.extraPatches or [ ]
              ++ lib.optional (isCross && isAarch32) (
                final.fetchpatch {
                  url = "https://patchwork.ozlabs.org/series/454366/mbox/";
                  hash = "sha256-n2TaQ/HOV588nAbd1ttJf3Knn2L5181VjEG5xDwjlT8=";
                }
              );
          });
      in
      {
        ubootRaspberryPi = patchUboot prev.ubootRaspberryPi;
        ubootRaspberryPiZero = patchUboot prev.ubootRaspberryPiZero;

        linuxKernel = prev.linuxKernel // {
          packages = prev.linuxKernel.packages // {
            # Disable drivers which fail to build under nixpkgs
            linux_rpi1 = prev.linuxKernel.packages.linux_rpi1.extend (
              kself: ksuper: {
                kernel = (
                  ksuper.kernel.override (originalArgs: {
                    kernelPatches =
                      (originalArgs.kernelPatches or [ ])
                      ++ lib.trace "using linux_rpi1 with config patch" [
                        {
                          name = "disable-broken-div64";
                          patch = null;
                          extraStructuredConfig = with lib.kernel; {
                            # pwm-rp1
                            PWM_RP1 = no;
                            # i2c-designware-core
                            I2C_DESIGNWARE_CORE = no;
                            I2C_DESIGNWARE_SLAVE = no;
                            I2C_DESIGNWARE_PLATFORM = no;
                            I2C_DESIGNWARE_PCI = no;
                            # rp1-cfe  Raspberry Pi PiSP Camera Front End
                            VIDEO_RP1_CFE = no;
                          };
                        }
                      ];
                  })
                );
              }
            );
          };
        };

        # https://github.com/NixOS/nixpkgs/issues/126755#issuecomment-869149243
        makeModulesClosure =
          args:
          prev.makeModulesClosure (
            args
            // lib.optionalAttrs isAarch32 {
              allowMissing = true;
            }
          );
      }
    )
  ];
}
