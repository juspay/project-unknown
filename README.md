# project-unknown

## Usage

```sh
nix run github:juspay/project-unknown
```

```
Usage: pu <command>

Commands:
  create [--name <name>]           Create instance and print a pu connect command
  fork <source> [--name <name>]    Fork an existing instance and print a pu connect command
  connect <name> [ssh args ...]    Connect to an instance via ssh; use -- before a remote command
  destroy <name>                   Destroy an instance
  list                             List your instances
```

## Limitations

- No direct cross-instance networking across cluster members; access goes through the manager for simplicity.

## Incus Reset

If the Incus cluster state gets wedged and you want to rebuild it from scratch:

1. On each machine, stop and cleanup incus state:

```sh
incus list -c n --format csv | xargs -r -n1 incus delete -f
systemctl stop incus.socket && systemctl stop incus.service && btrfs subvolume delete --recursive /var/lib/incus/storage-pools/default/ && rm -rf /var/lib/incus
ip link set incusbr0 down
ip link delete incusbr0 type bridge
```

2. Re-deploy the machines:

```sh
clan machines update
```

3. Re-join the cluster:

```sh
nix run .#incus-cluster-join
```
