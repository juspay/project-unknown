PU_STATE_DIR="${PU_STATE_DIR:-$HOME/.pu-state}"
mkdir -p "$PU_STATE_DIR"

write_ssh_config() {
  local name="$1"
  local dir="$PU_STATE_DIR/$name"
  mkdir -p "$dir"

  local proxy_cmd
  if [ "${PU_USE_SSH_CA:-}" != "true" ]; then
    proxy_cmd="ssh pu@$PU_HOST \"connect $name\""
  else
    proxy_cmd="ssh -i $PU_STATE_DIR/key -o CertificateFile=$PU_STATE_DIR/key-cert.pub -o IdentitiesOnly=yes pu@$PU_HOST \"connect $name\""
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
    echo "  StrictHostKeyChecking no"
    echo "  UserKnownHostsFile /dev/null"
  } > "$dir/ssh_config"
}

pu_create() {
  local name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  client_auth_init

  echo "Creating instance..." >&2
  local result
  result=$(pu_ssh "create base-container${name:+ $name}")
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

cmd="${1:-}"

case "$cmd" in
  create)
    shift
    name=$(pu_create "$@")
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
  create [--name <name>]  Create instance, print ssh command
  destroy <name>          Destroy an instance
  list                    List your instances
EOF
    exit 1
    ;;
esac
