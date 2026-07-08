{
  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = eachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.writeShellApplication {
            name = "xyne-boxes";
            runtimeInputs = with pkgs; [
              openssh
              step-cli
            ];
            text = builtins.readFile ./pu/pu-client.sh;
            meta = {
              description = "CLI for xyne-boxes";
              mainProgram = "xyne-boxes";
            };
            derivationArgs.postCheck = ''
              # Backwards compatibility for users with the old CLI name.
              ln -s xyne-boxes "$out/bin/pu"
            '';
          };
        });
    };
}
