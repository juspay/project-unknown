let
  lowerStoreDir = "/nix/lower/store";
  daemonSocket = "/nix/lower/var/nix/daemon-socket/socket";
  upperDir = "/var/lib/nix/overlay/upper";
  workDir = "/var/lib/nix/overlay/work";
in
{
  # Overlay mounts inside unprivileged containers default to
  # redirect_dir=nofollow, which makes directory rename() return EXDEV.
  # Intercepting the mount syscall lets the host perform the mount with
  # full privileges so redirect_dir=on is honoured.
  incusPreseedConfig = {
    "security.syscalls.intercept.mount" = "true";
    "security.syscalls.intercept.mount.allowed" = "overlay";
  };

  incusPreseedDevices = {
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

  nixosModule = { pkgs, lib, node, ... }: {
    nix.settings = {
      experimental-features = [ "local-overlay-store" ];
    };

    # Set the overlay store for all Nix commands in the container.
    # This is a single-user setup - no daemon needed, the overlay store
    # handles the lower (host) store connection directly.
    # Use mkForce to override the default "daemon" set by NixOS for containers.
    environment.variables.NIX_REMOTE = lib.mkForce
      "local-overlay://?lower-store=unix%3A%2F%2F${daemonSocket}%3Freal%3D${lowerStoreDir}&upper-layer=${upperDir}&check-mount=false";

    systemd.services.local-overlay-store-mount = {
      description = "OverlayFS mount for shared Nix store";
      wantedBy = [ "local-fs.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.util-linux ];
      script = ''
        mkdir -p ${upperDir} ${workDir}
        chown toor:wheel ${upperDir}

        # Nix in single-user mode calls chmod on its state dirs, which requires
        # ownership. Give toor ownership so both toor and root (via caps) can use nix.
        mkdir -p /nix/var/nix/profiles/per-user
        chown -R toor:wheel /nix/var/nix
        chmod 1777 /nix/var/nix/temproots

        mount --make-private /nix/store
        mount -t overlay overlay \
          -o lowerdir=${lowerStoreDir} \
          -o upperdir=${upperDir} \
          -o workdir=${workDir} \
          -o redirect_dir=on \
          /nix/store
      '';
    };

    systemd.tmpfiles.rules = [
      "d /nix/var/nix 0755 toor wheel -"
      "d /nix/var/nix/db 0755 toor wheel -"
      "d /nix/var/nix/profiles 0755 toor wheel -"
      "d /nix/var/nix/profiles/per-user 0755 toor wheel -"
      "d /nix/var/nix/temproots 1777 root root -"
    ];
  };
}
