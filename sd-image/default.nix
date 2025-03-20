{ config, lib, pkgs, ... }: {
  imports = [ ./sd-image.nix ];
  config = {
    boot.loader.grub.enable = false;
    boot.consoleLogLevel = lib.mkDefault 7;
    boot.kernelParams = [
      "root=/dev/nvme0n1p2"
      "rootfstype=ext4"
      "fsck.repair=yes"
      "rootwait"
      "console=ttyAMA10,115200"
      "coherent_pool=2M"
      "cma=512M"
      "nvme_core.default_ps_max_latency_us=0"
    ];
    sdImage = {
      populateFirmwareCommands = ''
        cp ${config.boot.kernelPackages.kernel}/Image firmware/kernel.img
        cp ${config.system.build.initialRamdisk}/initrd firmware/initrd
        cp ${config.boot.kernelPackages.kernel}/dtbs/broadcom/bcm2712-rpi-cm5-cm5io.dtb firmware/bcm2712-rpi-cm5-cm5io.dtb
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bootcode.bin firmware/bootcode.bin
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/start4.elf firmware/start4.elf
        cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/fixup4.dat firmware/fixup4.dat
        mkdir -p firmware/overlays
        # https://github.com/agherzan/meta-raspberrypi/issues/1394#issuecomment-2552721960
        cp ${config.boot.kernelPackages.kernel}/dtbs/overlays/bcm2712d0.dtbo firmware/overlays/bcm2712d0.dtbo
        cat > firmware/config.txt <<EOF
[all]
arm_64bit=1
dtoverlay=bcm2712d0
dtoverlay=vc4-kms-v3d-pi5
gpu_mem=256
kernel=kernel.img
initramfs initrd followkernel
device_tree=bcm2712-rpi-cm5-cm5io.dtb
boot_order=0x20
EOF
        echo "root=/dev/nvme0n1p2 rootfstype=ext4 rootwait console=ttyAMA10,115200 coherent_pool=2M cma=512M nvme_core.default_ps_max_latency_us=0" > firmware/cmdline.txt
      '';
      populateRootCommands = ''
        echo "Populating root filesystem..."
        mkdir -p ./files/sbin
        content="#!${pkgs.bash}/bin/bash
        exec ${config.system.build.toplevel}/init"
        echo "$content" > ./files/sbin/init
        chmod +x ./files/sbin/init
        ln -s ./sbin/init ./files/init
        echo "DEBUG: Verifying init scripts in ./files"
        ls -l ./files/init ./files/sbin/init
      '';
      firmwareSize = 1024; # 1 GiB
      postBuildCommands = ''
        echo "Starting post-build commands..."
        echo "Truncating image to 8G..."
        truncate -s 8192M $img
        echo "Updating partition table..."
        echo ",+," | sfdisk -N 2 --no-reread $img
        eval $(partx $img -o START,SECTORS --nr 2 --pairs)
        echo "DEBUG: Partition 2 - START=$START, SECTORS=$SECTORS"
        echo "Ensuring root-fs.img is writable..."
        chmod 666 ./root-fs.img
        echo "Resizing filesystem to match partition..."
        ${pkgs.e2fsprogs}/bin/resize2fs ./root-fs.img $SECTORS
        echo "DEBUG: Filesystem size after resize"
        ${pkgs.e2fsprogs}/bin/dumpe2fs ./root-fs.img | grep "Block count"
        echo "Writing root filesystem to image..."
        dd conv=notrunc if=./root-fs.img of=$img seek=$START count=$SECTORS bs=512 status=progress
        sync
        echo "DEBUG: Final image partition table"
        sfdisk -d $img
        echo "Post-build commands completed."
      '';
    };
  };
}