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
in
{
  name = "local-overlay-store";

  nodes.server = { pkgs, ... }: {
    imports = [ ../incus.nix ];
    _module.args.node = self.node;
    virtualisation.diskSize = 2048; # default 1024 not enough for importing base-container

    environment.systemPackages = [ hostOnlyPackage ];
  };

  testScript = ''
    # ${containerToplevel}
    server.wait_for_unit("incus.service")
    server.wait_for_unit("nix-daemon.socket")
    server.sleep(2)

    server.succeed("incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container")

    server.succeed("incus launch base-container test-overlay -p default -p local-overlay-store")

    server.wait_until_succeeds("incus exec test-overlay -- ${systemPath}/bin/systemctl is-active local-overlay-store-mount")

    with subtest("container can run host-only package"):
      result = server.succeed("incus exec test-overlay -- ${hostOnlyPackage}/bin/host-only-marker")
      assert "built on host" in result, f"Host package not working: {result}"

    with subtest("nix daemon recognizes host-only package"):
      server.succeed("incus exec test-overlay -- ${nixPackage}/bin/nix-store --query --hash ${hostOnlyPackage}")
  '';
}
