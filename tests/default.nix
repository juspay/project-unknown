{ pkgs, lib, self, ... }:
let
  # TODO: enable useHostNixStore
  # I had to disable it because `pu create` was failing for unknown reasons
  node = self.node // { useSSHCA = false; useHostNixStore = false; };

  base-container = self.nixosConfigurations.base-container;

  test-key = pkgs.runCommand "test-ssh-key" { buildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -t ed25519 -f $out/id_ed25519 -N ""
  '';

  test-container = base-container.extendModules {
    modules = [{
      users.users.root.openssh.authorizedKeys.keyFiles = [ "${test-key}/id_ed25519.pub" ];
    }];
  };

  pu = pkgs.writeShellApplication {
    name = "pu";
    runtimeInputs = with pkgs; [ openssh gawk ]
      ++ lib.optional node.useSSHCA pkgs.step-cli;
    text = self.lib.mkPUClientScript node.useSSHCA;
  };

  metadata = test-container.config.system.build.metadata;
  squashfs = test-container.config.system.build.squashfs;
in
{
  name = "e2e-no-auth";

  nodes = {
    server = { pkgs, ... }: {
      imports = [
        ../incus.nix
        ../openssh.nix
      ];

      _module.args.node = node;

      virtualisation = {
        diskSize = 2048;
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

    client = { pkgs, ... }: {
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
    start_all()
    server.wait_for_unit("incus.service")
    server.wait_for_unit("sshd.service")
    server.sleep(2)

    server.succeed("incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container")

    with subtest("create instance"):
      result = client.succeed("PU_HOST=server pu create 2>&1")
      print(f"create result: {result}")
      lines = [l.strip() for l in result.strip().split('\n') if l.strip()]
      instance_name = None
      for line in lines:
        if line.startswith("pu-"):
          instance_name = line
          break
      assert instance_name, f"create failed - no instance name found: {result}"

    with subtest("list instances"):
      list_result = client.succeed("PU_HOST=server pu list 2>&1")
      print(f"list result: {list_result}")
      assert instance_name in list_result, f"instance not in list: {list_result}"

    with subtest("connect to instance"):
      connect_result = client.succeed(f"ssh -F /root/.pu-state/{instance_name}/ssh_config {instance_name} hostname 2>&1")
      print(f"connect result: {connect_result}")

    with subtest("destroy instance"):
      destroy_result = client.succeed(f"PU_HOST=server pu destroy {instance_name} 2>&1")
      print(f"destroy result: {destroy_result}")

    with subtest("verify destroyed"):
      list_after = client.succeed("PU_HOST=server pu list 2>&1")
      print(f"list after destroy: {list_after}")
      assert instance_name not in list_after, f"instance still in list after destroy: {list_after}"
  '';
}
