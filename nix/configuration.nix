{ config, pkgs, ... }:

{

imports = [
    ./hardware-configuration.nix
];

hardware = {
    graphics.enable = true;
    nvidia = {
        modesetting.enable = true;

	nvidiaSettings = true;
	
	open = true;

	powerManagement.enable = true;
    	powerManagement.finegrained = true;

        prime = {
            offload = {
                enable = true;
                enableOffloadCmd = true;
            };
            # nix-shell -p lshw --run "sudo lshw -c display"
	    intelBusId = "PCI:0:2:0";  # Example Intel ID
            nvidiaBusId = "PCI:1:0:0"; # Example Nvidia ID
        };
    };
};

boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernel.sysctl."vm.swappiness" = 10;
    loader = {
        efi = {
            canTouchEfiVariables = true;
	};

        grub = {
	    enable = true;
            efiSupport = true;
            device = "nodev";

  # 1. FORCE THE CANVAS TO BE BIG (Crucial for size 48)
  # 1920x1080 is safe, but since you have a high-end i9 laptop, 
  # you could even try "2560x1440" if your screen is 2K+.
            gfxmodeEfi = "2560x1600";
  
  # 2. NOW THE GIANT FONT WILL FIT COMPLETELY
            font = "${pkgs.hack-font}/share/fonts/hack/Hack-Regular.ttf";
            fontSize = 48; 

            splashImage = null;
            backgroundColor = "#000000";	
	};
    };
};

systemd.services.greetd.serviceConfig = {
    Type = "idle";
    StandardInput = "tty";
    StandardOutput = "tty";
    StandardError = "journal"; # Redirects boot errors to the journal instead of screen
    TTYReset = true;
    TTYVHangup = true;
    TTYVTDisallocate = true;
};

zramSwap.enable = true;

networking = {
    firewall = {
        enable = true;
        allowPing = true;
        allowedTCPPorts = [];
        allowedUDPPorts = [];
        logRefusedConnections = true;
        checkReversePath = false; # for libvirtd
    };

    hostName = "flow";

    networkmanager = {
        enable = true;
    	ethernet.macAddress = "random";
	wifi.scanRandMacAddress = true;
    };
};

time.timeZone = "Europe/Warsaw";
i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
        LC_ADDRESS = "pl_PL.UTF-8";
        LC_IDENTIFICATION = "pl_PL.UTF-8";
        LC_MEASUREMENT = "pl_PL.UTF-8";
        LC_MONETARY = "pl_PL.UTF-8";
        LC_NAME = "pl_PL.UTF-8";
	LC_NUMERIC = "pl_PL.UTF-8";
	LC_PAPER = "pl_PL.UTF-8";
        LC_TELEPHONE = "pl_PL.UTF-8";
        LC_TIME = "pl_PL.UTF-8";
    };
};

environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    
    WLR_NO_HARDWARE_CURSORS = "1";

    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
    __VK_LAYER_NV_optimus = "NVIDIA_only";
};


services = {
    fstrim.enable = true;

    greetd = {
        enable = true;
	settings = {
            default_session = {
        # --time: shows a clock
        # --remember: remembers your last username
        # --cmd: what to launch after logging in
            command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
            user = "greeter";
        };
    };
};

    xserver = {
        videoDrivers = [
            "modesetting"  
	    "nvidia"
        ];

        xkb = {
            layout = "pl";
            variant = "";
        };
    };
};

console.keyMap = "pl2";

users.users."rog" = {
    isNormalUser = true;
    description = "rog";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
    shell = pkgs.fish;
};

nixpkgs.config.allowUnfree = true;
nix = {
     #settings.experimental-features = [ "nix-command" "flakes" ];
#    gc = {
#        automatic = true;
#        dates = "weekly";
#        options = "--delete-older-than 7d";
#    };
#    settings.auto-optimise-store = true;
};

environment.systemPackages = with pkgs; [
    alacritty
    atlauncher
    awww
    
    bat
    brave
    brightnessctl
    
    curl
    
    duf
    
    eza
    
    fd
    
    gedit
    
    hyprpaper
    hyprsunset
    hyprlauncher
    htop
    
    kitty
    
    mpv

    nvtopPackages.full

    pfetch

    ripgrep
    
    unrar
    unzip
    
    wget
    
    xz

    yt-dlp

    ffmpegthumbnailer # For video thumbnails (mp4, mkv, avi)
    imagemagick       # For advanced image formats
    poppler-utils     # For PDF previews
    webp-pixbuf-loader # For .webp images in GTK file pickers
    libgepub          # For epub/book covers
];

programs = {
    chromium.enable = true;
    git.enable = true;
    hyprland.enable = true;
    neovim.enable = true;

    firefox = {
        enable = true;

        policies = {
            DisableTelemetry = true;
	    DisableFirefoxStudies = true;

	    Preferences = {
                "ui.systemUsesDarkTheme" = 1;          
                "browser.theme.content-theme" = 0;    
                "browser.theme.toolbar-theme" = 0;
		"extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
            };

            ExtensionSettings = {
                "uBlock0@raymondhill.net" = {
                    installation_mode = "force_installed";
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
                };
                "addon@darkreader.org" = {
                    installation_mode = "force_installed";
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
                };
                "w@violentmonkey.org" = {
                    installation_mode = "force_installed";
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/violentmonkey/latest.xpi";
                };
            };
        };
    };

    fish = {
        enable = true;
    };

    nh = {
        enable = true;
  	clean.enable = true;
	clean.extraArgs = "--keep-since 4d --keep 3";
 	# Points nh to your configuration directory
  	flake = "/etc/nixos"; 
    };
};


system.stateVersion = "26.05";

}
