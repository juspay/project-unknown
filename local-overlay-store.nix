let
  lowerStoreDir = "/nix/lower/store";
  daemonSocket = "/nix/lower/var/nix/daemon-socket/socket";
  upperDir = "/var/lib/nix/overlay/upper";
  workDir = "/var/lib/nix/overlay/work";
in
{
  incusProfile = {
    name = "local-overlay-store";
    devices = {
      nix-store-ro = {
        type = "disk";
        source = "/nix/store";
        path = lowerStoreDir;
        readonly = true;
      };
      nix-daemon-socket = {
        type = "disk";
        source = "/nix/var/nix/daemon-socket";
        path = builtins.dirOf daemonSocket;
      };
    };
  };

  nixosModule = { pkgs, node, ... }: {
    nix.settings = {
      experimental-features = [ "local-overlay-store" ];
      trusted-users = [ "root" node.admin.name ];
      store = "local-overlay://?root=/&lower-store=unix%3A%2F%2F${daemonSocket}&lower-store.real%3D${lowerStoreDir}&upper-layer=${upperDir}&check-mount=false";
    };

    systemd.services.local-overlay-store-mount = {
      description = "OverlayFS mount for shared Nix store";
      wantedBy = [ "local-fs.target" ];
      before = [ "nix-daemon.service" ];
      after = [ "local-fs.target" ];
      requiredBy = [ "nix-daemon.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.util-linux ];
      script = ''
        mkdir -p ${upperDir} ${workDir}
        mount -t overlay overlay \
          -o lowerdir=${lowerStoreDir} \
          -o upperdir=${upperDir} \
          -o workdir=${workDir} \
          /nix/store
      '';
    };

    systemd.tmpfiles.rules = [
      "d /nix/var/nix 0755 root root -"
      "d /nix/var/nix/db 0755 root root -"
      "d /nix/var/nix/profiles 0755 root root -"
    ];
  };
}
