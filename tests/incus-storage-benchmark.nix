# Incus Storage Backend Benchmark (Single-Node)
#
# Compares btrfs, LVM+ext4, and ZFS for container lifecycle operations.
# Runs in QEMU VM with 4 cores, 12GB RAM, 4GB virtual disks per pool.
#
# Lifecycle Operations:
#   Create:        btrfs > ZFS (1.8x) > LVM (3.5x)
#   Destroy:       btrfs > ZFS (2.5x) > LVM (6.5x)
#   Snapshot:      btrfs = ZFS > LVM (4x)
#   Snapshot copy: btrfs > ZFS (4x) > LVM (15x)
#
# Why btrfs wins lifecycle:
#   CoW (copy-on-write) + B-tree: create/snapshot/delete just update metadata.
#
# Why ZFS close second:
#   Also CoW, but more overhead per operation.
#
# Why LVM slowest:
#   No CoW. Must allocate/copy actual blocks for every operation.
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
      ../incus.nix
    ];

    _module.args.node = self.node;

    virtualisation = {
      cores = 4;
      memorySize = 12288;
      diskSize = 20480;
      emptyDiskImages = [ 4096 4096 4096 ];
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
      coreutils
      parted
      zfs
    ];

    system.stateVersion = "25.11";
  };

  testScript = ''
    import time
    import statistics
    import json

    def time_command(cmd):
        start = time.time()
        server.succeed(cmd)
        return time.time() - start

    server.wait_for_unit("incus.service")
    server.sleep(2)

    server.succeed("incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container")

    with subtest("setup btrfs storage pool"):
        server.succeed("incus storage create btrfs-pool btrfs source=/dev/vdb")

    with subtest("setup lvm storage pool"):
        server.succeed("incus storage create lvm-pool lvm source=/dev/vdc")

    with subtest("setup zfs storage pool"):
        server.succeed("zpool create zfs-pool /dev/vdd")
        server.succeed("incus storage create zfs-pool zfs source=zfs-pool")

    results: dict[str, dict[str, list[float]]] = {
        "btrfs": {
            "create": [],
            "start": [],
            "stop": [],
            "destroy": [],
            "snapshot_create": [],
            "snapshot_copy": [],
        },
        "lvm": {
            "create": [],
            "start": [],
            "stop": [],
            "destroy": [],
            "snapshot_create": [],
            "snapshot_copy": [],
        },
        "zfs": {
            "create": [],
            "start": [],
            "stop": [],
            "destroy": [],
            "snapshot_create": [],
            "snapshot_copy": [],
        },
    }

    for pool_name, result_key in [("btrfs-pool", "btrfs"), ("lvm-pool", "lvm"), ("zfs-pool", "zfs")]:
        print("\n" + "="*60)
        print(f"Benchmarking {pool_name} ({result_key})")
        print("="*60)

        for i in range(${toString iterations}):
            container_name = f"bench-{result_key}-{i}"

            create_time = time_command(f"incus launch base-container {container_name} -s {pool_name}")
            results[result_key]["create"].append(create_time)
            print(f"  [{i+1}/${toString iterations}] Create: {create_time:.3f}s")

            server.succeed(f"incus stop {container_name} --force")
            start_time = time_command(f"incus start {container_name}")
            results[result_key]["start"].append(start_time)
            print(f"  [{i+1}/${toString iterations}] Start: {start_time:.3f}s")

            snap_name = f"snap{i}"
            snapshot_time = time_command(f"incus snapshot create {container_name} {snap_name}")
            results[result_key]["snapshot_create"].append(snapshot_time)
            print(f"  [{i+1}/${toString iterations}] Snapshot create: {snapshot_time:.3f}s")

            restore_container = f"{container_name}-from-snap"
            copy_time = time_command(f"incus copy {container_name}/{snap_name} {restore_container} -s {pool_name}")
            results[result_key]["snapshot_copy"].append(copy_time)
            print(f"  [{i+1}/${toString iterations}] Snapshot copy: {copy_time:.3f}s")

            server.succeed(f"incus delete {restore_container} --force")

            stop_time = time_command(f"incus stop {container_name} --force")
            results[result_key]["stop"].append(stop_time)
            print(f"  [{i+1}/${toString iterations}] Stop: {stop_time:.3f}s")

            destroy_time = time_command(f"incus delete {container_name} --force")
            results[result_key]["destroy"].append(destroy_time)
            print(f"  [{i+1}/${toString iterations}] Destroy: {destroy_time:.3f}s")

    print("\n" + "="*70)
    print("BENCHMARK RESULTS")
    print("="*70)

    def avg(lst):
        return statistics.mean(lst) if lst else 0

    def format_ranked(name, btrfs_val, lvm_val, zfs_val, lower_better=False):
        vals = {"btrfs": btrfs_val, "lvm": lvm_val, "zfs": zfs_val}
        non_zero = {k: v for k, v in vals.items() if v > 0}

        if len(non_zero) == 0:
            return f"  {name}: N/A"

        if lower_better:
            sorted_fs = sorted(non_zero.items(), key=lambda x: x[1])
        else:
            sorted_fs = sorted(non_zero.items(), key=lambda x: x[1], reverse=True)

        best_name, best_val = sorted_fs[0]

        parts = []
        i = 0
        while i < len(sorted_fs):
            current_name, current_val = sorted_fs[i]
            tied = [current_name]
            j = i + 1
            while j < len(sorted_fs):
                _, next_val = sorted_fs[j]
                if abs(current_val - next_val) / max(current_val, next_val) < 0.05:
                    tied.append(sorted_fs[j][0])
                    j += 1
                else:
                    break

            if len(tied) > 1:
                parts.append(" = ".join(tied))
            else:
                if i == 0:
                    parts.append(current_name)
                else:
                    ratio = current_val / best_val
                    if lower_better:
                        parts.append(f"{current_name} ({ratio:.1f}x)")
                    else:
                        parts.append(f"{current_name} ({1/ratio:.1f}x)")
            i = j

        return f"  {name}: {' > '.join(parts)}"

    print("\nLifecycle Operations:")
    print(format_ranked("Create", avg(results["btrfs"]["create"]), avg(results["lvm"]["create"]), avg(results["zfs"]["create"]), lower_better=True))
    print(format_ranked("Destroy", avg(results["btrfs"]["destroy"]), avg(results["lvm"]["destroy"]), avg(results["zfs"]["destroy"]), lower_better=True))
    print(format_ranked("Snapshot", avg(results["btrfs"]["snapshot_create"]), avg(results["lvm"]["snapshot_create"]), avg(results["zfs"]["snapshot_create"]), lower_better=True))
    print(format_ranked("Snapshot copy", avg(results["btrfs"]["snapshot_copy"]), avg(results["lvm"]["snapshot_copy"]), avg(results["zfs"]["snapshot_copy"]), lower_better=True))

    print("\n" + "="*70)
    print("RAW JSON RESULTS")
    print("="*70)
    print(json.dumps(results, indent=2))

    assert len(results["btrfs"]["create"]) == ${toString iterations}, "Btrfs tests incomplete"
    assert len(results["lvm"]["create"]) == ${toString iterations}, "LVM tests incomplete"
    assert len(results["zfs"]["create"]) == ${toString iterations}, "ZFS tests incomplete"
  '';
}
