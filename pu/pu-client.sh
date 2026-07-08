#!/usr/bin/env bash
set -euo pipefail

PU_HOST="${PU_HOST:-pu}"
PU_ADMIN="${PU_ADMIN:-toor}"
PU_USE_SSH_CA="${PU_USE_SSH_CA:-true}"
STEP_FINGERPRINT="${STEP_FINGERPRINT:-76bb5cab2458b5331221da3cc6754102189a03184d119b26ce5284b49fa06463}"
STEP_CA_URL="${STEP_CA_URL:-https://${PU_HOST}:8443}"
CLI_NAME="${0##*/}"
export STEP_FINGERPRINT STEP_CA_URL

PU_STATE_DIR="${PU_STATE_DIR:-$HOME/.pu-state}"
mkdir -p "$PU_STATE_DIR"

require_step_cli() {
  if [ "${PU_USE_SSH_CA:-}" = "true" ] && ! command -v step >/dev/null 2>&1; then
    echo "step-cli is not installed." >&2
    echo "Install from: https://smallstep.com/docs/step-cli/installation/" >&2
    exit 1
  fi
}

pu_version() {
  echo "GNU bash, version $BASH_VERSION"
  ssh -V 2>&1
  [ "${PU_USE_SSH_CA:-}" = "true" ] && step version | head -1
}

require_step_cli

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

  if [ ! -f "$PU_STATE_DIR/key-cert.pub" ] ||
    [ ! -f "$PU_STATE_DIR/key-cert.provisioner" ] ||
    [ "$(cat "$PU_STATE_DIR/key-cert.provisioner")" != GoogleBrowserless ] ||
    step ssh needs-renewal "$PU_STATE_DIR/key-cert.pub" --expires-in 75% 2>/dev/null; then
    echo "Signing SSH key..." >&2
    step ssh certificate --force --no-agent --no-password --insecure --provisioner GoogleBrowserless --console me "$PU_STATE_DIR/key"
    echo GoogleBrowserless > "$PU_STATE_DIR/key-cert.provisioner"
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
  local name="$1" cmd="$2" label="$3"
  client_auth_init
  echo "$label..." >&2
  pu_ssh "$cmd" > /dev/null || return 1
  echo "Waiting for instance to be ready..." >&2
  pu_ssh "wait $name" > /dev/null || return 1
  write_ssh_config "$name"
  echo "$name"
}

pu_create() {
  [ $# -eq 1 ] || {
    echo "Usage: $CLI_NAME create <name>" >&2
    exit 1
  }
  local name="$1"
  pu_launch "$name" "create base-container $name" "Creating instance"
}

pu_fork() {
  [ $# -eq 2 ] || {
    echo "Usage: $CLI_NAME fork <source> <name>" >&2
    exit 1
  }
  local source="$1" name="$2"
  pu_launch "$name" "fork $source $name" "Forking $source"
}

pu_connect() {
  local name="${1:-}"
  [ -z "$name" ] && {
    echo "Usage: $CLI_NAME connect <name> [ssh options ...] [-- remote command ...]" >&2
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

  # bash 3.2 (default on macOS) errors on empty "${arr[@]}" under `set -u`.
  # Guard with ${arr[@]+"${arr[@]}"} so each array expands to nothing when empty.
  exec ssh \
    ${_pu_instance_ssh_opts[@]+"${_pu_instance_ssh_opts[@]}"} \
    ${ssh_args[@]+"${ssh_args[@]}"} \
    -o "ProxyCommand=$proxy_cmd" \
    -o ForwardAgent=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -l "$PU_ADMIN" \
    -- "$name" \
    ${remote_cmd[@]+"${remote_cmd[@]}"}
}

pu_destroy() {
  [ $# -eq 0 ] && {
    echo "Usage: $CLI_NAME destroy <name> [name ...]" >&2
    exit 1
  }

  client_auth_init

  local name
  pu_ssh destroy "$@"

  for name in "$@"; do
    rm -rf "${PU_STATE_DIR:?}/$name"
  done
}

cmd="${1:-}"

case "$cmd" in
  create)
    shift
    name="${1:-}"
    pu_create "$@"
    echo "Connect: $CLI_NAME connect $name" >&2
    ;;

  fork)
    shift
    name="${2:-}"
    pu_fork "$@"
    echo "Connect: $CLI_NAME connect $name" >&2
    ;;

  connect)
    shift
    pu_connect "$@"
    ;;

  destroy)
    shift
    pu_destroy "$@"
    ;;

  list)
    client_auth_init
    pu_ssh "list"
    ;;

  version)
    pu_version
    ;;

  *)
    cat >&2 <<EOF
Usage: $CLI_NAME <command>

Commands:
  create <name>                    Create instance and print a $CLI_NAME connect command
  fork <source> <name>             Fork an existing instance and print a $CLI_NAME connect command
  connect <name> [ssh args ...]    Connect to an instance via ssh; use -- before a remote command
  destroy <name> [name ...]        Destroy one or more instances
  list                             List your instances
  version                          Print bash, ssh, and step-cli versions
EOF
    exit 1
    ;;
esac
