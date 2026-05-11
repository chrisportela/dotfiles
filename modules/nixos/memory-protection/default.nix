{ config, lib, ... }:

let
  cfg = config.chrisportela.memory-protection;
in
{
  options.chrisportela.memory-protection = {
    enable = lib.mkEnableOption "cgroup-based memory protection (Layer 2 + 4)";

    nixDaemon = {
      enable = lib.mkEnableOption "nix-daemon cgroup ceilings";
      memoryMax = lib.mkOption {
        type = lib.types.str;
        example = "90G";
        description = "Hard memory ceiling for nix-daemon and its build children.";
      };
      memoryHigh = lib.mkOption {
        type = lib.types.str;
        example = "75G";
        description = "Soft memory threshold; reclaim/pressure starts here.";
      };
    };

    dockerSlice = {
      enable = lib.mkEnableOption "docker.slice with cgroup ceilings (covers docker daemon + all containers)";
      memoryMax = lib.mkOption {
        type = lib.types.str;
        example = "90G";
        description = "Hard memory ceiling for the entire docker.slice.";
      };
      memoryHigh = lib.mkOption {
        type = lib.types.str;
        example = "75G";
        description = "Soft memory threshold; reclaim/pressure starts here.";
      };
    };

    userSlice = {
      enable = lib.mkEnableOption "user.slice cgroup ceilings (bounds interactive shell, KDE, browsers, games)";
      memoryMax = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "100G";
        description = "Hard memory ceiling for user.slice. Null disables the cap.";
      };
      memoryHigh = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "85G";
        description = "Soft memory threshold for user.slice. Null disables the threshold.";
      };
    };

    microvmHost = lib.mkEnableOption "host-side OOM settings for microvm@.service (biases kernel toward killing VMs before host services)";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Always-on: critical-service hardening
      {
        systemd.services.dbus.serviceConfig = {
          ManagedOOMPreference = "avoid";
          OOMScoreAdjust = -900;
          MemoryMin = "64M";
        };
        systemd.services.systemd-journald.serviceConfig = {
          ManagedOOMPreference = "avoid";
          OOMScoreAdjust = -900;
          MemoryMin = "128M";
        };
        systemd.services.sshd.serviceConfig = {
          ManagedOOMPreference = "avoid";
          OOMScoreAdjust = -900;
          MemoryMin = "32M";
        };
        systemd.services.systemd-logind.serviceConfig = {
          ManagedOOMPreference = "avoid";
          OOMScoreAdjust = -900;
        };
      }

      (lib.mkIf config.networking.networkmanager.enable {
        systemd.services.NetworkManager.serviceConfig = {
          ManagedOOMPreference = "avoid";
          OOMScoreAdjust = -800;
        };
      })

      (lib.mkIf config.services.tailscale.enable {
        systemd.services.tailscaled.serviceConfig = {
          ManagedOOMPreference = "avoid";
          OOMScoreAdjust = -800;
        };
      })

      # nix-daemon ceiling (opt-in via nixDaemon.enable)
      (lib.mkIf cfg.nixDaemon.enable {
        systemd.services.nix-daemon.serviceConfig = {
          ManagedOOMMemoryPressure = "kill";
          ManagedOOMMemoryPressureLimit = "80%";
          MemoryMax = cfg.nixDaemon.memoryMax;
          MemoryHigh = cfg.nixDaemon.memoryHigh;
        };
      })

      # docker.slice (opt-in via dockerSlice.enable)
      (lib.mkIf cfg.dockerSlice.enable {
        systemd.services.docker.serviceConfig.Slice = "docker.slice";
        systemd.slices."docker".sliceConfig = {
          MemoryMax = cfg.dockerSlice.memoryMax;
          MemoryHigh = cfg.dockerSlice.memoryHigh;
          ManagedOOMMemoryPressure = "kill";
          ManagedOOMMemoryPressureLimit = "80%";
        };
        virtualisation.docker.daemon.settings = {
          "exec-opts" = [ "native.cgroupdriver=systemd" ];
          "cgroup-parent" = "docker.slice";
        };
      })

      # user.slice (opt-in via userSlice.enable; nullable values disable)
      (lib.mkIf
        (cfg.userSlice.enable && cfg.userSlice.memoryMax != null && cfg.userSlice.memoryHigh != null)
        {
          systemd.slices."user".sliceConfig = {
            MemoryMax = cfg.userSlice.memoryMax;
            MemoryHigh = cfg.userSlice.memoryHigh;
            ManagedOOMMemoryPressure = "kill";
            ManagedOOMMemoryPressureLimit = "80%";
          };
        }
      )

      # microvm@.service host-side OOM (opt-in via microvmHost)
      (lib.mkIf cfg.microvmHost {
        systemd.services."microvm@".serviceConfig = {
          OOMScoreAdjust = 200;
          ManagedOOMPreference = "omit";
        };
      })
    ]
  );
}
