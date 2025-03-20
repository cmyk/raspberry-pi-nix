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
        mkdir -p firmware/overlays
        cp ${config.boot.kernelPackages.kernel}/dtbs/overlays/bcm2712d0.dtbo firmware/overlays/bcm2712d0.dtbo
        cat > firmware/config.txt <<EOF
[all]
arm_64bit=1
enable_uart=0
dtoverlay=disable-bt
dtoverlay=bcm2712d0
kernel=kernel.img
initramfs initrd followkernel
device_tree=bcm2712-rpi-cm5-cm5io.dtb
os_check=0
EOF
        echo "8250.nr_uarts=0 root=/dev/nvme0n1p2 rootwait console=ttyAMA10,115200 cma=512M nvme_core.default_ps_max_latency_us=0" > firmware/cmdline.txt
      '';
      populateRootCommands = ''
        echo "Populating root filesystem..."
        mkdir -p ./files
        content="$(
          echo "#!${pkgs.bash}/bin/bash"
          echo "exec ${config.system.build.toplevel}/init"
        )"
        echo "$content" > ./files/init
        chmod 744 ./files/init
        echo "DEBUG: Verifying init script in ./files"
        ls -l ./files/init
      '';
      firmwareSize = 1024; # 1 GiB
      postBuildCommands = ''
        echo "Starting post-build commands..."
        # Resize image to match NVMe partition (7.5G)
        echo "Truncating image to 7.5G..."
        truncate -s 7500M $img
        echo "Updating partition table..."
        echo ",+," | sfdisk -N 2 --no-reread $img
        eval $(partx $img -o START,SECTORS --nr 2 --pairs)
        echo "DEBUG: Partition 2 - START=$START, SECTORS=$SECTORS"
        echo "DEBUG: Before resize - ls -l ./root-fs.img"
        ls -l ./root-fs.img
        echo "DEBUG: Filesystem size before resize"
        ${pkgs.e2fsprogs}/bin/dumpe2fs ./root-fs.img | grep "Block count"
        echo "Copying root-fs.img to temp location..."
        cp ./root-fs.img /tmp/root-fs.img
        chmod 666 /tmp/root-fs.img
        echo "DEBUG: After chmod - ls -l /tmp/root-fs.img"
        ls -l /tmp/root-fs.img
        echo "DEBUG: Filesystem size before resize (temp)"
        ${pkgs.e2fsprogs}/bin/dumpe2fs /tmp/root-fs.img | grep "Block count"
        echo "Resizing filesystem to 1655808 blocks (to match NVMe partition)..."
        ${pkgs.e2fsprogs}/bin/resize2fs /tmp/root-fs.img 1655808
        echo "DEBUG: Filesystem size after resize"
        ${pkgs.e2fsprogs}/bin/dumpe2fs /tmp/root-fs.img | grep "Block count"
        echo "Copying resized root-fs.img back..."
        cp /tmp/root-fs.img ./root-fs.img
        sync
        echo "DEBUG: After copy back - ls -l ./root-fs.img"
        ls -l ./root-fs.img
        echo "DEBUG: Filesystem size after copy back"
        ${pkgs.e2fsprogs}/bin/dumpe2fs ./root-fs.img | grep "Block count"
        echo "Writing root filesystem to image with progress..."
        dd conv=notrunc if=./root-fs.img of=$img seek=$START count=$SECTORS bs=512 status=progress
        sync
        echo "DEBUG: Final image partition table"
        sfdisk -d $img
        echo "DEBUG: Extracting partition 2 from final image to verify filesystem contents..."
        dd if=$img of=/tmp/part2.img skip=$START count=$SECTORS bs=512 status=progress
        sync
        echo "DEBUG: Mounting partition 2 to check contents..."
        mkdir -p /tmp/mount-point
        mount /tmp/part2.img /tmp/mount-point -o loop
        echo "DEBUG: Contents of root filesystem"
        ls -l /tmp/mount-point
        echo "DEBUG: Contents of /init in root filesystem"
        ls -l /tmp/mount-point/init || echo "ERROR: /init not found"
        cat /tmp/mount-point/init || echo "ERROR: Cannot read /init"
        umount /tmp/mount-point
        echo "DEBUG: Filesystem size in final image partition 2"
        ${pkgs.e2fsprogs}/bin/dumpe2fs /tmp/part2.img | grep "Block count"
        echo "DEBUG: Verifying final image filesystem integrity"
        ${pkgs.e2fsprogs}/bin/fsck.ext4 -n /tmp/part2.img
        echo "Post-build commands completed."
      '';
    };
  };
}