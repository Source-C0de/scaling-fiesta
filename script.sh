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


# Configure IP Addresses
section "STEP 4: Configuring IP Address"

# ns1
ip netns exex ns1 ip link set lo up
ip netns exex ns1 ip link set veth-ns1 up
ip netns exec ns1 ip addr add 10.0.1.10/24 dev veth-ns1
info "ns1       → veth-ns1  = 10.0.1.10/24"
 
# ns2
ip netns exec ns2 ip link set lo up
ip netns exec ns2 ip link set veth-ns2 up
ip netns exec ns2 ip addr add 10.0.2.10/24 dev veth-ns2
info "ns2       → veth-ns2  = 10.0.2.10/24"
 
# router-ns (two interfaces, one per network)
ip netns exec router-ns ip link set lo up
ip netns exec router-ns ip link set veth-r0 up
ip netns exec router-ns ip link set veth-r1 up
ip netns exec router-ns ip addr add 10.0.1.1/24 dev veth-r0
ip netns exec router-ns ip addr add 10.0.2.1/24 dev veth-r1
info "router-ns → veth-r0   = 10.0.1.1/24  (Network 1 gateway)"
info "router-ns → veth-r1   = 10.0.2.1/24  (Network 2 gateway)"


section "STEP 5: Configuring Routing"
ip netns exec router-ns sysctl -w net.ipv4.ip_forward=1
info "IP forwarding enabled on router-ns"

ip netns exex ns1 ip router add default via 10.0.1.1
info "ns1 default router -> 10.0.1.1"

ip netns exec ns2 ip router add default via 10.0.2.1
info "ns2 default router -> 10.0.2.1"


section "STEP 6: Testing Connectivity"
echo ""
echo "  Route tables:"
echo "  [ ns1 ]"
ip netns exec ns1 ip route | sed 's/^/    /'
echo "  [ ns2 ]"
ip netns exec ns2 ip route | sed 's/^/    /'
echo "  [ router-ns ]"
ip netns exec router-ns ip route | sed 's/^/    /'
 
echo ""
echo "  Connectivity tests:"
 
pass=0; fail=0
 
run_ping() {
  local from_ns=$1 target=$2 label=$3
  printf "    %-40s" "$label"
  if ip netns exec "$from_ns" ping -c 2 -W 2 "$target" &>/dev/null; then
    echo -e "${GREEN}PASS${NC}"
    ((pass++))
  else
    echo -e "${RED}FAIL${NC}"
    ((fail++))
  fi
}
 
run_ping ns1      10.0.1.1   "ns1 → router gateway (10.0.1.1)"
run_ping ns2      10.0.2.1   "ns2 → router gateway (10.0.2.1)"
run_ping router-ns 10.0.1.10 "router → ns1 (10.0.1.10)"
run_ping router-ns 10.0.2.10 "router → ns2 (10.0.2.10)"
run_ping ns1      10.0.2.10  "ns1 → ns2   (10.0.2.10)  ← KEY TEST"
run_ping ns2      10.0.1.10  "ns2 → ns1   (10.0.1.10)  ← KEY TEST"
 
echo ""
echo "  Results: ${GREEN}${pass} passed${NC}, ${RED}${fail} failed${NC}"
echo ""
 
if [[ $fail -eq 0 ]]; then
  info "All connectivity tests passed! Simulation is fully operational."
else
  warn "$fail test(s) failed. Check the troubleshooting section in README.md"
fi
 
echo ""
info "To clean up all resources: sudo bash $0 clean"