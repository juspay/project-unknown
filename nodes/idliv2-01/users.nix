{ node, pkgs, lib, ... }:
let
  inherit (node) admin;
in
{
  users.users.pu = {
    isSystemUser = true;
    group = "pu";
    shell = lib.getExe pkgs.bash;
    extraGroups = [ "incus-admin" ];
  } // lib.optionalAttrs (!node.useSSHCA) {
    openssh.authorizedKeys.keys = admin.openssh.authorizedKeys.keys;
  };
  users.groups.pu = {};
}
