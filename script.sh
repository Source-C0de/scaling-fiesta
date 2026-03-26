#!/bin/bash



# Create Bridge
section "Step 1: Creating Bridge"

ip link add name br0 type bridge
ip link add name br1 type bridge

ip link set br0 up
ip link set br1 up

info "Bridge0 and Bridge1 are created and up"

# Create Network Namespace
section "Step 2: Creating Network Namespace"

ip netns add ns1
ip netns add ns2
ip netns add router-ns

info "Created namespace: ns1 , ns2, router-ns"
info "Active namespaces: $(ip netns list)"


# Create Veth Pair and Connect to Bridge

# ── Pair A: ns1 ↔ br0 ────────────────────────────────────────────────────────
ip link add veth-ns1 type veth peer name veth-br0
ip link set veth-ns1 netns ns1       # move ns1-side into namespace
ip link set veth-br0 master br0      # attach bridge-side to br0
ip link set veth-br0 up
info "Pair A: veth-ns1 (ns1) <--> veth-br0 (br0)"
 
# ── Pair B: ns2 ↔ br1 ────────────────────────────────────────────────────────
ip link add veth-ns2 type veth peer name veth-br1
ip link set veth-ns2 netns ns2
ip link set veth-br1 master br1
ip link set veth-br1 up
info "Pair B: veth-ns2 (ns2) <--> veth-br1 (br1)"
 
# ── Pair C: router-ns ↔ br0 (Network 1 side) ─────────────────────────────────
ip link add veth-r0 type veth peer name veth-rtr0
ip link set veth-r0 netns router-ns
ip link set veth-rtr0 master br0
ip link set veth-rtr0 up
info "Pair C: veth-r0 (router-ns) <--> veth-rtr0 (br0)"
 
# ── Pair D: router-ns ↔ br1 (Network 2 side) ─────────────────────────────────
ip link add veth-r1 type veth peer name veth-rtr1
ip link set veth-r1 netns router-ns
ip link set veth-rtr1 master br1
ip link set veth-rtr1 up
info "Pair D: veth-r1 (router-ns) <--> veth-rtr1 (br1)"


