# Script to set up a hotspot with your OpenBSD laptop

This script is designed to provide OpenBSD users with a simple way to set up a hotspot so that other devices can connect to the Internet. 
The goal is a similar ease of use as the hotspot functionality of smartphones.

Just run `ksh mobile-router-openbsd.sh` to build a working mobile router right with your OpenBSD laptop (or any other OpenBSD running device).

## Prerequisite

1. A working uplink (egress) connection.
2. An unused network interface.

## Limitations

1. IPv6 has not yet been implemented.
