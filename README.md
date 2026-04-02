# project-unknown

## Usage

```sh
nix run github:juspay/project-unknown#pu
```

```
Usage: pu <command>

Commands:
  create           Create instance, print ssh command
  destroy <name>   Destroy an instance
  list             List your instances
```

## Milestones

- [x] `pu` CLI for instance management (create/destroy/list)
- [x] Incus integration for LXC
- [x] SSH Certificate-based authentication
- [ ] Opencode contributing to [services-flake#563](https://github.com/juspay/services-flake/issues/563) via pu instances
- [ ] Multiple opencode agents in kolu, running pu instances to contribute to a large internal Juspay project in parallel

## Todo

- VM test
- Non-interactive auth one-liner example
- Custom hostname
- Rename "hypervisor" → "container and VM manager" for Incus
- Switch disko to btrfs
- Change Incus storage to `driver = "btrfs"` for instant CoW instance cloning
- Consider ZFS for VM block storage if RAM available; btrfs for LXC-only
- Add snapshot and fork commands to pu-manager (builds on btrfs)
- Shared /nix/store (local-overlay-store)
