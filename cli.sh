#!/usr/bin/env bash

DIRNAME=$(realpath $0 | rev | cut -d'/' -f2- | rev)
readonly DIRNAME

DEFAULT_SQUID_PER_IP_COUNT=2
readonly DEFAULT_SQUID_PER_IP_COUNT

DEFAULT_SQUID_BASEDIR="${DIRNAME}/storage/tmp/squidVolume"
readonly DEFAULT_SQUID_BASEDIR

DEFAULT_PROJECT_NAME=$(basename "$DIRNAME")
readonly DEFAULT_PROJECT_NAME

LISTEN_IP=0.0.0.0

############
### function
############

function _version() {
  echo "0.1.0"
  echo ""
  exit
}

function _usage() {
  echo -e "Mysterium proxy\n"
  echo -e "Usage:"
  echo -e "  bash $0 [OPTIONS...]\n"
  echo -e "Options:"
  echo -e "      install\t\t\tInstall dependency"
  echo ""
  echo -e "  -v, --version\t\t\tShow version information and exit"
  echo -e "  -h, --help\t\t\tShow help"
  echo ""

  exit
}

function _find_distro() {
  local distro=$(awk '/^ID=/' /etc/*-release | awk -F'=' '{ print tolower($2) }')

  echo $distro
}

function _check_dependency() {
  local DISTRO=$(_find_distro)
  readonly DISTRO

  case ${DISTRO} in
  debian | ubuntu)
    dpkg -l docker >/dev/null 2>&1

    if ! [[ $? -eq 0 ]]; then
      echo -e "[ERR] Need install dependency\n"
      echo -e "Please use below command:"
      echo -e "  bash $0 install"
      echo ""

      exit 1
    fi

    dpkg -l jq >/dev/null 2>&1

    if ! [[ $? -eq 0 ]]; then
      echo -e "[ERR] Need install dependency\n"
      echo -e "Please use below command:"
      echo -e "  bash $0 install"
      echo ""

      exit 1
    fi
    ;;

  centos)
    centos_check=$(rpm -qa docker-ce jq | wc -l)

    if ! [[ ${centos_check} -eq 2 ]]; then
      echo -e "[ERR] Need install dependency\n"
      echo -e "Please use below command:"
      echo -e "  bash $0 install"
      echo ""

      exit 1
    fi
    ;;
  esac

  if [[ $(lsmod | grep tun | wc -l) -eq 0 ]]; then
    echo -e "[ERR] Need install dependency\n"
    echo -e "Please use below command:"
    echo -e "  bash $0 install"
    echo ""

    exit 1
  fi
}

#############
### Arguments
#############

execute_mode=

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case ${key} in
  install)
    execute_mode="install"
    shift
    ;;

  create)
    execute_mode="create"
    shift
    ;;

  list)
    execute_mode="list"
    shift
    ;;

  -v | --version)
    _version
    shift
    ;;

  -h | --help)
    _usage
    shift
    ;;

  *)
    # _usage
    shift
    ;;
  esac
done

set -- "${POSITIONAL[@]}"

############
### business
############

if [[ $execute_mode =~ "install|create|list" ]]; then
  echo "[ERR] Not valid option for execute"
  exit 1
fi

print_stdout() {
  echo "$1" >/dev/tty
}

print_stderr() {
  echo "$1" >/dev/stderr
}

build_image() {
  docker build -t interface-proxy-api:latest "${DIRNAME}/docker/images/squid"
}

get_next_counter() {
  local counter=$(ls -1v "$DEFAULT_SQUID_BASEDIR" | wc -l)

  echo $(( counter + 1 ))
}

get_next_port() {
  local find_port=$(find "$DEFAULT_SQUID_BASEDIR" -type f -name '*.conf' -exec sed -nr 's/^http_port\s+[^:]+:([0-9]+).+/\1/p' {} + | sort | tail -n 1)
  local select_port=3128

  if ! [[ -z $find_port ]]; then
    select_port=$(( find_port + 1 ))
  fi

  while true; do
      local is_port_in_use=$(lsof -i -P -n | grep LISTEN | grep $select_port | wc -l)
      if [[ $is_port_in_use -eq 0 ]]; then
        break
      fi

      select_port=$(( select_port + 1 ))
  done

  echo $select_port
}

get_next_dir_instance() {
  while IFS= read -r dir; do
    if [[ -z $dir ]]; then
      echo ""
      break
    fi

    local path_config="${DEFAULT_SQUID_BASEDIR}/${dir}"

    local total_conf_file=$(find "$path_config" -type f -name '*.conf' | wc -l)
    if [[ $total_conf_file -ge $DEFAULT_SQUID_PER_IP_COUNT ]]; then
      continue
    fi

    echo "$path_config"
    break
  done <<<$(ls -1v "$DEFAULT_SQUID_BASEDIR")
}

get_ip_list() {
  ip_list=$(ip a | awk -v RS='(^|\n)[0-9]+: ' '/^br-.+:/ {print}' | sed -nr 's/\s+inet\s+([^\s]+)\/[0-9]+\s+brd.+/\1/p')
  echo "$ip_list"
}

check_interface_ip_in_use() {
  local ip="$1"
  local is_ip_in_use=$(grep -r -E "^tcp_outgoing_address\s+${ip}\s*" "$DEFAULT_SQUID_BASEDIR" | wc -l)
  if [[ $is_ip_in_use -ne 0 ]]; then
    echo 1

    return
  fi

  echo 0
}

create_config_file() {
  local counter="$1"
  local listen_port="$2"
  local dir_config="$3"
  local output_ip="$4"

  if [[ -z $dir_config ]]; then
    dir_config="${DEFAULT_SQUID_BASEDIR}/squid-${counter}"
    mkdir -p "$dir_config"
  fi

  cat <<-EOF >"${dir_config}/port-${listen_port}.conf"
http_port ${LISTEN_IP}:${listen_port} name=port${listen_port}
acl out${listen_port} myportname port${listen_port}
tcp_outgoing_address ${output_ip} out${listen_port}
EOF

  echo "$dir_config"
}

run_squid_container() {
  local path_config="$1"

  local container_run=$(
    docker ps -a \
      --format '{{ .ID }}\t{{ .Status }}' \
      --filter "label=com.project.name=${DEFAULT_PROJECT_NAME}" \
      --filter "volume=${path_config}"
  )

  if [[ -z $container_run ]]; then
    docker run -d \
      --name "${DEFAULT_PROJECT_NAME}-${dir}" \
      --label "com.project.name=${DEFAULT_PROJECT_NAME}" \
      --volume "${path_config}:/etc/squid/conf.d/" \
      --network host
      interface-proxy-api:latest > /dev/null 2>&1

    if [[ $? -ne 0 ]]; then
      print_stderr "[ERR] Can't create new container."
      exit 1
    fi

    return
  fi

  local container_id=$(echo "$container_run" | awk '{ print $1 }')

  local is_container_run=$(echo "$container_run" | grep -i "up" | wc -l)
  if [[ $is_container_run -eq 1 ]]; then
    docker kill --signal=HUP $container_id > /dev/null 2>&1

    if [[ $? -ne 0 ]]; then
      print_stderr "[ERR] Can't reload exist container."
      exit 1
    fi

    return
  fi

  docker restart $container_id > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    print_stderr "[ERR] Can't restart stopped container."
    exit 1
  fi
}

install() {
  build_image
}

create_proxy() {
  mkdir -p "$DEFAULT_SQUID_BASEDIR"

  while IFS= read -r ip; do
    is_ip_in_use=$(check_interface_ip_in_use "$ip")
    if [[ $is_ip_in_use -eq 1 ]]; then
      print_stdout "[WARN] The ip address ${ip} is use."
      continue
    fi

    next_counter=$(get_next_counter)
    next_listen_port=$(get_next_port)
    next_dir_config=$(get_next_dir_instance)

    print_stdout "[INFO] Generate config file for outgoing ip ${ip}"
    service_dir_config=$(create_config_file "$next_counter" "$next_listen_port" "$next_dir_config" "$ip")

    print_stdout "[INFO] Run service on outgoing ip ${ip}"
    run_squid_container "$service_dir_config"
  done <<<$(get_ip_list)
}

list_proxy() {
  echo -e "Listener\t\tOutgoing\t\tInterface"

  while IFS= read -r dir; do
    if [[ -z $dir ]]; then
      echo ""
      exit
    fi

    local path_config="${DEFAULT_SQUID_BASEDIR}/${dir}"

    is_container_run=$(
      docker ps -q \
        --filter "label=com.project.name=${DEFAULT_PROJECT_NAME}" \
        --filter "volume=${path_config}" \
      | wc -l
    )
    if [[ $is_container_run -eq 0 ]]; then
      continue
    fi

    while IFS= read -r config_file; do
      local listener=$(sed -nr 's/^http_port\s+([^\s]+)\s+.+/\1/p' "${path_config}/${config_file}")
      local outgoing=$(sed -nr 's/^tcp_outgoing_address\s+([^\s]+)\s+.+/\1/p' "${path_config}/${config_file}")
      local interface=$(
        ip a | awk -v "target_addr=$outgoing" '
        /^[0-9]+/ {
          iface=substr($2, 0, length($2)-1)
        }

        $1 == "inet" {
          split($2, addr, "/")
          if (addr[1] == target_addr) {
            print iface
          }
        }
        '
      )

      echo -e "${listener}\t\t${outgoing}\t\t${interface:--}"
    done <<<$(ls -1v "$path_config")
  done <<<$(ls -1v "$DEFAULT_SQUID_BASEDIR")
}

case $execute_mode in
  install)
    install
    ;;

  create)
    create_proxy "$@"
    ;;

  list)
    list_proxy "$@"
    ;;
esac
