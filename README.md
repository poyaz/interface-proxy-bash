Run service
===========

For run and restart service use this cli

## Usage

```bash
> bash cli.sh --help
Interface proxy

Usage:
  bash cli.sh [OPTIONS...]

Command:
      install                   Install dependency
      create [interface]        Create new proxy on interface
      list                      List of proxy
      remove [interface]        Remove exist proxy from interface

Options:
  -v, --version                 Show version information and exit
  -h, --help                    Show help
```

### Sample

```bash
### Install dependency
> bash cli.sh install

### Create proxy on eno1
> bash cli.sh create eno1

### Create proxy on wlan0, wlan1, ...
> bash cli.sh create wlan.+

### Get list of proxy
> bash cli.sh list

### Remove proxy on eno1
> bash cli.sh remove eno1

### Remove proxy on wlan0, wlan1, ...
> bash cli.sh remove wlan.+
```

Install
=======

This commandline service need docker for using. For install as fast as possible you should use below command before use
API.

```bash
bash cli.sh install
```

CLI Api
=======

## Create

For create proxy on an interface you can use two pattern. The full name of interface, or the regex name of interface.

* Create with full name of interface

```bash
bash cli.sh create eno1
```

* Create with regex name of interface

```bash
bash cli.sh create wlan.+
```

**Tip:** For run service on custom ip, you can use three options:

1. Using `bash cli.sh create --listen-ip <ip-address>`
2. Copy `env/cli/.env.example` to env/cli/.env` and fill **LISTEN_IP=** variable
3. If didn't use any of previous step, The commandline prompt ask listen ip at first time

## List

To get list of proxy in use, You can use below command:

```bash
bash cli.sh list

### Output
# Listener                Outgoing                Interface
# 0.0.0.0:3128            10.101.0.25             br-6d79d7c4ca71
```

## Remove

For remove proxy on an interface you can use two pattern. The full name of interface, or the regex name of interface.

* Remove with full name of interface

```bash
bash cli.sh remove eno1
```

* Remove with regex name of interface

```bash
bash cli.sh remove wlan.+
```
