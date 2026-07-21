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
    write_proxy_script
    migrate_old_ssh_configs
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

  write_proxy_script
  migrate_old_ssh_configs
}

# write_proxy_script — emit $PU_STATE_DIR/bin/pu-proxy from an embedded
# POSIX-sh template. Refreshed on every client_auth_init so upgrading the
# client automatically upgrades the ProxyCommand behaviour for every
# existing per-container ssh_config.
#
# Why indirection: `~/.pu-state/<name>/ssh_config` files persist across
# pu upgrades. If they baked the ProxyCommand inline, we'd have to
# rewrite every one to change behaviour. Instead they point at a stable
# path here; we own the script content.
write_proxy_script() {
  local dir="$PU_STATE_DIR/bin"
  local script="$dir/pu-proxy"
  mkdir -p "$dir"
  cat > "$script" <<'PROXY_EOF'
#!/bin/sh
# pu-proxy: cert pre-flight + SSH delegation. Emitted by pu-client on
# every client_auth_init. Source lives in project-unknown's pu-client.sh
# under write_proxy_script — DO NOT hand-edit this file.
#
# ProxyCommand target: `<pu-proxy> <container-name>`.
# Everything user-facing goes to stderr with a `[state=<code>]` suffix so
# support tickets carry a stable machine-readable identifier.

name="$1"
: "${PU_HOST:=pu}"
: "${PU_STATE_DIR:=$HOME/.pu-state}"
: "${PU_USE_SSH_CA:=true}"

msg() {
  code="$1"; shift
  first="$1"; shift
  printf 'pu: %s [state=%s]\n' "$first" "$code" >&2
  for line in "$@"; do
    printf '    %s\n' "$line" >&2
  done
}

# --- pre-flight: cert presence + expiry (only when SSH CA is in use) ---
if [ "$PU_USE_SSH_CA" = "true" ]; then
  CERT="$PU_STATE_DIR/key-cert.pub"
  if [ ! -f "$CERT" ]; then
    msg no-cert \
      "first-run on this machine — no SSH cert on disk." \
      "Run 'xyne-boxes list' once to create one (opens a browser sign-in)."
    exit 1
  fi
  # Cross-platform expiry check via ssh-keygen (OpenSSH built-in on macOS + Linux).
  valid_to=$(ssh-keygen -L -f "$CERT" 2>/dev/null | awk '/Valid: from/ {print $NF}')
  if [ -n "$valid_to" ] && [ "$valid_to" != "forever" ]; then
    now=$(date -u +%Y-%m-%dT%H:%M:%S)
    # ISO 8601 → lex compare works on POSIX test.
    if [ "$now" \> "$valid_to" ]; then
      msg cert-expired \
        "your SSH certificate expired at $valid_to." \
        "Run 'xyne-boxes list' — one browser sign-in refreshes the cert." \
        "VS Code / editors reconnect on their own after that."
      exit 1
    fi
  fi
fi

# --- delegate: ssh -T pu@$PU_HOST "connect $name" ---
_MACS="hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com"
if [ "$PU_USE_SSH_CA" = "true" ]; then
  ssh -T \
    -o "MACs=$_MACS" \
    -i "$PU_STATE_DIR/key" \
    -o "CertificateFile=$PU_STATE_DIR/key-cert.pub" \
    -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=$PU_STATE_DIR/known_hosts" \
    -o StrictHostKeyChecking=accept-new \
    "pu@${PU_HOST}" "connect $name"
else
  ssh -T \
    -o "MACs=$_MACS" \
    -o StrictHostKeyChecking=no \
    "pu@${PU_HOST}" "connect $name"
fi
rc=$?

if [ "$rc" -ne 0 ]; then
  msg connect-failed \
    "cannot reach pu-manager (ssh exit $rc)." \
    "Run 'xyne-boxes doctor' for a diagnosis (checks DNS / VPN / cert / cluster)."
fi
exit "$rc"
PROXY_EOF
  chmod 0755 "$script"
}

# migrate_old_ssh_configs — rewrite any per-container ssh_config whose
# ProxyCommand still bakes the old inline `ssh -T … pu@… connect NAME`
# form. Idempotent, safe to run every client_auth_init. Silent on
# already-migrated configs.
migrate_old_ssh_configs() {
  local cfg name
  [ -d "$PU_STATE_DIR" ] || return 0
  local proxy="$PU_STATE_DIR/bin/pu-proxy"
  for cfg in "$PU_STATE_DIR"/*/ssh_config; do
    [ -f "$cfg" ] || continue
    # Skip if already migrated (uses pu-proxy indirection).
    if grep -q "ProxyCommand.*pu-proxy" "$cfg" 2>/dev/null; then
      continue
    fi
    # Skip if not old-style (no ProxyCommand line at all).
    if ! grep -q '^  ProxyCommand ssh' "$cfg" 2>/dev/null; then
      continue
    fi
    name=$(basename "$(dirname "$cfg")")
    awk -v n="$name" -v p="$proxy" '
      /^  ProxyCommand ssh / { print "  ProxyCommand " p " " n; next }
      { print }
    ' "$cfg" > "$cfg.new" && mv "$cfg.new" "$cfg"
  done
}

pu_ssh() {
  ssh -nT "${_pu_ssh_opts[@]}" "pu@${PU_HOST}" "$@"
}

# Retained for callers (pu connect) that need the ProxyCommand as a
# string; now delegates to the pu-proxy script, no inline ssh.
pu_proxy_command() {
  local name="$1" proxy_cmd
  proxy_cmd=$(printf '%q %q' "$PU_STATE_DIR/bin/pu-proxy" "$name")
  printf '%s\n' "$proxy_cmd"
}

write_ssh_config() {
  local name="$1"
  local dir="$PU_STATE_DIR/$name"
  mkdir -p "$dir"

  client_auth_init

  {
    echo "Host $name"
    echo "  User $PU_ADMIN"
    [ "${PU_USE_SSH_CA:-}" = "true" ] && {
      echo "  IdentityFile $PU_STATE_DIR/key"
      echo "  CertificateFile $PU_STATE_DIR/key-cert.pub"
      echo "  IdentitiesOnly yes"
    }
    echo "  ProxyCommand $PU_STATE_DIR/bin/pu-proxy $name"
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
  write_ssh_config "$name"

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
