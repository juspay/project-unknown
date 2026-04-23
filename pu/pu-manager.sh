# Incus and ssh-keygen need a writable HOME (pu user's home is /var/empty)
HOME=$(mktemp -d)
export HOME
trap 'rm -rf "$HOME"' EXIT

gen_name() {
  echo "pu-$(head -c3 /dev/urandom | od -An -tx1 | tr -d ' \n')"
}

require_owner() {
  local name="$1" identity="$2"
  local owner
  owner=$(inst_get_owner "$name") || return 1
  if [ "$owner" != "$identity" ]; then
    echo "ERR not owner of $name" >&2
    exit 1
  fi
}

require_instance_access() {
  local name="$1" identity="$2"
  if ! inst_exists "$name"; then
    echo "ERR instance '$name' not found" >&2
    exit 1
  fi
  require_owner "$name" "$identity"
}

identity=$(auth_get_identity)

read -r -a args <<< "${SSH_ORIGINAL_COMMAND:-}"
cmd="${args[0]:-}"

case "$cmd" in
  create)
    image="${args[1]:-}"
    [ -z "$image" ] && { echo "ERR usage: create <image> [name]" >&2; exit 1; }
    name="${args[2]:-}"
    if [ -n "$name" ]; then
      if inst_exists "$name"; then
        echo "ERR name already exists" >&2; exit 1
      fi
    else
      name="$(gen_name)"
    fi
    if inst_create "$image" "$name" "$identity"; then
      echo "OK $name"
    else
      echo "ERR failed to create instance" >&2; exit 1
    fi
    ;;
  list)
    inst_list "$identity"
    ;;
  destroy)
    name="${args[1]:-}"
    [ -z "$name" ] && { echo "ERR usage: destroy <name>" >&2; exit 1; }
    require_instance_access "$name" "$identity"
    if inst_destroy "$name"; then
      echo "OK destroyed"
    else
      echo "ERR failed to delete instance" >&2; exit 1
    fi
    ;;
  wait)
    name="${args[1]:-}"
    [ -z "$name" ] && { echo "ERR usage: wait <name>" >&2; exit 1; }
    require_instance_access "$name" "$identity"
    for _ in $(seq 1 120); do
      if inst_ssh_ready "$name"; then
        netrc="/run/agenix/netrc-juspay"
        [ -f "$netrc" ] && inst_push_file "$name" "$netrc" "/etc/nix/netrc" 0 0 0400
        echo "OK ready"
        exit 0
      fi
      sleep 1
    done
    echo "ERR timeout waiting for $name" >&2
    exit 1
    ;;
  connect)
    name="${args[1]:-}"
    [ -z "$name" ] && { echo "ERR usage: connect <name>" >&2; exit 1; }
    require_instance_access "$name" "$identity"
    inst_ssh_proxy "$name"
    ;;
  fork)
    source="${args[1]:-}"
    new_name="${args[2]:-}"
    [ -z "$source" ] && { echo "ERR usage: fork <source> [name]" >&2; exit 1; }
    require_instance_access "$source" "$identity"
    if [ -n "$new_name" ]; then
      inst_exists "$new_name" && { echo "ERR name already exists" >&2; exit 1; }
    else
      new_name="$(gen_name)"
    fi
    if inst_fork "$source" "$new_name"; then
      echo "OK $new_name"
    else
      echo "ERR failed to fork $source" >&2; exit 1
    fi
    ;;
  *)
    echo "Commands: create <image> [name], list, destroy <name>, wait <name>, connect <name>, fork <source> [name]" >&2
    ;;
esac
