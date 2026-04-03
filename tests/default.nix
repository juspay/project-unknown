{ pkgs, lib, self, ... }:
let
  node = self.node // { authMode = "none"; };

  base-container = self.nixosConfigurations.base-container;
  metadata = base-container.config.system.build.metadata;
  squashfs = base-container.config.system.build.squashfs;

  test-key = pkgs.runCommand "test-ssh-key" { buildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -t ed25519 -f $out/id_ed25519 -N ""
  '';
in
{
  name = "pu-create-list-destroy";

  node.specialArgs = { inherit node; };

  nodes.server = { pkgs, ... }: {
    imports = [
      ../incus.nix
      ../users.nix
      ../remote.nix
    ];

    virtualisation = {
      cores = 2;
      memorySize = 4096;
      diskSize = 20480;
    };

    services.openssh.settings.PermitRootLogin = "yes";

    environment.systemPackages = with pkgs; [ openssh ];

    users.users.${node.admin.name}.openssh.authorizedKeys.keyFiles = [ "${test-key}/id_ed25519.pub" ];
    users.users.pu.openssh.authorizedKeys.keyFiles = [ "${test-key}/id_ed25519.pub" ];

    system.stateVersion = "25.11";
  };

  testScript = ''
    server.wait_for_unit("incus.service")
    server.wait_for_unit("sshd.service")
    server.sleep(2)

    server.succeed("incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container")

    ssh_opts = "-o StrictHostKeyChecking=no -i ${test-key}/id_ed25519"
    admin_user = "${node.admin.name}"

    with subtest("create instance"):
      result = server.succeed(f"sudo -u {admin_user} ssh {ssh_opts} pu@localhost create base-container 2>&1")
      print(f"create result: {result}")
      assert "OK" in result, f"create failed: {result}"
      container_name = result.strip().split()[-1]

    with subtest("list instances"):
      list_result = server.succeed(f"sudo -u {admin_user} ssh {ssh_opts} pu@localhost list 2>&1")
      print(f"list result: {list_result}")
      assert container_name in list_result, f"container not in list: {list_result}"

    with subtest("destroy instance"):
      destroy_result = server.succeed(f"sudo -u {admin_user} ssh {ssh_opts} pu@localhost destroy {container_name} 2>&1")
      print(f"destroy result: {destroy_result}")

    with subtest("verify destroyed"):
      list_after = server.succeed(f"sudo -u {admin_user} ssh {ssh_opts} pu@localhost list 2>&1")
      print(f"list after destroy: {list_after}")
      assert container_name not in list_after, f"container still in list after destroy: {list_after}"
  '';
}
