{
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
              end = "-150G";
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
              end = "-150G";
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
              end = "-150G";
              content = {
                type = "luks";
                name = "crypt-ssd2";
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
      ssd3 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB_S6B0NL0TA31231X";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              end = "-150G";
              content = {
                type = "luks";
                name = "crypt-ssd3";
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
      /*
      evo-ssd0 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Samsung_SSD_860_EVO_4TB_S5JBNE0MA00760D";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              end = "-400G";
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
              end = "-400G";
              content = {
                type = "luks";
                name = "crypt-evo-ssd1";
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
                  type = "zfs";
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
      */
    };
    zpool = {
      zroot = {
        type = "zpool";
        mode = {
          topology = {
            type = "topology";
            vdev = [
              {
                mode = "raidz1";
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
      /*
      tank = {
        type = "zpool";
        mode = {
          topology = {
            type = "topology";
            vdev = [
              {
                mode = "raidz1";
                members = [
                  "crypt-hdd-wd8tb-0"
                  "crypt-hdd-wd8tb-1"
                  "crypt-hdd-wd8tb-2"
                  "crypt-hdd-wd8tb-3"
                ];
              }
            ];
            cache = [
              "crypt-evo-ssd0"
              "crypt-evo-ssd1"
            ];
            log = [
              {
                mode = "mirror";
                members = [
                  "crypt-intel-ssd0"
                  "crypt-intel-ssd1"
                ];
              }
            ];
            special = [
              {
                mode = "mirror";
                members = [
                  "crypt-intel-ssd2"
                  "crypt-intel-ssd3"
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
      */
    };
  };
}
