{ node, pkgs, lib, ... }:
{
  users.users.pu = {
    isSystemUser = true;
    group = "pu";
    shell = lib.getExe pkgs.bash;
    extraGroups = [ "incus-admin" ];
  } // lib.optionalAttrs (!node.useSSHCA) {
    openssh.authorizedKeys.keys = [ # TODO: autoWire from admin clanService
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFN5Ov2zDIG59/DaYKjT0sMWIY15er1DZCT9SIak07vK" # shivaraj-bh
    ];
  };
  users.groups.pu = {};
}
