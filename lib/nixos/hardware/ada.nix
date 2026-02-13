{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  diskoConfig = {
    disko.devices = {
      disk = {
        boot-usb = {
          type = "disk";
          device = "/dev/disk/by-id/usb-Samsung_Flash_Drive_FIT_0371324100002895-0:0";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
            };
          };
        };
        ssd0 = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NC0RA01059T";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "95%";
                content = {
                  type = "luks";
                  name = "crypt-ssd0";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "zroot";
                  };
                };
              };
            };
          };
        };
        ssd1 = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0TA31156F";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "95%";
                content = {
                  type = "luks";
                  name = "crypt-ssd1";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "zroot";
                  };
                };
              };
            };
          };
        };
        ssd2 = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0TA31162E";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "95%";
                content = {
                  type = "luks";
                  name = "crypt-ssd2";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "filesystem";
                    format = "zfs";
                    pool = "zroot";
                  };
                };
              };
            };
          };
        };
        ssd3 = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0TA31231X";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "95%";
                content = {
                  type = "luks";
                  name = "crypt-ssd3";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "filesystem";
                    format = "zfs";
                    pool = "zroot";
                  };
                };
              };
            };
          };
        };
        evo-ssd0 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-Samsung_SSD_860_EVO_4TB_S5JBNE0MA00760D";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "95%";
                content = {
                  type = "luks";
                  name = "crypt-evo-ssd0";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };
        };
        evo-ssd1 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-Samsung_SSD_860_EVO_4TB_S5JBNE0MA00764H";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-evo-ssd1";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "filesystem";
                    format = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };
        };
        intel-ssd0 = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_PHOC1502007M118B";
          content = {
            type = "gpt";
            partitions = {
              swap = {
                size = "16G";
                type = "8200";
                content = {
                  type = "swap";
                  randomEncryption = true;
                };
              };
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-intel-ssd0";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };
        };
        intel-ssd1 = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_PHOC150200RA118B";
          content = {
            type = "gpt";
            partitions = {
              swap = {
                size = "16G";
                type = "8200";
                content = {
                  type = "swap";
                  randomEncryption = true;
                };
              };
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-intel-ssd1";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "filesystem";
                    format = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };
        };
        intel-ssd2 = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_PHOC202100QM118B";
          content = {
            type = "gpt";
            partitions = {
              swap = {
                size = "16G";
                type = "8200";
                content = {
                  type = "swap";
                  randomEncryption = true;
                };
              };
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-intel-ssd2";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "zroot";
                  };
                };
              };
            };
          };
        };
        intel-ssd3 = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_PHOC2021017E118B";
          content = {
            type = "gpt";
            partitions = {
              swap = {
                size = "16G";
                type = "8200";
                content = {
                  type = "swap";
                  randomEncryption = true;
                };
              };
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-intel-ssd3";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };
        };
        hdd-wd8tb-0 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-WDC_WD80EFZX-68UW8N0_R6GH5RAY";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-hdd-wd8tb-0";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };
        };
        hdd-wd8tb-1 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-WDC_WD80EFZX-68UW8N0_R6GH8NTY";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-hdd-wd8tb-1";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };
        };
        hdd-wd8tb-2 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-WDC_WD80EFZX-68UW8N0_R6GHEM3Y";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-hdd-wd8tb-2";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };
        };
        hdd-wd8tb-3 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-WDC_WD80EFZX-68UW8N0_R6GHJ9XY";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-hdd-wd8tb-3";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };
        };
        hdd-wd14tb-0 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-WDC_WD141KFGX-68FH9N0_9RHGPXZL";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-hdd-wd14tb-0";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "hpool0";
                  };
                };
              };
            };
          };
        };
        hdd-mdd12tb-0 = {
          type = "disk";
          device = "/dev/disk/by-id/ata-HUH721212ALE601_AAJBZVEH";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-hdd-mdd12tb-0";
                  settings = {
                    allowDiscards = true;
                  };
                  # passwordFile = "/tmp/secret.key"; # Interactive prompt
                  content = {
                    type = "zfs";
                    pool = "hpool1";
                  };
                };
              };
            };
          };
        };
      };
      zpool = {
        zroot = {
          type = "zpool";
          mode = {
            topology = {
              type = "topology";
              vdev = [
                {
                  type = "draid1";
                  members = [
                    "ssd0"
                    "ssd1"
                    "ssd2"
                    "ssd3"
                  ];
                }
              ];
            };
          };
          rootFsOptions = {
            # https://wiki.archlinux.org/title/Install_Arch_Linux_on_ZFS
            acltype = "posixacl";
            atime = "off";
            compression = "zstd";
            mountpoint = "none";
            xattr = "sa";
          };
          options.ashift = "12";

          datasets = {
            "local" = {
              type = "zfs_fs";
              options.mountpoint = "none";
            };
            "local/home" = {
              type = "zfs_fs";
              mountpoint = "/home";
              options."com.sun:auto-snapshot" = "true";
            };
            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options."com.sun:auto-snapshot" = "false";
            };
            "local/persist" = {
              type = "zfs_fs";
              mountpoint = "/persist";
              options."com.sun:auto-snapshot" = "false";
            };
            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              options."com.sun:auto-snapshot" = "false";
              postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot/local/root@blank$' || zfs snapshot zroot/local/root@blank";
            };
          };
        };
        tank = {
          type = "zpool";
          mode = {
            topology = {
              type = "topology";
              vdev = [
                {
                  type = "draid1";
                  members = [
                    "hdd-wd8tb-0"
                    "hdd-wd8tb-1"
                    "hdd-wd8tb-2"
                    "hdd-wd8tb-3"
                  ];
                }
              ];
              cache = [
                "evo-ssd0"
                "evo-ssd1"
              ];
              log = [
                {
                  type = "mirror";
                  members = [
                    "intel-ssd0"
                    "intel-ssd1"
                  ];
                }
              ];
              special = [
                {
                  type = "mirror";
                  members = [
                    "intel-ssd2"
                    "intel-ssd3"
                  ];
                }
              ];
            };
          };
          rootFsOptions = {
            # https://wiki.archlinux.org/title/Install_Arch_Linux_on_ZFS
            acltype = "posixacl";
            atime = "off";
            compression = "zstd";
            mountpoint = "none";
            xattr = "sa";
          };
          options.ashift = "12";
          datasets = {
            "tank/main" = {
              type = "zfs_fs";
              mountpoint = "/mnt/tank";
              options."com.sun:auto-snapshot" = "false";
            };
          };
        };
        hpool0 = {
          type = "zpool";
          rootFsOptions = {
            # https://wiki.archlinux.org/title/Install_Arch_Linux_on_ZFS
            acltype = "posixacl";
            atime = "off";
            compression = "zstd";
            mountpoint = "none";
            xattr = "sa";
          };
          options.ashift = "12";
          datasets = {
            "hpool0/main" = {
              type = "zfs_fs";
              mountpoint = "/mnt/hpool0";
              options."com.sun:auto-snapshot" = "false";
            };
          };
        };
        hpool1 = {
          type = "zpool";
          rootFsOptions = {
            # https://wiki.archlinux.org/title/Install_Arch_Linux_on_ZFS
            acltype = "posixacl";
            atime = "off";
            compression = "zstd";
            mountpoint = "none";
            xattr = "sa";
          };
          options.ashift = "12";
          datasets = {
            "hpool1/main" = {
              type = "zfs_fs";
              mountpoint = "/mnt/hpool1";
              options."com.sun:auto-snapshot" = "false";
            };
          };
        };
      };
    };
  };
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    diskoConfig
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-intel"
    "i2c-dev"
    "nvidia-uvm" # For ollama to use GPU properly
  ];
  boot.extraModulePackages = [ ];
  boot.zfs = {
    extraPools = [
      "spool"
      "tank"
    ];
    requestEncryptionCredentials = [
      "spool"
      "spool/docker"
      "spool/home"
      "tank/main"
    ];
    forceImportRoot = false;
  };

  # Bootloader.
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    systemd-boot = {
      enable = true;
      configurationLimit = 30;
      editor = false;
      generationsDir = {
        enable = true;
        copyKernels = true;
      };
    };

    # grub = {
    #   enable = true;
    #   configurationLimit = 10;
    #   efiSupport = true;
    #   # efiInstallAsRemovable = true;
    #   devices = [ "nodev" ];
    #   # timeoutStyle = "countdown";
    #   default = "saved"; # use last option booted

    #   extraEntries = ''
    #     menuentry 'Windows' --class windows --class os {
    #       insmod part_gpt
    #       insmod fat
    #       search --no-floppy --fs-uuid --set=root BE3A-DC27
    #       chainloader /efi/Microsoft/Boot/bootmgfw.efi
    #     }
    #   '';
    # };
  };

  time.hardwareClockInLocalTime = true;

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/a0e68cd1-b6e7-4568-b2d9-f5253a34cb76";
      fsType = "ext4";
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/E6BE-1E5C";
      fsType = "vfat";
    };
  };

  swapDevices = [ { device = "/dev/disk/by-uuid/bcf75db2-0312-4d27-958e-bb608604caf4"; } ];

  boot.kernel.sysctl = {
    "vm.swappiness" = 80;
  };

  zramSwap = {
    enable = true;
    priority = 5;
    algorithm = "zstd";
    memoryPercent = 100;
  };

  # Enable OpenGL
  hardware.graphics = {
    enable = true;
    #driSupport32Bit = true;
    extraPackages = with pkgs; [
      # onevpl-intel-gpu
    ];
  };

  # https://nixos.wiki/wiki/Intel_Graphics#12th_Gen_(Alder_Lake)
  #boot.kernelParams = [ "i915.force_probe=4680" ];

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = true;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Do not disable this unless your GPU is unsupported or if you have a good reason to.
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Possible fix for discord crashing?
    nvidiaPersistenced = false;

    prime = {
      sync.enable = false;
      offload.enable = false;
      nvidiaBusId = "PCI:1:0:0";
      intelBusId = "PCI:0:2:0";
    };

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.nvidia-container-toolkit.enable = lib.mkIf config.virtualisation.docker.enable true;

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault false;
  networking.interfaces.enp6s0.useDHCP = lib.mkDefault true;
  networking.interfaces.wlo1.useDHCP = lib.mkDefault true;

  services.autosuspend = {
    enable = false;
    settings = {
      enable = true;
      interval = 30; # seconds
      idle_time = 120; # seconds
    };

    checks = {
      RemoteUsers = {
        class = "Users";
        name = ".*";
        terminal = ".*";
        host = "[0-9].*";
      };

      TmuxUsers = {
        class = "Users";
        name = ".*";
        terminal = ".*";
        host = "localhost";
      };

      LocalUsers = {
        class = "Users";
        name = ".*";
        terminal = ".*";
        host = "localhost";
      };
    };

    wakeups = {
      Systemd-Timer.match = "^(?!.*logrotate).*";
    };
  };
  services.thermald.enable = true;

  # Thunderbolt
  # https://nixos.wiki/wiki/Thunderbolt#Enroll_Thunderbolt_devices
  services.hardware.bolt.enable = true;

  nixpkgs.hostPlatform = "x86_64-linux";
  powerManagement.cpuFreqGovernor = "performance";
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
}
