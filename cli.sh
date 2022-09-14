#!/usr/bin/env bash

DIRNAME=$(realpath $0 | rev | cut -d'/' -f2- | rev)
readonly DIRNAME

DEFAULT_SQUID_PER_IP_COUNT=2
readonly DEFAULT_SQUID_PER_IP_COUNT

DEFAULT_SQUID_BASEDIR="${DIRNAME}/storage/tmp/squidVolume"
readonly DEFAULT_SQUID_BASEDIR

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
    _install
    shift
    ;;

  run)
    execute_mode="run"
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

if [[ $execute_mode != "run" ]]; then
  echo "[ERR] Not valid option for execute"
  exit 1
fi

build_image() {
  docker build -t interface-proxy-api:latest "${DIRNAME}/docker/images/squid"
}

get_next_counter() {
  local counter=$(ls -1v "$DEFAULT_SQUID_BASEDIR" | wc -l)

  echo $(( counter + 1 ))
}

get_next_port() {
  local find_port=$(find "$DEFAULT_SQUID_BASEDIR" -type f -name '*.conf' -exec sed -nr 's/^http_port\s+[^:]+:([0-9]+).+/\1/p' {} + | tail -n 1)

  if [[ -z $find_port ]]; then
    echo "3128"
  fi

  echo $find_port
}

get_next_dir_instance() {
  while IFS= read -r dir; do
    local path_config="${DEFAULT_SQUID_BASEDIR}/${dir}"

    if [[ $(ls -1v "$path_config" | wc -l) -eq $DEFAULT_SQUID_PER_IP_COUNT ]]; then
      continue
    fi

    echo "$path_config"
    break
  done <<<$(ls -1v "$DEFAULT_SQUID_BASEDIR")
}

get_ip_list() {
  ip_list=$(ip a | awk -v RS='(^|\n)[0-9]+: ' '/^br-.+:/ {print}' | sed -nr 's/\s+inet\s+([^\s]+)\/[0-9]+\s+brd.+/\1/p')
}

create_config_file() {
  local counter="$1"
  local listen_port="$2"
  local dir_config="$3"


  echo $counter
  echo $listen_port
  echo $dir_config
}

_main() {
  mkdir -p "$DEFAULT_SQUID_BASEDIR"

  next_counter=$(get_next_counter)
  next_listen_port=$(get_next_port)
  next_dir_config=$(get_next_dir_instance)

  create_config_file "$next_counter" "$next_listen_port" "$next_dir_config"

  #  build_image
}

_main "$@"
