PU_STATE_DIR="${PU_STATE_DIR:-$HOME/.pu-state}"
mkdir -p "$PU_STATE_DIR"

write_ssh_config() {
  local name="$1"
  local dir="$PU_STATE_DIR/$name"
  {
    echo "Host $name"
    echo "  User $PU_ADMIN"
    if [ -f "$dir/key" ]; then
      echo "  IdentityFile $dir/key"
      echo "  CertificateFile $dir/key-cert.pub"
      echo "  IdentitiesOnly yes"
      echo "  ProxyCommand ssh -i $dir/key -o CertificateFile=$dir/key-cert.pub -o IdentitiesOnly=yes pu@$PU_HOST \"connect $name\""
    else
      echo "  ProxyCommand ssh pu@$PU_HOST \"connect $name\""
    fi
    echo "  StrictHostKeyChecking no"
    echo "  UserKnownHostsFile /dev/null"
  } > "$dir/ssh_config"
}

pu_create() {
  client_auth_init "$PU_STATE_DIR/.pending"

  echo "Creating container..." >&2
  local result
  result=$(pu_ssh "create base-container")
  _pu_container=$(echo "$result" | awk '/^OK/ {print $2}')
  if [ -z "$_pu_container" ]; then
    echo "Failed to create container" >&2
    exit 1
  fi

  echo "Waiting for container to be ready..." >&2
  pu_ssh "wait $_pu_container" > /dev/null

  if [ -d "$PU_STATE_DIR/.pending" ]; then
    mv "$PU_STATE_DIR/.pending" "$PU_STATE_DIR/$_pu_container"
  else
    mkdir -p "$PU_STATE_DIR/$_pu_container"
  fi
  write_ssh_config "$_pu_container"
}

cmd="${1:-}"

case "$cmd" in
  create)
    pu_create
    echo "$_pu_container"
    echo "Connect: ssh -F $PU_STATE_DIR/$_pu_container/ssh_config $_pu_container" >&2
    ;;

  destroy)
    name="${2:-}"
    [ -z "$name" ] && { echo "Usage: pu destroy <name>" >&2; exit 1; }
    client_auth_init "$PU_STATE_DIR/.pending"
    pu_ssh "destroy $name"
    rm -rf "${PU_STATE_DIR:?}/$name"
    ;;

  list)
    client_auth_init "$PU_STATE_DIR/.pending"
    pu_ssh "list"
    ;;

  *)
    cat >&2 <<'EOF'
Usage: pu <command>

Commands:
  create           Create a container, print its name
  destroy <name>   Destroy a container
  list             List your containers

After 'create', connect with: ssh -F ~/.pu-state/<name>/ssh_config <name>
EOF
    exit 1
    ;;
esac
