{
  inputs,
  nixos,
  system ? "x86_64-linux",
  hostName ? "installer",
  overlays ? [ ],
  ...
}:
let
  sshKeys = import ../../lib/ssh-keys.nix;
in
nixos.lib.nixosSystem {
  inherit system;

  specialArgs = { inherit system inputs overlays; };

  modules = [
    # "${nixos}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    "${nixos}/nixos/modules/installer/cd-dvd/installation-cd-graphical-gnome.nix"
    ../../modules/nixos/nixpkgs.nix
    (
      { pkgs, lib, ... }:
      {
        # allowedUnfree = [
        #   "nvidia-persistenced"
        #   "nvidia-settings"
        #   "nvidia-x11"
        #   "cuda_cudart"
        #   "cuda-merged"
        #   "cuda_cuobjdump"
        #   "cuda_gdb"
        #   "cuda_nvcc"
        #   "cuda_nvdisasm"
        #   "cuda_nvprune"
        #   "cuda_cccl"
        #   "cuda_cupti"
        #   "cuda_cuxxfilt"
        #   "cuda_nvml_dev"
        #   "cuda_nvrtc"
        #   "cuda_nvtx"
        #   "cuda_profiler_api"
        #   "cuda_sanitizer_api"
        #   "libcublas"
        #   "libcufft"
        #   "libcurand"
        #   "libcusolver"
        #   "libnvjitlink"
        #   "libcusparse"
        #   "libcusparse_lt"
        #   "libcufile"
        #   "cudnn"
        #   "libnpp"
        # ];

        # nixpkgs.hostPlatform.system = system;
        networking.hostName = hostName;

        boot.loader.timeout = lib.mkOverride 10 10;
        documentation.enable = lib.mkOverride 10 false;
        documentation.nixos.enable = lib.mkOverride 10 false;

        boot.initrd.systemd.enable = lib.mkForce false;

        system.disableInstallerTools = lib.mkOverride 10 false;

        systemd.services.sshd.wantedBy = pkgs.lib.mkOverride 10 [ "multi-user.target" ];

        boot.kernel.sysctl = {
          "vm.swappiness" = 133;
        };

        zramSwap = {
          enable = true;
          priority = 5;
          algorithm = "zstd";
          memoryPercent = 50;
        };

        environment.systemPackages = with pkgs; [
          inputs.disko.packages.${system}.disko
          inputs.disko.packages.${system}.disko-install
          btop
          htop
          # nvtopPackages.full
          psmisc
          rclone
          reptyr
          rmlint
          lm_sensors
          pciutils
          inetutils
          nftables
          tcpdump
          traceroute
          wget
          curl
          hdparm
          smartmontools
          f3
          e2fsprogs
        ];

        users.users.nixos = {
          openssh.authorizedKeys.keys = sshKeys.default;
        };
      }
    )
  ];
}
