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

  config = lib.mkIf cfg.enable {
    # Implementation lands in subsequent tasks.
  };
}
