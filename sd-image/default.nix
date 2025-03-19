{ config, lib, pkgs, ... }:

{
  imports = [ ./sd-image.nix ];

  config = {
    boot.loader.grub.enable = false;

    boot.consoleLogLevel = lib.mkDefault 7;

    boot.kernelParams = [
      "root=PARTUUID=${lib.strings.removePrefix "0x" config.sdImage.firmwarePartitionID}-02"
      "rootfstype=ext4"
      "fsck.repair=yes"
      "rootwait"
    ];

    sdImage = {
      populateFirmwareCommands = ''
        cp ${config.boot.kernelPackages.kernel}/Image firmware/kernel.img
        cp ${config.system.build.initialRamdisk}/initrd firmware/initrd
        cp ${config.boot.kernelPackages.kernel}/dtbs/broadcom/bcm2712-rpi-cm5-cm5io.dtb firmware/bcm2712-rpi-cm5-cm5io.dtb
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bootcode.bin firmware/bootcode.bin
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/start4.elf firmware/start4.elf
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/fixup4.dat firmware/fixup4.dat
        echo "[all]\narm_64bit=1\nenable_uart=1\ndtoverlay=disable-bt\nkernel=kernel.img\ninitramfs initrd followkernel" > firmware/config.txt
        echo "console=ttyAMA10,115200 root=/dev/nvme0n1p2 rootwait cma=512M nvme_core.default_ps_max_latency_us=0" > firmware/cmdline.txt
      '';
      populateRootCommands = ''
        mkdir -p ./files/sbin
        content="$(
          echo "#!${pkgs.bash}/bin/bash"
          echo "exec ${config.system.build.toplevel}/init"
        )"
        echo "$content" > ./files/sbin/init
        chmod 744 ./files/sbin/init
      '';
      firmwareSize = 512; # Bump to 512 MiB
      postBuildCommands = ''
        # Resize image to 8G total
        truncate -s 8G $img
        echo ",+," | sfdisk -N 2 --no-reread $img
        eval $(partx $img -o START,SECTORS --nr 2 --pairs)
        ${pkgs.e2fsprogs}/bin/resize2fs ./root-fs.img $((SECTORS - 32768))
        dd conv=notrunc if=./root-fs.img of=$img seek=$START count=$SECTORS
      '';
    };
  };
}