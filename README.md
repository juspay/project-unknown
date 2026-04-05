# project-unknown

## Usage

```sh
nix run github:juspay/project-unknown
```

```
Usage: pu <command>

Commands:
  create [--name <name>]  Create instance, print ssh command
  destroy <name>          Destroy an instance
  list                    List your instances
```

## Milestones

- [x] `pu` CLI for instance management (create/destroy/list)
- [x] Incus integration for LXC
- [x] SSH Certificate-based authentication
- [ ] Opencode contributing to [services-flake#563](https://github.com/juspay/services-flake/issues/563) via pu instances
- [ ] Multiple opencode agents in kolu, running pu instances to contribute to a large internal Juspay project in parallel

## Todo

- [X] VM test
- [X] Custom hostname
- [ ] Rename "hypervisor" → "container and VM manager" for Incus
- [ ] ext4 -> btrfs -- for instant snapshots
  - [ ] Change Incus storage to `driver = "btrfs"` -- for instant CoW instance cloning
  - Gemini: ZFS handles VM block storage and snapshots significantly better than Btrfs, provided you have the RAM to feed it. Choose btrfs if running only LXC. 
  - [ ] Add snapshot and fork commands to pu-manager
- [X] Shared /nix/store (local-overlay-store)
- [ ] Add a skill for LLM agents to use pu instances
