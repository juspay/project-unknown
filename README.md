# idliv2

TODO: Add a long description of what the host does; Add local in-office IP

## Deploy

> [!TIP]
> To use a specific private key, **prefix** the deployment commands below with `NIX_SSHOPTS="-i <path-to-key>"`

```sh
HOST_NAME=$(nix eval --raw -f node.nix hostName)
TARGET=$(nix eval --raw -f node.nix sshTarget)
nixos-rebuild --flake .#$HOST_NAME --build-host $TARGET --target-host $TARGET --fast --use-remote-sudo switch
```
> [!NOTE]
> `--fast` is a hack to skip building `nixosConfigurations.<name>.config.system.build.nixos-rebuild`, which will fail on macOS (possibly on other non-x86_64-linux too)
>
> In the future, we can switch to`nixos-rebuild-ng`, that will come with first-class support for remote deployments

