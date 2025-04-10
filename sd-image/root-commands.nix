{ config, lib, pkgs, ... }:

{
  options.sdImage = {
    populateRootCommands = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = lib.literalExpression
        "''\${config.boot.loader.generic-extlinux-compatible.populateCmd} -c \${config.system.build.toplevel} -d ./files/boot''";
      description = ''
        Shell commands to populate the ./files directory.
        All files in that directory are copied to the
        root (/) partition on the SD image. Use this to
        populate the ./files/boot (/boot) directory.
      '';
    };
  };
}