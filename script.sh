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
