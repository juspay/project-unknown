{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.inputs.darwin.follows = "";
    agenix.inputs.home-manager.follows = "";
  };
  outputs = inputs@{ self, nixpkgs, disko, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];

      flake = {
        node = import ./node.nix;

        nixosConfigurations = {
          ${self.node.hostName} = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hardware
              ./openssh.nix
              ./users.nix
              ./incus.nix
              ./secrets
              inputs.agenix.nixosModules.default
              disko.nixosModules.disko
            ] ++ nixpkgs.lib.optional (self.node.useSSHCA or true) ./step-ca.nix
            ++ [
              ({ node, ... }: {
                nix.settings = {
                  max-jobs = "auto";
                  experimental-features = "nix-command flakes";
                  trusted-users = [ "root" node.admin.name ];
                };
                services.tailscale.enable = true;
              })
            ];
            specialArgs = {
              node = self.node;
            };
          };

          base-container = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ ./containers/base ];
            specialArgs = {
              node = self.node;
            };
          };
        };

        lib.mkPUClientScript = useSSHCA:
          # TODO: PU_ADMIN is not an appropriate name for the env var
          ''
            PU_HOST="''${PU_HOST:-${self.node.hostName}.tail12b27.ts.net}"
            PU_ADMIN="root"
          '' + (if useSSHCA then ''
            export STEP_FINGERPRINT="a1a94de010ff8b2996b4ba4634df5f54db3761dfd92e5974631d0fdae932009b"
            export STEP_CA_URL="https://''${PU_HOST}:8443"
            export STEP_PROVISIONER="me@shivaraj-bh.in"
            export PU_USE_SSH_CA=true
          '' else ''
            export PU_USE_SSH_CA=false
          '') + ''
            ${builtins.readFile ./pu/lib/auth-client.sh}
            ${builtins.readFile ./pu/pu-client.sh}
          '';
      };

      perSystem = { pkgs, lib, ... }:
      {
        formatter = pkgs.nixpkgs-fmt;

        checks = lib.optionalAttrs pkgs.stdenv.isLinux (
          {
            pu-test = pkgs.testers.runNixOSTest (import ./tests { inherit pkgs lib self; });
            incus-storage-benchmark = pkgs.testers.runNixOSTest (import ./tests/incus-storage-benchmark.nix { inherit pkgs lib self; });
          }
          // lib.optionalAttrs self.node.useHostNixStore {
            local-overlay-store = pkgs.testers.runNixOSTest (import ./tests/local-overlay-store.nix { inherit pkgs lib self; });
          }
        );

        packages.default = pkgs.writeShellApplication {
          name = "pu";
          runtimeInputs = with pkgs; [ openssh gawk ]
            ++ lib.optional self.node.useSSHCA pkgs.step-cli;
          text = self.lib.mkPUClientScript self.node.useSSHCA;
        };


        apps.incus-import-container =
          let
            container = self.nixosConfigurations.base-container;
            metadata = container.config.system.build.metadata;
            squashfs = container.config.system.build.squashfs;
            script = pkgs.writeShellApplication {
              name = "incus-import-container";
              text = ''
                incus image delete base-container 2>/dev/null || true
                echo "Importing container image..."
                incus image import ${metadata}/tarball/nixos-*.tar.xz ${squashfs}/nixos-lxc-image-x86_64-linux.squashfs --alias base-container
                echo "Done. Launch with: incus launch base-container <name>"
              '';
            };
          in
          lib.optionalAttrs pkgs.stdenv.isLinux {
            type = "app";
            program = lib.getExe script;
          };
      };
    };
}
