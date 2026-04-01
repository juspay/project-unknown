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
  owner=$(hyp_get_owner "$name")
  if [ "$owner" != "$identity" ]; then
    echo "ERR not owner of $name" >&2
    exit 1
  fi
}

identity=$(auth_get_identity)

read -r -a args <<< "${SSH_ORIGINAL_COMMAND:-}"
cmd="${args[0]:-}"

case "$cmd" in
  create)
    image="${args[1]:-}"
    [ -z "$image" ] && { echo "ERR usage: create <image>" >&2; exit 1; }
    name="$(gen_name)"
    if hyp_create "$image" "$name" "$identity"; then
      echo "OK $name"
    else
      echo "ERR failed to create container" >&2; exit 1
    fi
    ;;
  list)
    hyp_list "$identity"
    ;;
  destroy)
    name="${args[1]:-}"
    [ -z "$name" ] && { echo "ERR usage: destroy <name>" >&2; exit 1; }
    require_owner "$name" "$identity"
    if hyp_destroy "$name"; then
      echo "OK destroyed"
    else
      echo "ERR failed to delete container" >&2; exit 1
    fi
    ;;
  wait)
    name="${args[1]:-}"
    [ -z "$name" ] && { echo "ERR usage: wait <name>" >&2; exit 1; }
    require_owner "$name" "$identity"
    for _ in $(seq 1 30); do
      ip=$(hyp_get_ip "$name") || true
      if [ -n "$ip" ] && tunnel_probe "$ip" 22; then
        hyp_inject_secrets "$name"
        echo "OK $ip"
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
    require_owner "$name" "$identity"
    ip=$(hyp_get_ip "$name")
    [ -z "$ip" ] && { echo "ERR no IPv4 for $name" >&2; exit 1; }
    tunnel_connect "$ip" 22
    ;;
  *)
    echo "Commands: create <image>, list, destroy <name>, wait <name>, connect <name>" >&2
    ;;
esac
