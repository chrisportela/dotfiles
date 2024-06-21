{ inputs, nixosModules, overlays ? [ ], ... }:
let
  hardwareConfig = import ../hardware/ada.nix;
in
inputs.nixos.lib.nixosSystem {
  specialArgs = {
    inherit inputs overlays;
    nixpkgs = inputs.nixos;
  };

  modules = [
    inputs.vscode-server.nixosModules.default
    nixosModules.common
    # nixosModules.ddc  # is, In-Fact, The Source of udev boot slowness
    nixosModules.dualboot
    nixosModules.nixpkgs
    nixosModules.openssh
    hardwareConfig

    ({ pkgs, config, lib, ... }: {

      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "steam"
        "steam-original"
        "steam-run"
        "nvidia-persistenced"
        "nvidia-settings"
        "nvidia-x11"
        "cuda_cudart"
        "cuda-merged"
        "cuda_cuobjdump"
        "cuda_gdb"
        "cuda_nvcc"
        "cuda_nvdisasm"
        "cuda_nvprune"
        "cuda_cccl"
        "cuda_cupti"
        "cuda_cuxxfilt"
        "cuda_nvml_dev"
        "cuda_nvrtc"
        "cuda_nvtx"
        "cuda_profiler_api"
        "cuda_sanitizer_api"
        "libcublas"
        "libcufft"
        "libcurand"
        "libcusolver"
        "libnvjitlink"
        "libcusparse"
        "libnpp"
        "1password"
        "1password-cli"
        "ookla-speedtest"
      ];

      security.acme = {
        acceptTerms = true;
        defaults = {
          dnsResolver = "liara.gorgon-basilisk.ts.net";
          email = "chris@cafecito.cloud";
          server = "https://ca.cafecito.cloud/acme/acme/directory";
          webroot = "/var/lib/acme/acme-challenge";
        };
      };

      security.pki.certificates = [
        ''
          Root Cafecito Cloud CA
          =======================
          ${builtins.readFile ../../cafecitocloud-root_ca.crt}
        ''
        ''
          YubiKey 4 Cafecito Cloud Intermediate CA
          =======================
          ${builtins.readFile ../../cafecitocloud-yubikey4-intermediate_ca.crt}
        ''
      ];

      # Enable networking
      networking = {
        hostName = "ada";
        hostId = "5bc6e263";

        # wireless.enable = true; # Enables wireless support via wpa_supplicant.
        dhcpcd.enable = false;
        useDHCP = false;
        useNetworkd = true;
        networkmanager.enable = true;

        # nameservers = [ "1.1.1.1#853" ];

        interfaces.enp6s0.useDHCP = true;
        interfaces.wlo1.useDHCP = true;

        nftables.enable = true;
        nftables.checkRuleset = true;
        firewall = {
          enable = true;
          allowedTCPPorts = config.services.openssh.ports;
          allowedUDPPorts = [ config.services.tailscale.port ];
          trustedInterfaces = [ "tailscale0" "docker0" ];
        };
      };

      # Prevent wait-online from stopping boot or switching config
      boot.initrd.systemd.network.wait-online.enable = false;
      systemd.network.wait-online.enable = false;

      environment.systemPackages = with pkgs; [
        btop
        nvtopPackages.full
        virt-manager

        # Important tools
        playonlinux

        # Hardware
        ddcutil
        ddcui
        lm_sensors
        pciutils
        glxinfo


        # Network
        inetutils
        ipcalc
        iperf3
        nftables
        tcpdump
        traceroute
        fast-cli
        ookla-speedtest
        speedtest-cli
      ];

      programs.git = {
        enable = true;
        lfs.enable = true;
      };

      services.tailscale = {
        enable = true;
        package = pkgs.tailscale;
      };

      services.ollama = {
        enable = true;
        acceleration = "cuda";
        listenAddress = "127.0.0.1:11434";
        environmentVariables = {
          OLLAMA_ORIGINS = "https://ollama.ada.i.cafecito.cloud";
        };
      };

      systemd.services.ollama-reload =
        let
          script = (pkgs.writeShellScriptBin "reload-ollama" ''
            systemctl stop ollama
            echo "Ollama service stopped"

            echo "Reloading Nvidia kernel modules"
            ${pkgs.kmod}/bin/rmmod nvidia_uvm && ${pkgs.kmod}/bin/modprobe nvidia_uvm

            echo "Starting Ollama service..."
            systemctl start ollama
          '');
        in
        {
          enable = true;
          description = "Reloads NVidia kernel modules and restarts ollama so it can use GPU after suspend.";
          after = ["suspend.target"];
          wantedBy = ["suspend.target"];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${script}/bin/reload-ollama";
          };
        };

      services.resolved = {
        enable = true;
        fallbackDns = [
          "1.1.1.1#853"
        ];
        dnssec = "false";
      };

      time.timeZone = "America/New_York";

      specialisation.desktop.configuration = {

        environment.systemPackages = with pkgs; [
          (lutris.override {
            extraLibraries = pkgs: [ ];
          })
        ];
        services.xserver = {
          # Enable the X11 windowing system.
          # enable = true;

          dpi = 180;

          # Configure keymap in X11
          xkb = {
            layout = "us";
            variant = "";
          };

          # Enable the KDE Plasma Desktop Environment.
          # desktopManager.plasma5.enable = true;
          # desktopManager.plasma5.useQtScaling = true;
        };

        # plasma6
        services.desktopManager.plasma6.enable = true;

        services.displayManager = {
          sddm.enable = true;
          sddm.enableHidpi = true;
          sddm.settings = {
            General = {
              GreeterEnvironment = "QT_SCREEN_SCALE_FACTORS=2,QT_FONT_DPI=192";
            };
          };
          sddm.wayland.enable = true;
        };
        programs.xwayland.enable = true;

        # Enable CUPS to print documents.
        services.printing.enable = true;

        # Enable sound with pipewire.
        sound.enable = true;
        hardware.pulseaudio.enable = false;
        security.rtkit.enable = true;
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
          # If you want to use JACK applications, uncomment this
          # jack.enable = true;

          # use the example session manager (no others are packaged yet so this is enabled by default, no
          # need to redefine it in your config for now)
          # wireplumber.enable = true;
        };

        services.vscode-server.enable = false;

        programs._1password.enable = true;
        programs._1password-gui.enable = true;
        programs._1password-gui.polkitPolicyOwners = [ "cmp" ];
        security.pam.services.kwallet.enableKwallet = true;


        programs.steam = {
          enable = true;
          remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
          dedicatedServer.openFirewall = false; # Open ports in the firewall for Source Dedicated Server
          gamescopeSession.enable = true;
        };

        virtualisation = {
          virtualbox.host = {
            enable = true;
          };
          libvirtd.enable = true;
        };
        programs.dconf.enable = true; # For libvirtd

        environment.sessionVariables = {
          STEAM_FORCE_DESKTOPUI_SCALING = "2";
          NIXOS_OZONE_WL = "1";
        };
      };

      boot.plymouth = {
        enable = true;
        # logo = "";
        # theme = "bgrt";
      };

      programs.neovim = {
        enable = true;
        viAlias = true;
        vimAlias = true;
      };

      services.vscode-server.enable = lib.mkDefault true;

      virtualisation = {
        docker = {
          enable = true;
          enableNvidia = true;
          storageDriver = "zfs";
        };
        oci-containers.backend = "docker";
        # virtualbox.host = {
        #   enable = true;
        # };
        # libvirtd.enable = true;
      };
      # programs.dconf.enable = true; # For libvirtd

      # Ollama Web UI
      virtualisation.oci-containers.containers.open-webui = {
        autoStart = true;
        image = "ghcr.io/open-webui/open-webui";
        # TODO figure out how to create the data directory declaratively
        volumes = [ "${config.users.users.cmp.home}/open-webui:/app/backend/data" ];
        extraOptions = [ "--network=host" "--add-host=host.containers.internal:host-gateway" ];
        environment = {
          OLLAMA_API_BASE_URL = "http://127.0.0.1:11434/api";
          OLLAMA_BASE_URL = "http://127.0.0.1:11434";
        };
      };


      users.users.nginx.extraGroups = [ "acme" ];

      services.nginx = {
        enable = true;

        virtualHosts = {
          "ollama.ada.i.cafecito.cloud" = {
            forceSSL = true;
            enableACME = true;

            locations."/" = {
              proxyPass = "http://127.0.0.1:11434";
              #recommendedProxySettings = true;
              extraConfig = ''
                proxy_set_header Host localhost:11434;
              '';
            };

            extraConfig = ''
              access_log /var/log/nginx/ollama-cafeito_cloud.access.log;
              error_log /var/log/nginx/ollama-cafeito_cloud.error.log;
            '';
          };

          "chat.ada.i.cafecito.cloud" = {
            forceSSL = true;
            enableACME = true;

            locations."/" = {
              proxyPass = "http://127.0.0.1:8080";
              recommendedProxySettings = true;
            };

            extraConfig = ''
              access_log /var/log/nginx/chat-cafeito_cloud.access.log;
              error_log /var/log/nginx/chat-cafeito_cloud.error.log;
            '';
          };
        };
      };

      users.users.cmp = {
        extraGroups = [
          "networkmanager"
          "wheel"
          "libvirtd"
          "ddc"
          "docker"
        ];

        packages = with pkgs; [ firefox kate ];
      };

      system.stateVersion = "23.05";
    })
  ];
}
