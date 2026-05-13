#!/usr/bin/env bash
set -euo pipefail

PU_HOST="${PU_HOST:-10.10.68.56}"
PU_ADMIN="${PU_ADMIN:-toor}"
PU_USE_SSH_CA="${PU_USE_SSH_CA:-true}"
STEP_FINGERPRINT="${STEP_FINGERPRINT:-76bb5cab2458b5331221da3cc6754102189a03184d119b26ce5284b49fa06463}"
STEP_CA_URL="${STEP_CA_URL:-https://${PU_HOST}:8443}"
STEP_PROVISIONER="${STEP_PROVISIONER:-me@shivaraj-bh.in}"
export STEP_FINGERPRINT STEP_CA_URL STEP_PROVISIONER

PU_STATE_DIR="${PU_STATE_DIR:-$HOME/.pu-state}"
mkdir -p "$PU_STATE_DIR"

client_auth_init() {
  _pu_instance_ssh_opts=()
  _pu_mac_opts=(-o "MACs=hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com")

  if [ "${PU_USE_SSH_CA:-}" != "true" ]; then
    _pu_ssh_opts=("${_pu_mac_opts[@]}" -o StrictHostKeyChecking=no)
    _pu_instance_ssh_opts=("${_pu_mac_opts[@]}")
    return
  fi

  if [ ! -f "$PU_STATE_DIR/key" ]; then
    ssh-keygen -q -t ed25519 -N "" -f "$PU_STATE_DIR/key"
  fi

  if ! step ca health &>/dev/null; then
    step ca bootstrap --force
  fi

  if [ ! -f "$PU_STATE_DIR/key-cert.pub" ] || step ssh needs-renewal "$PU_STATE_DIR/key-cert.pub" --expires-in 75% 2>/dev/null; then
    echo "Signing SSH key..." >&2
    step ssh certificate --force --no-agent --no-password --insecure me "$PU_STATE_DIR/key"
  fi

  _pu_instance_ssh_opts=("${_pu_mac_opts[@]}" -i "$PU_STATE_DIR/key" -o "CertificateFile=$PU_STATE_DIR/key-cert.pub" -o IdentitiesOnly=yes)
  _pu_ssh_opts=("${_pu_mac_opts[@]}" -i "$PU_STATE_DIR/key" -o "CertificateFile=$PU_STATE_DIR/key-cert.pub" -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=$PU_STATE_DIR/known_hosts" -o StrictHostKeyChecking=accept-new)
}

pu_ssh() {
  ssh -nT "${_pu_ssh_opts[@]}" "pu@${PU_HOST}" "$@"
}

pu_proxy_command() {
  local name="$1" proxy_cmd
  local proxy_args=(ssh -T "${_pu_ssh_opts[@]}" "pu@${PU_HOST}" "connect $name")
  printf -v proxy_cmd '%q ' "${proxy_args[@]}"
  printf '%s\n' "${proxy_cmd% }"
}

write_ssh_config() {
  local name="$1"
  local dir="$PU_STATE_DIR/$name"
  mkdir -p "$dir"

  client_auth_init

  local proxy_cmd
  proxy_cmd=$(pu_proxy_command "$name")

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

pu_connect() {
  local name="${1:-}"
  [ -z "$name" ] && {
    echo "Usage: pu connect <name> [ssh options ...] [-- remote command ...]" >&2
    exit 1
  }
  shift

  local ssh_args=() remote_cmd=() saw_separator=false
  while [ $# -gt 0 ]; do
    if [ "$1" = "--" ]; then
      saw_separator=true
      shift
      continue
    fi

    if [ "$saw_separator" = "false" ] && [ ${#ssh_args[@]} -eq 0 ] && [[ "$1" != -* ]]; then
      remote_cmd=("$@")
      break
    fi

    if [ "$saw_separator" = "true" ]; then
      remote_cmd+=("$1")
    else
      ssh_args+=("$1")
    fi
    shift
  done

  client_auth_init

  local proxy_cmd
  proxy_cmd=$(pu_proxy_command "$name")

  exec ssh \
    "${_pu_instance_ssh_opts[@]}" \
    "${ssh_args[@]}" \
    -o "ProxyCommand=$proxy_cmd" \
    -o ForwardAgent=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -l "$PU_ADMIN" \
    -- "$name" \
    "${remote_cmd[@]}"
}

cmd="${1:-}"

case "$cmd" in
  create)
    shift
    name=$(pu_create "$@")
    echo "$name"
    echo "Connect: pu connect $name" >&2
    ;;

  fork)
    shift
    name=$(pu_fork "$@")
    echo "$name"
    echo "Connect: pu connect $name" >&2
    ;;

  connect)
    shift
    pu_connect "$@"
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
  create [--name <name>]           Create instance and print a pu connect command
  fork <source> [--name <name>]    Fork an existing instance and print a pu connect command
  connect <name> [ssh args ...]    Connect to an instance via ssh; use -- before a remote command
  destroy <name>                   Destroy an instance
  list                             List your instances
EOF
    exit 1
    ;;
esac
