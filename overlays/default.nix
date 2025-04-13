# overlays/default.nix
{ rpi-linux-6_12_20-src
, rpi-firmware-src
, rpi-firmware-nonfree-src
, rpi-bluez-firmware-src
, ...
}:
final: prev:

let
  versions = {
    v6_12_20 = {
      src = rpi-linux-6_12_20-src;
      version = "6.12.22";
      # Do NOT set modDirVersion here.
      # Let it default to the actual kernel output: 6.12.22-v8-16k
    };
  };

  boards = [ "bcm2711" "bcm2712" ];

  # Helpers for building the `pkgs.rpi-kernels' map.
  rpi-kernel = { version, board }:
    let
      version-slug = builtins.replaceStrings [ "v" "_" ] [ "" "." ] version;
      kernelInfo = builtins.getAttr version versions;
      modDirVersion = kernelInfo.modDirVersion or null;
    in
    {
      "${version}"."${board}" = (final.buildLinux {
        modDirVersion = modDirVersion;
        version = kernelInfo.version or version-slug;
        pname = "linux-rpi";
        src = kernelInfo.src;
        defconfig = "${board}_defconfig";
        structuredExtraConfig = with final.lib.kernel; {
          # The perl script to generate kernel options sets unspecified
          # parameters to `m` if possible [1]. This results in the
          # unspecified config option KUNIT [2] getting set to `m` which
          # causes DRM_VC4_KUNIT_TEST [3] to get set to `y`.
          #
          # This vc4 unit test fails on boot due to a null pointer
          # exception with the existing config. I'm not sure why, but in
          # any case, the DRM_VC4_KUNIT_TEST config option itself states
          # that it is only useful for kernel developers working on the
          # vc4 driver. So, I feel no need to deviate from the standard
          # rpi kernel and attempt to successfully enable this test and
          # other unit tests because the nixos perl script has this
          # sloppy "default to m" behavior. So, I set KUNIT to `n`.
          #
          # [1] https://github.com/NixOS/nixpkgs/blob/85bcb95aa83be667e562e781e9d186c57a07d757/pkgs/os-specific/linux/kernel/generate-config.pl#L1-L10
          # [2] https://github.com/raspberrypi/linux/blob/1.20230405/lib/kunit/Kconfig#L5-L14
          # [3] https://github.com/raspberrypi/linux/blob/bb63dc31e48948bc2649357758c7a152210109c4/drivers/gpu/drm/vc4/Kconfig#L38-L52
          KUNIT = no;
        };
        features.efiBootStub = false;
        kernelPatches =
          if kernelInfo ? "patches" then kernelInfo.patches else [ ];
        ignoreConfigErrors = true;
      }).overrideAttrs
        (oldAttrs: {
          postConfigure = ''
            echo "✅ Not touching CONFIG_LOCALVERSION — preserving upstream config"
          '';
        });
    };

    rpi-kernels = (
      builtins.foldl'
        (b: a: final.lib.recursiveUpdate b (rpi-kernel a))
        { }
        (final.lib.cartesianProduct { 
          board = boards; 
          version = builtins.attrNames versions; 
        })
    );

in {
  # disable firmware compression so that brcm firmware can be found at
  # the path expected by raspberry pi firmware/device tree
  compressFirmwareXz = x: x;
  compressFirmwareZstd = x: x;

  # provide generic rpi arm64 u-boot
  uboot-rpi-arm64 = final.buildUBoot {
    defconfig = "rpi_arm64_defconfig";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [ "u-boot.bin" ];
  };

  # default to latest firmware
  raspberrypiWirelessFirmware = final.callPackage
    (
      import ./raspberrypi-wireless-firmware.nix {
        bluez-firmware = rpi-bluez-firmware-src;
        firmware-nonfree = rpi-firmware-nonfree-src;
      }
    )
    { };

  raspberrypifw = prev.raspberrypifw.overrideAttrs (oldfw: { src = rpi-firmware-src; });

  rpi-kernels = {
    v6_12_20 = {
      bcm2711 = final.buildLinux {
        version = "6.12.22";
        modDirVersion = "6.12.22-v8-16k";
        pname = "linux-rpi";
        src = rpi-linux-6_12_20-src;
        defconfig = "bcm2711_defconfig";
        structuredExtraConfig = {};
        ignoreConfigErrors = true;
        extraMeta.platforms = [ "aarch64-linux" ];
      };
      bcm2712 = final.buildLinux {
        version = "6.12.22";
        modDirVersion = "6.12.22-v8-16k";
        pname = "linux-rpi";
        src = rpi-linux-6_12_20-src;
        defconfig = "bcm2712_defconfig";
        structuredExtraConfig = {};
        ignoreConfigErrors = true;
        extraMeta.platforms = [ "aarch64-linux" ];
      };
    };
  };
}