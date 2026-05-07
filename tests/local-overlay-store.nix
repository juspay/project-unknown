{ pkgs, lib, self, ... }:
let
  base-container = self.nixosConfigurations.base-container;
  metadata = base-container.config.system.build.metadata;
  squashfs = base-container.config.system.build.squashfs;
  systemPath = builtins.toString base-container.config.system.path;
  nixPackage = base-container.config.nix.package;
  # Reference toplevel so the container's full system closure is in the test sandbox.
  # Without this, the overlay mount on /nix/store would hide the container's own paths
  # (like nix.conf) since they wouldn't be available via the host's 9p-shared store.
  containerToplevel = base-container.config.system.build.toplevel;

  hostOnlyPackage = pkgs.runCommand "host-only-marker" { } ''
    mkdir -p $out/bin
    echo '#!/bin/sh' > $out/bin/host-only-marker
    echo 'echo "built on host"' >> $out/bin/host-only-marker
    chmod +x $out/bin/host-only-marker
  '';

  instanceMgrScript = pkgs.writeShellScript "incus.sh" (builtins.readFile ../pu/lib/incus.sh);
in
{
  name = "local-overlay-store";

  nodes.server = { pkgs, lib, ... }: {
    imports = [ ../clanServices/incus/standalone.nix ];
    virtualisation.diskSize = 2048; # default 1024 not enough for importing base-container

    # This test doesn't need btrfs — override to dir to avoid needing a btrfs-formatted disk
    virtualisation.incus.preseed.storage_pools = lib.mkForce [
      {
        name = "default";
        driver = "dir";
        config.source = "/var/lib/incus/storage-pools/default";
      }
    ];

    environment.systemPackages = [ hostOnlyPackage pkgs.jq ];
  };

  testScript = ''
    # ${containerToplevel}
    server.wait_for_unit("incus.service")
    server.wait_for_unit("nix-daemon.socket")
    server.sleep(2)

    server.succeed("incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container")

    server.succeed("source ${instanceMgrScript} && inst_create base-container test-overlay test-owner")

    server.wait_until_succeeds("incus exec test-overlay -- ${systemPath}/bin/systemctl is-active local-overlay-store-mount")

    with subtest("container can run host-only package"):
      result = server.succeed("incus exec test-overlay -- ${hostOnlyPackage}/bin/host-only-marker")
      assert "built on host" in result, f"Host package not working: {result}"

    with subtest("nix log directories are writable for toor"):
      server.succeed("incus exec test-overlay -- su -l toor -c 'test -w /nix/var/log/nix && test -w /nix/var/log/nix/drvs'")

    with subtest("nix can query host packages through overlay"):
      server.succeed("incus exec test-overlay -- su -l toor -c '${nixPackage}/bin/nix-store --query --hash ${hostOnlyPackage}'")
  '';
}
