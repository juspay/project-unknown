{ pkgs, lib, self, ... }:
let
  testNode = self.nodes."idliv2-01" // {
    useSSHCA = false;
    useHostNixStore = false;
  };

  bootstrapNode = testNode // {
    hostName = "server1";
    incus.role = "bootstrap";
  };

  memberNode = name: testNode // {
    hostName = name;
    incus.role = "member";
  };

  test-key = pkgs.runCommand "test-ssh-key" { buildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -t ed25519 -f $out/id_ed25519 -N ""
  '';

  test-container = self.nixosConfigurations.base-container.extendModules {
    modules = [{
      users.users.toor.openssh.authorizedKeys.keyFiles = [ "${test-key}/id_ed25519.pub" ];
    }];
  };

  pu = pkgs.writeShellApplication {
    name = "pu";
    runtimeInputs = with pkgs; [ openssh gawk ];
    text = self.lib.mkPUClientScript (testNode.useSSHCA or false);
  };

  metadata = test-container.config.system.build.metadata;
  squashfs = test-container.config.system.build.squashfs;

  mkIncusServer = nodeConfig: { pkgs, lib, ... }: {
    imports = [
      ../common/incus.nix
      ../nodes/idliv2-01/openssh.nix
    ];

    _module.args.node = nodeConfig;

    virtualisation.incus.preseed.storage_pools = lib.mkIf (nodeConfig.incus.role or "standalone" != "member") (lib.mkForce [
      {
        name = "default";
        driver = "btrfs";
        config.source = "/var/lib/incus/storage-pools";
      }
    ]);

    networking.firewall.allowedTCPPorts = [ 8443 ];

    virtualisation.vlans = [ 1 ];
    virtualisation.emptyDiskImages = [ 2048 ];
    boot.supportedFilesystems.btrfs = true;

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

    users.users.pu = {
      isSystemUser = true;
      group = "pu";
      shell = lib.getExe pkgs.bash;
      extraGroups = [ "incus-admin" ];
      openssh.authorizedKeys.keyFiles = [ "${test-key}/id_ed25519.pub" ];
    };
    users.groups.pu = {};

    system.stateVersion = "25.11";
  };
in
{
  name = "e2e-cluster";

  nodes = {
    server1 = mkIncusServer bootstrapNode;
    server2 = mkIncusServer (memberNode "server2");
    server3 = mkIncusServer (memberNode "server3");

    client = { pkgs, ... }: {
      virtualisation.vlans = [ 1 ];

      environment.systemPackages = [ pu pkgs.openssh pkgs.iputils ];

      system.activationScripts.setupTestSSHKey = {
        text = ''
          mkdir -p /root/.ssh
          cp -r ${test-key}/id_ed25519 /root/.ssh/id_ed25519
          cp ${test-key}/id_ed25519.pub /root/.ssh/id_ed25519.pub
          chmod 600 /root/.ssh/id_ed25519
          chmod 644 /root/.ssh/id_ed25519.pub
        '';
      };

      system.stateVersion = "25.11";
    };
  };

  testScript = ''
    import json
    import re

    def get_instance_location(server, instance_name):
        result = server.succeed(f"incus list --format=json {instance_name}")
        data = json.loads(result)
        if data:
            return data[0].get("location", "unknown")
        return "not_found"

    def join_cluster(server, hostname, token):
        # server_name and cluster_address are omitted: fillClusterConfig decodes
        # both from the join token itself (token encodes member name and cluster addresses).
        server.succeed(f"""incus admin init --preseed <<'EOF'
cluster:
  enabled: true
  server_address: {hostname}:8443
  cluster_token: {token}
  member_config:
    - entity: storage-pool
      name: default
      key: source
      value: /var/lib/incus/storage-pools
EOF""")

    def extract_instance_name(output, context):
        match = re.search(r'\bOK\s+(pu-[a-f0-9]+)', output)
        if match:
            return match.group(1)
        for line in output.replace('\r', '\n').splitlines():
            line = line.strip()
            if re.match(r'^pu-[a-f0-9]+$', line):
                return line
        raise AssertionError(f"{context}: no instance name in output:\n{output}")

    start_all()

    cluster_members = ["server1", "server2", "server3"]

    for srv in [server1, server2, server3]:
        srv.wait_for_unit("incus.service")
        srv.wait_for_unit("sshd.service")
        srv.wait_until_succeeds("incus list")

    server1.wait_for_unit("incus-preseed.service")

    with subtest("verify network connectivity via VLAN"):
        server1.succeed("ping -c 1 server2")
        server1.succeed("ping -c 1 server3")
        server2.succeed("ping -c 1 server1")
        server3.succeed("ping -c 1 server1")

    with subtest("bootstrap cluster on server1"):
        server1.succeed("incus config set core.https_address server1:8443")
        server1.succeed("incus cluster enable server1")
        server1.succeed("incus cluster list")

    with subtest("generate join tokens"):
        token2 = server1.succeed("incus cluster add --quiet server2").strip()
        token3 = server1.succeed("incus cluster add --quiet server3").strip()

    with subtest("join server2 to cluster"):
        join_cluster(server2, "server2", token2)

    with subtest("join server3 to cluster"):
        join_cluster(server3, "server3", token3)

    with subtest("verify cluster formation"):
        cluster_list = server1.succeed("incus cluster list --format=json")
        members = json.loads(cluster_list)
        member_names = {m["server_name"] for m in members}
        assert member_names == {"server1", "server2", "server3"}, f"Expected 3 cluster members, got: {member_names}"
        for m in members:
            assert m["status"] == "Online", f"Member {m['server_name']} is not online: {m['status']}"

    with subtest("import container image on server1"):
        server1.succeed("incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container")
        server1.wait_until_succeeds("incus image list | grep base-container")

    with subtest("verify image available cluster-wide"):
        server2.succeed("incus image list --format=json | grep base-container")
        server3.succeed("incus image list --format=json | grep base-container")

    with subtest("create instance"):
        result = client.succeed("PU_HOST=server1 pu create 2>&1")
        print(f"create result: {result}")
        instance_name = extract_instance_name(result, "create")

    with subtest("check instance location"):
        location = get_instance_location(server1, instance_name)
        print(f"instance {instance_name} is on {location}")

    with subtest("list instances"):
        list_result = client.succeed("PU_HOST=server1 pu list 2>&1")
        print(f"list result: {list_result}")
        assert instance_name in list_result, f"instance not in list: {list_result}"

    with subtest("connect to instance"):
        connect_result = client.succeed(f"ssh -F /root/.pu-state/{instance_name}/ssh_config {instance_name} hostname 2>&1")
        print(f"connect result: {connect_result}")
        assert instance_name in connect_result, f"hostname mismatch: expected {instance_name}, got: {connect_result}"

    with subtest("fork instance (should land on different node)"):
        _, fork_result = client.execute(f"PU_HOST=server1 pu fork {instance_name} 2>&1")
        print(f"fork output: {repr(fork_result)}")
        fork_name = extract_instance_name(fork_result, "fork")

    with subtest("verify cross-node fork"):
        instance_location = get_instance_location(server1, instance_name)
        fork_location = get_instance_location(server1, fork_name)
        print(f"instance {instance_name} on {instance_location}")
        print(f"fork {fork_name} on {fork_location}")
        assert instance_location != fork_location, \
            f"Fork did not cross nodes: instance on {instance_location}, fork on {fork_location}"

    with subtest("destroy fork"):
        destroy_status, destroy_result = client.execute(f"PU_HOST=server1 pu destroy {fork_name} 2>&1")
        print(f"destroy fork status: {destroy_status}, output: {destroy_result}")

    with subtest("destroy instance"):
        destroy_result = client.succeed(f"PU_HOST=server1 pu destroy {instance_name} 2>&1")
        print(f"destroy result: {destroy_result}")
  '';
}
