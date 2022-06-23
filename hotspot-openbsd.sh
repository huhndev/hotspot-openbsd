#!/bin/ksh
#
# Copyright (c) 2022 Julian Huhn <julian@huhn.dev>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.

# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

set -euf -o pipefail

# TODO: Add wifi mode.
INTERNAL_MODE="wired" # Options: wired or wifi
INTERNAL_INTERFACE="em0" # Options: em0, iwm0, ... all physical OpenBSD interfaces.
INTERNAL_IP="192.168.252.1"
INTERNAL_SUBNET="192.168.252.0"
INTERNAL_NETMASK="255.255.255.0"
INTERNAL_BROADCAST="192.168.252.255"
INTERNAL_IP_RANGE_LOWER="192.168.252.100"
INTERNAL_IP_RANGE_UPPER="192.168.252.254"
# TODO: Add support for local unbound.
DNS_SERVER="159.69.114.157"

#######################
# Build config files. #
#######################

REALPATH=$(realpath "$0")
DIR=$(dirname "$REALPATH")

# Build pf.conf
print "Building pf.conf..."
cat > "$DIR"/pf.conf << ENDOFFILE
INTERNAL_INTERFACE = "$INTERNAL_INTERFACE"

set skip on lo

match out on egress inet from (\$INTERNAL_INTERFACE:network) to any nat-to (egress:0)

block return all

pass out quick inet
pass in on \$INTERNAL_INTERFACE inet
pass in on \$INTERNAL_INTERFACE inet proto udp from any to (\$INTERNAL_INTERFACE:0) port 53 rdr-to $DNS_SERVER 
ENDOFFILE

# Build dhcpd.conf
print "Building dhcpd.conf..."
cat > "$DIR"/dhcpd.conf << ENDOFFILE
subnet $INTERNAL_SUBNET netmask $INTERNAL_NETMASK {
	option routers $INTERNAL_IP;
        option domain-name-servers $INTERNAL_IP;
        range $INTERNAL_IP_RANGE_LOWER $INTERNAL_IP_RANGE_UPPER;
}
ENDOFFILE

#####################
# Shut down router. #
#####################

SHUTDOWN() {
	# Reload regular pf config.
	print "Loading regular firewall rules..."
	pfctl -f /etc/pf.conf

	# Kill the dhcpd process.
	print "Killing dhcpd..."
	pkill dhcpd || true

	# Reset IP forwarding to default value.
	if [[ $FORWARDING -eq 0 ]]
	then
	        sysctl -q net.inet.ip.forwarding=0
	fi

	# Clean up internal interface.
	print "Clean up internal interface..."
        ifconfig "$INTERNAL_INTERFACE" -inet -inet6 down 

	# Reset interfaces.
	print "Restarting networking..."
	sh /etc/netstart

	print "Mobile router shut down."
	exit 0
}

##################
# Set up router. #
##################
# TODO: Add IPv6 support.

trap "SHUTDOWN" 2

# Script can only be run as root!
USER=$(whoami)
if [[ "$USER" != "root" ]]
then
	print "Please run as root!"
	exit 1
fi

# Enable IP forwarding so that packets can travel between network interfaces.
FORWARDING=$(sysctl -n net.inet.ip.forwarding)
sysctl -q net.inet.ip.forwarding=1 

# Clean up internal interface.
print "Clean up internal interface..."
ifconfig "$INTERNAL_INTERFACE" -inet -inet6 down

# Configure the network interface for the internal network.
print "Bringing up internal interface..."
ifconfig "$INTERNAL_INTERFACE" "$INTERNAL_IP" netmask "$INTERNAL_NETMASK" broadcast "$INTERNAL_BROADCAST"

# Start dhcpd so that clients can obtain a network address.
print "Starting dhcpd..."
touch /var/db/dhcpd.leases
dhcpd -c "$DIR"/dhcpd.conf "$INTERNAL_INTERFACE" > /dev/null 2>&1

# Set up NAT. https://en.wikipedia.org/wiki/Network_address_translation
print "Loading firewall rules..."
pfctl -f "$DIR"/pf.conf

print "Congratulations! Your mobile router is up and running..."
print "Use ctrl+c for clean shutdown."

# Delete automatically generated default route of the internal interface.
END=$((SECONDS+20))
while [[ "$SECONDS" -lt "$END" ]]
do
	if route -n show | grep default | grep "$INTERNAL_INTERFACE" 
	then
		route -q delete default "$INTERNAL_IP"
		break
	fi
done

while true; do sleep 86400; done
