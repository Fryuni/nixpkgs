{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.virtualisation.googleComputeImage;
  defaultConfigFile = pkgs.writeText "configuration.nix" ''
    { pkgs, ... }:
    {
      imports = [
        <nixpkgs/nixos/modules/virtualisation/google-compute-image.nix>
      ];

      environment.systemPackages = with pkgs; [
        jq
        git
        neovim
      ];

      nix.settings = {
        auto-optimise-store = true;

        experimental-features = [
          "nix-command"
          "flakes"
        ];

        substituters = [
          "https://nix-shell.cachix.org"
          "https://nix-community.cachix.org"
          "https://nixpkgs.cachix.org"
          "https://fryuni.cachix.org"
        ];
        trusted-public-keys = [
          "nix-shell.cachix.org-1:kat3KoRVbilxA6TkXEtTN9IfD4JhsQp1TPUHg652Mwc="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "nixpkgs.cachix.org-1:q91R6hxbwFvDqTSDKwDAV4T5PxqXGxswD8vhONFMeOE="
          "fryuni.cachix.org-1:YCNe73zqPG2YLIxxJkTXDz3/VFKcCiZAvHDIjEJIoDQ="
        ];
      };
    }
  '';
in
{

  imports = [
    ./google-compute-config.nix
    ./disk-size-option.nix
    ../image/file-options.nix
    (lib.mkRenamedOptionModuleWith {
      sinceRelease = 2411;
      from = [
        "virtualisation"
        "googleComputeImage"
        "diskSize"
      ];
      to = [
        "virtualisation"
        "diskSize"
      ];
    })
  ];

  options = {
    virtualisation.googleComputeImage.configFile = mkOption {
      type = with types; nullOr str;
      default = null;
      description = ''
        A path to a configuration file which will be placed at `/etc/nixos/configuration.nix`
        and be used when switching to a new configuration.
        If set to `null`, a default configuration is used, where the only import is
        `<nixpkgs/nixos/modules/virtualisation/google-compute-image.nix>`.
      '';
    };

    virtualisation.googleComputeImage.compressionLevel = mkOption {
      type = types.int;
      default = 6;
      description = ''
        GZIP compression level of the resulting disk image (1-9).
      '';
    };

    virtualisation.googleComputeImage.contents = mkOption {
      type = with types; listOf attrs;
      default = [ ];
      description = ''
        The files and directories to be placed in the image.
        This is a list of attribute sets {source, target, mode, user, group} where
        `source' is the file system object (regular file or directory) to be
        grafted in the file system at path `target', `mode' is a string containing
        the permissions that will be set (ex. "755"), `user' and `group' are the
        user and group name that will be set as owner of the files.
        `mode', `user', and `group' are optional.
        When setting one of `user' or `group', the other needs to be set too.
      '';
      example = literalExpression ''
        [
          {
            source = ./default.nix;
            target = "/etc/nixos/default.nix";
            mode = "0644";
            user = "root";
            group = "root";
          }
        ];
      '';
    };

    virtualisation.googleComputeImage.efi = mkEnableOption "EFI booting";
  };

  #### implementation
  config = {
    boot.initrd.availableKernelModules = [ "nvme" ];
    boot.loader.grub = mkIf cfg.efi {
      device = mkForce "nodev";
      efiSupport = true;
      efiInstallAsRemovable = true;
    };

    fileSystems."/boot" = mkIf cfg.efi {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
    };

    system.nixos.tags = [ "google-compute" ];
    image.extension = "raw.tar.gz";
    system.build.image = config.system.build.googleComputeImage;
    system.build.googleComputeImage = import ../../lib/make-disk-image.nix {
      name = "google-compute-image";
      inherit (config.image) baseName;
      postVM = ''
        PATH=$PATH:${
          with pkgs;
          lib.makeBinPath [
            gnutar
            gzip
          ]
        }
        pushd $out
        # RTFM:
        # https://cloud.google.com/compute/docs/images/create-custom
        # https://cloud.google.com/compute/docs/import/import-existing-image
        mv $diskImage disk.raw
        tar -Sc disk.raw | gzip -${toString cfg.compressionLevel} > \
          ${config.image.fileName}
        rm disk.raw
        popd
      '';
      format = "raw";
      configFile = if cfg.configFile == null then defaultConfigFile else cfg.configFile;
      inherit (cfg) contents;
      partitionTableType = if cfg.efi then "efi" else "legacy";
      inherit (config.virtualisation) diskSize;
      inherit config lib pkgs;
    };

    environment.systemPackages = with pkgs; [
      jq
      git
      neovim
    ];

    nix.settings = {
      auto-optimise-store = true;

      experimental-features = [
        "nix-command"
        "flakes"
      ];

      substituters = [
        "https://nix-shell.cachix.org"
        "https://nix-community.cachix.org"
        "https://nixpkgs.cachix.org"
        "https://fryuni.cachix.org"
      ];
      trusted-public-keys = [
        "nix-shell.cachix.org-1:kat3KoRVbilxA6TkXEtTN9IfD4JhsQp1TPUHg652Mwc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs.cachix.org-1:q91R6hxbwFvDqTSDKwDAV4T5PxqXGxswD8vhONFMeOE="
        "fryuni.cachix.org-1:YCNe73zqPG2YLIxxJkTXDz3/VFKcCiZAvHDIjEJIoDQ="
      ];
    };
  };

}
