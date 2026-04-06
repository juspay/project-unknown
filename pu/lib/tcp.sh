tcp_probe() {
  local ip="$1" port="$2"
  socat /dev/null "TCP4:$ip:$port,connect-timeout=1" 2>/dev/null
}

tcp_connect() {
  local ip="$1" port="$2"
  exec socat - "TCP4:$ip:$port"
}
