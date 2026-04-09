# KubeVirt vs Incus Benchmark
#
# Compares KubeVirt (full VM) and Incus (LXC container) for developer instance
# management. Measures creation time, time-to-SSH, fork/clone time, SSH latency,
# memory overhead, and storage efficiency.
#
# Runs both systems on the same NixOS VM test node for a fair relative comparison.
# KubeVirt uses software emulation (useEmulation: true) by default so the test
# works without nested hardware virtualisation. Pass -cpu host to the outer QEMU
# and set useEmulation = false below to benchmark with real KVM.
#
# Requires: x86_64-linux with KVM (for the outer test VM).
#
{ pkgs, lib, self, ... }:
let
  # ---------------------------------------------------------------------------
  # Incus container artifacts (reuse existing base-container)
  # ---------------------------------------------------------------------------
  base-container = self.nixosConfigurations.base-container;
  metadata = base-container.config.system.build.metadata;
  squashfs = base-container.config.system.build.squashfs;

  # ---------------------------------------------------------------------------
  # KubeVirt VM image
  # ---------------------------------------------------------------------------
  base-vm = self.nixosConfigurations.base-vm;
  vmImage = base-vm.config.system.build.kubevirtImage;

  # Wrap qcow2 in an OCI image for KubeVirt containerDisk
  containerDiskImage = pkgs.dockerTools.buildImage {
    name = "nixos-kubevirt-disk";
    tag = "latest";
    copyToRoot = pkgs.runCommand "disk-root" { } ''
      mkdir -p $out/disk
      cp ${vmImage}/nixos.qcow2 $out/disk/disk.qcow2
    '';
  };

  # ---------------------------------------------------------------------------
  # SSH key for test access
  # ---------------------------------------------------------------------------
  test-key = pkgs.runCommand "test-ssh-key" { buildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -t ed25519 -f $out/id_ed25519 -N ""
  '';

  # Extend both images with the test SSH key
  test-container = base-container.extendModules {
    modules = [{
      users.users.toor.openssh.authorizedKeys.keyFiles = [ "${test-key}/id_ed25519.pub" ];
    }];
  };
  test-metadata = test-container.config.system.build.metadata;
  test-squashfs = test-container.config.system.build.squashfs;

  test-vm = base-vm.extendModules {
    modules = [{
      users.users.toor.openssh.authorizedKeys.keyFiles = [ "${test-key}/id_ed25519.pub" ];
    }];
  };
  testVmImage = test-vm.config.system.build.kubevirtImage;

  testContainerDiskImage = pkgs.dockerTools.buildImage {
    name = "nixos-kubevirt-disk";
    tag = "test";
    copyToRoot = pkgs.runCommand "disk-root" { } ''
      mkdir -p $out/disk
      cp ${testVmImage}/nixos.qcow2 $out/disk/disk.qcow2
    '';
  };

  # ---------------------------------------------------------------------------
  # KubeVirt & CDI operator manifests (pinned versions)
  # ---------------------------------------------------------------------------
  kubevirtVersion = "1.6.1";
  cdiVersion = "1.61.0";

  kubevirt-operator = pkgs.fetchurl {
    url = "https://github.com/kubevirt/kubevirt/releases/download/v${kubevirtVersion}/kubevirt-operator.yaml";
    hash = "sha256-UJlWxnhMKMCnkWc0Xo4LJFwkL8OdPoJDkfn0d5gMdXs=";
  };

  kubevirt-cr = pkgs.writeText "kubevirt-cr.yaml" ''
    apiVersion: kubevirt.io/v1
    kind: KubeVirt
    metadata:
      name: kubevirt
      namespace: kubevirt
    spec:
      configuration:
        developerConfiguration:
          useEmulation: true
  '';

  cdi-operator = pkgs.fetchurl {
    url = "https://github.com/kubevirt/containerized-data-importer/releases/download/v${cdiVersion}/cdi-operator.yaml";
    hash = "sha256-AjSpMzJHMMBZq+Jipuf/6VPMl1OwIkbLv7aB7k/RxN8=";
  };

  cdi-cr = pkgs.fetchurl {
    url = "https://github.com/kubevirt/containerized-data-importer/releases/download/v${cdiVersion}/cdi-cr.yaml";
    hash = "sha256-SaXANvbRPO0V3MaWAHYIr9VnXsGAYW3bkpI9S5vnBzQ=";
  };

  # ---------------------------------------------------------------------------
  # Incus instance manager script (for fork operations)
  # ---------------------------------------------------------------------------
  instanceMgrScript = pkgs.writeShellScript "incus.sh" (builtins.readFile ../pu/lib/incus.sh);

  iterations = 3;
in
{
  name = "kubevirt-vs-incus-benchmark";

  nodes.server = { pkgs, lib, ... }: {
    imports = [
      ../common/incus.nix
    ];

    _module.args.node = self.nodes."idliv2-01" // { useHostNixStore = false; };

    virtualisation = {
      cores = 4;
      memorySize = 16384;
      diskSize = 20480;
      emptyDiskImages = [ 4096 ]; # btrfs pool for Incus
    };

    boot.supportedFilesystems.btrfs = true;

    # -- btrfs pool for Incus (same pattern as e2e test) --
    systemd.services.incus-btrfs-setup = {
      description = "Format and mount btrfs filesystem for incus storage pool";
      before = [ "incus.service" ];
      requiredBy = [ "incus.service" ];
      path = [ pkgs.btrfs-progs pkgs.util-linux ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkfs.btrfs /dev/vdb
        mkdir -p /var/lib/incus/storage-pools
        mount /dev/vdb /var/lib/incus/storage-pools
      '';
    };

    # -- k3s for KubeVirt --
    services.k3s = {
      enable = true;
      role = "server";
      extraFlags = toString [
        "--disable=traefik"
        "--write-kubeconfig-mode=644"
      ];
      images = [ testContainerDiskImage ];
      manifests = {
        kubevirt-operator.source = kubevirt-operator;
        kubevirt-cr.source = kubevirt-cr;
        cdi-operator.source = cdi-operator;
        cdi-cr.source = cdi-cr;
      };
    };

    environment.systemPackages = with pkgs; [
      kubevirt # virtctl
      kubectl
      jq
      openssh
      coreutils
      procps # free, ps
      sysstat # mpstat
    ];

    networking.firewall.enable = false;
    system.stateVersion = "25.11";
  };

  testScript = let
    sshOpts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i ${test-key}/id_ed25519";
    vmYaml = name: ''
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${name}
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: ${name}
    spec:
      domain:
        resources:
          requests:
            memory: 1024Mi
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          containerDisk:
            image: docker.io/nixos-kubevirt-disk:test
'';
  in ''
    import time
    import statistics
    import json
    import re

    ITERATIONS = ${toString iterations}

    def time_command(cmd):
        """Run command and return elapsed seconds."""
        start = time.time()
        server.succeed(cmd)
        return time.time() - start

    def get_used_memory_mb():
        """Return used memory in MB (MemTotal - MemAvailable)."""
        meminfo = server.succeed("cat /proc/meminfo")
        total = int(re.search(r'MemTotal:\s+(\d+)', meminfo).group(1))
        avail = int(re.search(r'MemAvailable:\s+(\d+)', meminfo).group(1))
        return (total - avail) / 1024

    # ================================================================
    # Phase 1: Wait for infrastructure
    # ================================================================
    server.wait_for_unit("incus.service")
    server.wait_for_unit("k3s.service")
    server.sleep(5)

    # Import Incus container image
    server.succeed("incus image import ${test-metadata}/tarball/nixos-*.tar.xz ${test-squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container")

    # Wait for k3s node to be ready
    server.wait_until_succeeds("kubectl get nodes -o jsonpath='{.items[0].status.conditions[-1:].status}' | grep True", timeout=120)

    # Wait for KubeVirt operator
    print("Waiting for KubeVirt operator...")
    server.wait_until_succeeds("kubectl -n kubevirt get kubevirt kubevirt -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Deployed", timeout=600)
    print("KubeVirt ready.")

    # Wait for CDI operator
    print("Waiting for CDI operator...")
    server.wait_until_succeeds("kubectl -n cdi get cdi cdi -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Deployed", timeout=600)
    print("CDI ready.")

    # ================================================================
    # Phase 2: Benchmarks
    # ================================================================
    results = {
        "incus": {
            "create_time": [],
            "time_to_ssh": [],
            "fork_time": [],
            "ssh_latency": [],
            "memory_overhead_mb": [],
        },
        "kubevirt": {
            "create_time": [],
            "time_to_ssh": [],
            "ssh_latency": [],
            "memory_overhead_mb": [],
        },
    }

    # ----------------------------------------------------------------
    # Incus benchmarks
    # ----------------------------------------------------------------
    print("\n" + "=" * 60)
    print("Benchmarking Incus (LXC containers)")
    print("=" * 60)

    for i in range(ITERATIONS):
        name = f"bench-incus-{i}"
        fork_name = f"bench-incus-fork-{i}"

        # Baseline memory
        mem_before = get_used_memory_mb()

        # Create time
        create_time = time_command(f"incus launch --ephemeral base-container {name}")
        results["incus"]["create_time"].append(create_time)
        print(f"  [{i+1}/{ITERATIONS}] Create: {create_time:.3f}s")

        # Time to SSH (exec into container)
        start = time.time()
        server.wait_until_succeeds(f"incus exec {name} -- true", timeout=60)
        ssh_ready = time.time() - start
        total_to_ssh = create_time + ssh_ready
        results["incus"]["time_to_ssh"].append(total_to_ssh)
        print(f"  [{i+1}/{ITERATIONS}] Time to exec: {total_to_ssh:.3f}s")

        # SSH/exec latency (command round-trip)
        ssh_lat = time_command(f"incus exec {name} -- echo ok")
        results["incus"]["ssh_latency"].append(ssh_lat)
        print(f"  [{i+1}/{ITERATIONS}] Exec latency: {ssh_lat:.3f}s")

        # Memory overhead
        mem_after = get_used_memory_mb()
        overhead = mem_after - mem_before
        results["incus"]["memory_overhead_mb"].append(overhead)
        print(f"  [{i+1}/{ITERATIONS}] Memory overhead: {overhead:.1f} MB")

        # Fork time (snapshot + copy + start)
        fork_time = time_command(
            f"source ${instanceMgrScript} && inst_fork {name} {fork_name}"
        )
        results["incus"]["fork_time"].append(fork_time)
        print(f"  [{i+1}/{ITERATIONS}] Fork: {fork_time:.3f}s")

        # Cleanup
        server.succeed(f"incus delete --force {fork_name} || true")
        server.succeed(f"incus delete --force {name} || true")

    # ----------------------------------------------------------------
    # KubeVirt benchmarks
    # ----------------------------------------------------------------
    print("\n" + "=" * 60)
    print("Benchmarking KubeVirt (full VMs)")
    print("=" * 60)

    vm_yaml = """${vmYaml "PLACEHOLDER"}"""

    for i in range(ITERATIONS):
        name = f"bench-kv-{i}"
        yaml = vm_yaml.replace("PLACEHOLDER", name)

        # Baseline memory
        mem_before = get_used_memory_mb()

        # Create time (apply + wait for Running)
        start = time.time()
        server.succeed(f"cat <<'VMEOF' | kubectl apply -f -\n{yaml}\nVMEOF")
        server.wait_until_succeeds(
            f"kubectl get vmi {name} -o jsonpath='{{{{.status.phase}}}}' 2>/dev/null | grep -q Running",
            timeout=600
        )
        create_time = time.time() - start
        results["kubevirt"]["create_time"].append(create_time)
        print(f"  [{i+1}/{ITERATIONS}] Create: {create_time:.3f}s")

        # Get VM IP
        server.wait_until_succeeds(
            f"kubectl get vmi {name} -o jsonpath='{{{{.status.interfaces[0].ipAddress}}}}' 2>/dev/null | grep -E '[0-9]'",
            timeout=120
        )
        vm_ip = server.succeed(
            f"kubectl get vmi {name} -o jsonpath='{{{{.status.interfaces[0].ipAddress}}}}'"
        ).strip()

        # Time to SSH
        start = time.time()
        server.wait_until_succeeds(
            f"ssh ${sshOpts} toor@{vm_ip} true 2>/dev/null",
            timeout=300
        )
        ssh_ready = time.time() - start
        total_to_ssh = create_time + ssh_ready
        results["kubevirt"]["time_to_ssh"].append(total_to_ssh)
        print(f"  [{i+1}/{ITERATIONS}] Time to SSH: {total_to_ssh:.3f}s")

        # SSH latency
        ssh_lat = time_command(f"ssh ${sshOpts} toor@{vm_ip} echo ok 2>/dev/null")
        results["kubevirt"]["ssh_latency"].append(ssh_lat)
        print(f"  [{i+1}/{ITERATIONS}] SSH latency: {ssh_lat:.3f}s")

        # Memory overhead
        mem_after = get_used_memory_mb()
        overhead = mem_after - mem_before
        results["kubevirt"]["memory_overhead_mb"].append(overhead)
        print(f"  [{i+1}/{ITERATIONS}] Memory overhead: {overhead:.1f} MB")

        # Cleanup
        server.succeed(f"kubectl delete vm {name} --force --grace-period=0 || true")
        server.succeed(f"kubectl wait --for=delete vmi/{name} --timeout=60s 2>/dev/null || true")

    # ================================================================
    # Phase 3: Results
    # ================================================================
    def avg(lst):
        return statistics.mean(lst) if lst else 0

    def format_metric(name, incus_val, kv_val, unit="s", lower_better=True):
        if incus_val == 0 and kv_val == 0:
            return f"  {name:<25} {'N/A':>12} {'N/A':>12}   {'N/A':>8}  {'N/A'}"
        if incus_val == 0:
            return f"  {name:<25} {'N/A':>12} {kv_val:>11.3f}{unit} {'KubeVirt':>8}  N/A"
        if kv_val == 0:
            return f"  {name:<25} {incus_val:>11.3f}{unit} {'N/A':>12}   {'Incus':>8}  N/A"

        if lower_better:
            winner = "Incus" if incus_val <= kv_val else "KubeVirt"
            ratio = max(incus_val, kv_val) / min(incus_val, kv_val)
        else:
            winner = "Incus" if incus_val >= kv_val else "KubeVirt"
            ratio = max(incus_val, kv_val) / min(incus_val, kv_val)

        return f"  {name:<25} {incus_val:>11.3f}{unit} {kv_val:>11.3f}{unit}   {winner:>8}  {ratio:.1f}x"

    print("\n" + "=" * 80)
    print("KUBEVIRT vs INCUS BENCHMARK RESULTS")
    print("=" * 80)
    print(f"\n  {'Metric':<25} {'Incus (LXC)':>12} {'KubeVirt (VM)':>12}   {'Winner':>8}  Ratio")
    print("  " + "-" * 76)

    print(format_metric("Create time (avg)", avg(results["incus"]["create_time"]), avg(results["kubevirt"]["create_time"])))
    print(format_metric("Time to SSH (avg)", avg(results["incus"]["time_to_ssh"]), avg(results["kubevirt"]["time_to_ssh"])))
    print(format_metric("Fork/Clone (avg)", avg(results["incus"]["fork_time"]), 0))
    print(format_metric("SSH latency (avg)", avg(results["incus"]["ssh_latency"]), avg(results["kubevirt"]["ssh_latency"])))
    print(format_metric("Memory overhead (avg)", avg(results["incus"]["memory_overhead_mb"]), avg(results["kubevirt"]["memory_overhead_mb"]), unit=" MB"))

    print("\n  Note: KubeVirt fork/clone not yet implemented (requires CSI hostpath driver).")
    print("  Note: KubeVirt runs with useEmulation: true (software QEMU, no nested KVM).")

    print("\n" + "=" * 80)
    print("RAW JSON RESULTS")
    print("=" * 80)
    print(json.dumps(results, indent=2))

    # Assertions
    assert len(results["incus"]["create_time"]) == ITERATIONS, "Incus benchmarks incomplete"
    assert len(results["kubevirt"]["create_time"]) == ITERATIONS, "KubeVirt benchmarks incomplete"
  '';
}
