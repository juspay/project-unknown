# Incus Storage Backend Benchmark (Single-Node)
#
# Compares btrfs, LVM+ext4, and ZFS for container lifecycle operations.
# Runs in QEMU VM with 2 cores, 4GB RAM, 2GB virtual disk per pool.
#
# Lifecycle Operations:
#   Create (init, no start): btrfs > zfs (4.9x) > lvm (10.2x)
#   Delete: btrfs > zfs (3.1x) > lvm (6.1x)
#   Start/stop: btrfs > zfs (1.1x) > lvm (1.2x)
#     Currently dominated by incus daemon + container init on local pools, so
#     storage barely contributes. Kept as a baseline — it becomes meaningful
#     once networked drivers (Ceph RBD map/unmap, LINSTOR/DRBD promote/demote)
#     are added, where start/stop is bound by network round-trips.
#   Snapshot: btrfs > zfs (1.3x) > lvm (4.2x)
#   Snapshot copy (same-pool, CoW-favorable): btrfs > zfs (3.8x) > lvm (6.2x)
#
{ pkgs, lib, self, ... }:
let
  base-container = self.nixosConfigurations.base-container;
  metadata = base-container.config.system.build.metadata;
  squashfs = base-container.config.system.build.squashfs;

  iterations = 3;
in
{
  name = "incus-storage-benchmark";

  nodes.server = { pkgs, ... }: {
    imports = [
      (import ../clanServices/incus/standalone.nix { useHostNixStore = false; })
    ];

    virtualisation.incus.preseed.storage_pools = lib.mkForce [ ]; # We setup the pools in the testScript below

    _module.args.node = self.nodes."idliv2-01";

    virtualisation = {
      cores = 2;
      memorySize = 4096;
      emptyDiskImages = [ 2048 2048 2048 ];
    };

    networking.hostId = "12345678";

    boot.supportedFilesystems = {
      btrfs = true;
      zfs = true;
    };

    services.lvm = {
      boot.thin.enable = true;
      dmeventd.enable = true;
    };

    environment.systemPackages = with pkgs; [
      hyperfine
      zfs
    ];

    system.stateVersion = "25.11";
  };

  testScript = ''
    import json
    import os

    server.wait_for_unit("incus.service")
    server.wait_for_unit("incus-preseed.service")

    server.succeed("incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container")

    with subtest("setup storage pools"):
        server.succeed("incus storage create btrfs btrfs source=/dev/vdb")
        server.succeed("incus storage create lvm lvm source=/dev/vdc")
        server.succeed("zpool create zfs /dev/vdd")
        server.succeed("incus storage create zfs zfs source=zfs")

    with subtest("benchmark create"):
        server.succeed(
            "hyperfine --runs ${toString iterations} --export-json bench-create.json"
            " --parameter-list pool btrfs,lvm,zfs"
            " --setup 'incus init base-container c -s {pool}'"
            " --prepare 'incus delete c'"
            " --cleanup 'incus delete c'"
            " 'incus init base-container c -s {pool}'"
        )

    with subtest("benchmark delete"):
        server.succeed(
            "hyperfine --runs ${toString iterations} --export-json bench-delete.json"
            " --parameter-list pool btrfs,lvm,zfs"
            " --prepare 'incus launch base-container d -s {pool}; incus stop d --force'"
            " 'incus delete d --force'"
        )

    with subtest("benchmark start-stop"):
        server.succeed(
            "hyperfine --runs ${toString iterations} --export-json bench-start-stop.json"
            " --parameter-list pool btrfs,lvm,zfs"
            " --setup 'incus launch base-container pwr-test -s {pool}; incus stop pwr-test --force'"
            " --cleanup 'incus delete pwr-test --force'"
            " 'incus start pwr-test; incus stop pwr-test --force'"
        )

    with subtest("benchmark snapshot"):
        server.succeed(
            "hyperfine --runs ${toString iterations} --export-json bench-snapshot.json"
            " --parameter-list pool btrfs,lvm,zfs"
            " --setup 'incus launch base-container s -s {pool}; incus snapshot create s snap0'"
            " --prepare 'incus snapshot delete s snap0'"
            " --cleanup 'incus delete s --force'" 
            " 'incus snapshot create s snap0'"
        )

    with subtest("benchmark snapshot copy"):
        server.succeed(
            "hyperfine --runs ${toString iterations} --export-json bench-snapshot-copy.json"
            " --parameter-list pool btrfs,lvm,zfs"
            " --setup 'incus launch base-container sc -s {pool}; incus snapshot create sc snap0; incus copy sc/snap0 sc-copy -s {pool}'"
            " --prepare 'incus delete sc-copy --force'"
            " --cleanup 'incus delete sc-copy --force; incus delete sc --force'" 
            " 'incus copy sc/snap0 sc-copy -s {pool}'"
        )


    print("\n" + "="*60)
    print("BENCHMARK RESULTS (mean, seconds)")
    print("="*60)
    
    for bench_name in [ "create", "delete", "start-stop", "snapshot", "snapshot-copy" ]:
        server.copy_from_vm(f"bench-{bench_name}.json")
        with open(f"{os.environ['out']}/bench-{bench_name}.json") as f:
            results = json.load(f)["results"]
        ranked = sorted(results, key=lambda r: r["mean"])
        best = ranked[0]["mean"]
        
        parts = []
        for i, r in enumerate(ranked):
            pool_name = r.get("parameters", {}).get("pool", r["command"])
            
            if i == 0:
                parts.append(f"{pool_name} ({r['mean']:.3f}s)")
            else:
                parts.append(f"{pool_name} ({r['mean']:.3f}s, {r['mean']/best:.1f}x)")
                
        print(f"  {bench_name}: {' > '.join(parts)}")
  '';
}
