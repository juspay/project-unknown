PU_STATE_DIR="${PU_STATE_DIR:-$HOME/.pu-state}"
mkdir -p "$PU_STATE_DIR"

write_ssh_config() {
  local name="$1"
  local dir="$PU_STATE_DIR/$name"
  mkdir -p "$dir"

  local proxy_cmd
  if [ "${PU_USE_SSH_CA:-}" != "true" ]; then
    proxy_cmd="ssh -T pu@$PU_HOST \"connect $name\""
  else
    proxy_cmd="ssh -T -i $PU_STATE_DIR/key -o CertificateFile=$PU_STATE_DIR/key-cert.pub -o IdentitiesOnly=yes pu@$PU_HOST \"connect $name\""
  fi

  {
    echo "Host $name"
    echo "  User $PU_ADMIN"
    [ "${PU_USE_SSH_CA:-}" = "true" ] && {
      echo "  IdentityFile $PU_STATE_DIR/key"
      echo "  CertificateFile $PU_STATE_DIR/key-cert.pub"
      echo "  IdentitiesOnly yes"
    }
    echo "  ProxyCommand $proxy_cmd"
    echo "  ForwardAgent yes"
    echo "  StrictHostKeyChecking no"
    echo "  UserKnownHostsFile /dev/null"
  } > "$dir/ssh_config"
}

pu_launch() {
  local cmd="$1" label="$2"
  client_auth_init
  echo "$label..." >&2
  local result name
  result=$(pu_ssh "$cmd")
  name=$(awk '/^OK/ {print $2}' <<< "$result")
  if [ -z "$name" ]; then
    echo "$result" >&2
    exit 1
  fi
  echo "Waiting for instance to be ready..." >&2
  pu_ssh "wait $name" > /dev/null
  write_ssh_config "$name"
  echo "$name"
}

pu_create() {
  local name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  pu_launch "create base-container${name:+ $name}" "Creating instance"
}

pu_fork() {
  local source="${1:?Usage: pu fork <source> [--name <name>]}" name=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  pu_launch "fork $source${name:+ $name}" "Forking $source"
}

cmd="${1:-}"

case "$cmd" in
  create)
    shift
    name=$(pu_create "$@")
    echo "$name"
    echo "Connect: ssh -F $PU_STATE_DIR/$name/ssh_config $name" >&2
    ;;

  fork)
    shift
    name=$(pu_fork "$@")
    echo "$name"
    echo "Connect: ssh -F $PU_STATE_DIR/$name/ssh_config $name" >&2
    ;;

  destroy)
    name="${2:-}"
    [ -z "$name" ] && { echo "Usage: pu destroy <name>" >&2; exit 1; }
    client_auth_init
    pu_ssh "destroy $name"
    rm -rf "${PU_STATE_DIR:?}/$name"
    ;;

  list)
    client_auth_init
    pu_ssh "list"
    ;;

  *)
    cat >&2 <<'EOF'
Usage: pu <command>

Commands:
  create [--name <name>]           Create instance, print ssh command
  fork <source> [--name <name>]    Fork an existing instance, print ssh command
  destroy <name>                   Destroy an instance
  list                             List your instances
EOF
    exit 1
    ;;
esac
