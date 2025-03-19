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
        # Create a disable-uart overlay
        cat > firmware/overlays/disable-uart.dts <<EOF
    /dts-v1/;
    /plugin/;

    / {
        compatible = "brcm,bcm2712";
        fragment@0 {
            target = <&serial0>;
            __overlay__ {
                status = "disabled";
            };
        };
    };
    EOF
        ${pkgs.dtc}/bin/dtc -I dts -O dtb -o firmware/overlays/disable-uart.dtbo firmware/overlays/disable-uart.dts
        cat > firmware/config.txt <<EOF
    [all]
    arm_64bit=1
    enable_uart=0
    dtoverlay=disable-bt
    dtoverlay=disable-uart
    kernel=kernel.img
    initramfs initrd followkernel
    device_tree=bcm2712-rpi-cm5-cm5io.dtb
    os_check=0
    EOF
        echo "8250.nr_uarts=0 root=/dev/nvme0n1p2 rootwait console=ttyAMA10,115200 cma=512M nvme_core.default_ps_max_latency_us=0" > firmware/cmdline.txt
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
      firmwareSize = 1024; # 1 GiB
      postBuildCommands = ''
        # Resize image to 8G total
        truncate -s 8G $img
        echo ",+," | sfdisk -N 2 --no-reread $img
        eval $(partx $img -o START,SECTORS --nr 2 --pairs)
        echo "DEBUG: Before resize - ls -l ./root-fs.img"
        ls -l ./root-fs.img
        echo "DEBUG: Copying root-fs.img to temp location"
        cp ./root-fs.img /tmp/root-fs.img
        chmod 666 /tmp/root-fs.img
        echo "DEBUG: After chmod - ls -l /tmp/root-fs.img"
        ls -l /tmp/root-fs.img
        ${pkgs.e2fsprogs}/bin/resize2fs /tmp/root-fs.img $((SECTORS - 32768))
        echo "DEBUG: Copying resized root-fs.img back"
        chmod 666 ./root-fs.img
        echo "DEBUG: After chmod on original - ls -l ./root-fs.img"
        ls -l ./root-fs.img
        cp /tmp/root-fs.img ./root-fs.img
        dd conv=notrunc if=./root-fs.img of=$img seek=$START count=$SECTORS
      '';
    };
  };
}