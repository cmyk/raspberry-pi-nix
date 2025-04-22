# raspberry-pi-nix/flake.nix
{
  description = "raspberry-pi nixos configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # rpi-linux-6_12_20-src = {
    #   flake = false;
    #   url = "github:raspberrypi/linux/rpi-6.12.y";
    # };
    # pinning 1284626bb6c6728a5b792eea2a615f9e0edde32d to avoid accidential kernel rebuilds
    rpi-linux-6_12_20-src = {
      flake = false;
      url = "https://github.com/raspberrypi/linux";
      rev = "1284626bb6c6728a5b792eea2a615f9e0edde32d";
      narHash = "sha256-F5pYVExFWC3Vb7I/kyhB0+Kn3LTM0kblwc5aLopOsok=";
    };
    rpi-firmware-src = {
      flake = false;
      url = "github:raspberrypi/firmware/1.20250326";
    };
    rpi-firmware-nonfree-src = {
      flake = false;
      url = "github:RPi-Distro/firmware-nonfree/bookworm";
    };
    rpi-bluez-firmware-src = {
      flake = false;
      url = "github:RPi-Distro/bluez-firmware/bookworm";
    };
    rpicam-apps-src = {
      flake = false;
      url = "github:raspberrypi/rpicam-apps/v1.5.2";
    };
    libcamera-src = {
      flake = false;
      url = "github:raspberrypi/libcamera/69a894c4adad524d3063dd027f5c4774485cf9db"; # v0.3.1+rpt20240906
    };
    libpisp-src = {
      flake = false;
      url = "github:raspberrypi/libpisp/v1.0.7";
    };
  };

  outputs = { self, nixpkgs, rpi-linux-6_12_20-src, rpi-firmware-src, rpi-firmware-nonfree-src, rpi-bluez-firmware-src, rpicam-apps-src, libcamera-src, libpisp-src }:
    let
      pinned = import nixpkgs {
        system = "aarch64-linux";
        overlays = with self.overlays; [ core libcamera ];
      };
    in
    {
      overlays = {
        core = import ./overlays {
          inherit rpi-linux-6_12_20-src rpi-firmware-src rpi-firmware-nonfree-src rpi-bluez-firmware-src;
        };
        libcamera = import ./overlays/libcamera.nix { inherit rpicam-apps-src libcamera-src libpisp-src; };
      };
      nixosModules = {
        raspberry-pi = import ./rpi {
          inherit pinned;
          core-overlay = self.overlays.core;
          libcamera-overlay = self.overlays.libcamera;
        };
        sd-image = import ./sd-image;
      };
      # nixosConfigurations = {
      #   rpi-example = nixpkgs.lib.nixosSystem {
      #     system = "aarch64-linux";
      #     modules = [ self.nixosModules.raspberry-pi self.nixosModules.sd-image ./example ];
      #   };
      # };
      #checks.aarch64-linux = builtins.removeAttrs self.packages.aarch64-linux [ "rpi-linux-6_12_20-src" ];
      packages.aarch64-linux = {
        #example-sd-image = self.nixosConfigurations.rpi-example.config.system.build.sdImage;
        firmware = pinned.raspberrypifw;
        libcamera = pinned.libcamera;
        wireless-firmware = pinned.raspberrypiWirelessFirmware;
        uboot-rpi-arm64 = pinned.uboot-rpi-arm64;
        linux-6_12_20-bcm2712 = pinned.rpi-kernels.v6_12_20.bcm2712;
      };
    };
}