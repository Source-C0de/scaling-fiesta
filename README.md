# Linux Network Namespace Simulation

**Author:** Fahmim Shahriar  
**Assignment:** Network Namespace Simulation with Bridges and Routing  
**Platform:** Linux (Ubuntu / Debian recommended)

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Background & Concepts](#2-background--concepts)
3. [Network Topology](#3-network-topology)
4. [IP Addressing Scheme](#4-ip-addressing-scheme)
5. [Component Breakdown](#5-component-breakdown)
6. [Bash Automation Script](#6-bash-automation-script)
7. [Manual Step-by-Step Commands](#7-manual-step-by-step-commands)
8. [Routing Configuration](#8-routing-configuration)
9. [Testing Procedures & Results](#9-testing-procedures--results)
10. [Cleanup](#10-cleanup)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Project Overview

This project simulates a two-network environment entirely inside a single Linux host using **network namespaces**, **virtual ethernet pairs (veth)**, and **Linux bridges**. No physical hardware or virtual machines are required.

The goal is to demonstrate:
- How isolated network environments work
- How a software router connects two separate subnets
- How IP forwarding and static routing enable cross-network communication

The final result: a host `ns1` on one subnet can successfully **ping** a host `ns2` on a completely separate subnet, with all traffic routed through a dedicated `router-ns` namespace.

---

## 2. Background & Concepts

Before diving into the implementation, it is important to understand the building blocks used.

### 2.1 Network Namespaces

A **network namespace** is a Linux kernel feature that provides a completely isolated copy of the network stack — its own interfaces, routing table, ARP table, firewall rules, and sockets.

> Think of each namespace as a separate "virtual machine" that shares the same kernel but has no network visibility into other namespaces unless explicitly connected.

**Why they are needed here:**  
We need `ns1` and `ns2` to behave like independent hosts on different networks. Without namespaces, they would all share the same host network stack and routing table, making true isolation impossible.

### 2.2 Virtual Ethernet Pairs (veth)

A **veth pair** is a pair of virtual network interfaces that act like two ends of a direct cable. Whatever is sent into one end comes out the other end.

```
  [veth-ns1] <-----------> [veth-br0]
    (inside ns1)              (connected to br0)
```

**Why they are needed here:**  
Namespaces cannot share physical interfaces. Veth pairs are the "virtual cables" that connect a namespace to a bridge or to another namespace.

### 2.3 Linux Bridge

A **Linux bridge** is a virtual Layer 2 switch. It learns MAC addresses and forwards Ethernet frames between all interfaces attached to it, just like a physical network switch.

**Why they are needed here:**  
Each subnet (`10.0.1.0/24` and `10.0.2.0/24`) needs a switch to aggregate its members. `br0` acts as the switch for Network 1, and `br1` acts as the switch for Network 2. The router namespace connects one interface to each bridge, enabling routing between the two networks.

### 2.4 IP Forwarding

By default, Linux drops packets that arrive on one interface but are destined for a different network. **IP forwarding** must be explicitly enabled to allow a host (or namespace) to act as a router and pass packets between interfaces.

**Why it is needed here:**  
The `router-ns` namespace has two interfaces — one on each network. Without IP forwarding enabled inside it, it will silently drop any packet trying to cross from one network to the other.

---

## 3. Network Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│                          LINUX HOST                                 │
│                                                                     │
│  ┌──────────────┐        ┌──────────────┐        ┌──────────────┐  │
│  │     ns1      │        │  router-ns   │        │     ns2      │  │
│  │              │        │              │        │              │  │
│  │  10.0.1.10   │        │  10.0.1.1    │        │  10.0.2.10   │  │
│  │  /24         │        │  (veth-r0)   │        │  /24         │  │
│  │  (veth-ns1)  │        │              │        │  (veth-ns2)  │  │
│  └──────┬───────┘        │  10.0.2.1    │        └──────┬───────┘  │
│         │                │  (veth-r1)   │               │          │
│         │                └──────┬───────┘               │          │
│         │                       │  │                    │          │
│   ┌─────┴───────────────────────┘  └──────────────────┐ │          │
│   │     (veth-br0)            (veth-br1)              │ │          │
│   │                                                    │ │          │
│   │  ┌─────────────────────┐  ┌──────────────────────┐│ │          │
│   │  │        br0          │  │         br1           ││ │          │
│   │  │  (10.0.1.0/24)      │  │   (10.0.2.0/24)      ││ │          │
│   └──┤  Layer 2 Switch     ├──┤   Layer 2 Switch     ├┘ │          │
│      │                     │  │                      ├───┘          │
│      └─────────────────────┘  └──────────────────────┘             │
│                                                                     │
│  Network 1: 10.0.1.0/24          Network 2: 10.0.2.0/24           │
└─────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow: ns1 → ns2

```
ns1 (10.0.1.10)
  → veth-ns1 → br0
  → veth-br0 → router-ns (10.0.1.1)
  [IP forwarding inside router-ns]
  → veth-r1 → br1
  → veth-br1 → ns2 (10.0.2.10)
```

---

## 4. IP Addressing Scheme

| Component      | Interface   | IP Address    | Subnet         | Role                          |
|----------------|-------------|---------------|----------------|-------------------------------|
| `ns1`          | `veth-ns1`  | `10.0.1.10/24`| `10.0.1.0/24`  | Host on Network 1             |
| `router-ns`    | `veth-r0`   | `10.0.1.1/24` | `10.0.1.0/24`  | Router gateway for Network 1  |
| `router-ns`    | `veth-r1`   | `10.0.2.1/24` | `10.0.2.0/24`  | Router gateway for Network 2  |
| `ns2`          | `veth-ns2`  | `10.0.2.10/24`| `10.0.2.0/24`  | Host on Network 2             |
| `br0`          | *(bridge)*  | *(no IP)*     | `10.0.1.0/24`  | Layer 2 switch for Network 1  |
| `br1`          | *(bridge)*  | *(no IP)*     | `10.0.2.0/24`  | Layer 2 switch for Network 2  |

### Why These Addresses?

- **`10.0.1.0/24`** and **`10.0.2.0/24`** are private RFC 1918 ranges — safe for lab use with no risk of collision with public internet routes.
- **`.1`** addresses are assigned to the router on each subnet — this is a common convention so hosts always know their gateway.
- **`.10`** addresses are assigned to hosts — arbitrary choice, but kept away from `.1` to avoid confusion.
- Bridges have **no IP addresses** because they operate at Layer 2 only — they forward frames, not packets.

---

## 5. Component Breakdown

### 5.1 Bridge `br0` — Network 1 Switch

**What it is:** A virtual Layer 2 switch bound to the `10.0.1.0/24` subnet.

**Why it is needed:** Without a bridge, you would need a direct veth link between every pair of devices on the same network. A bridge allows multiple devices to share the same Layer 2 segment, just like a physical switch. `ns1` and the router's `veth-r0` both plug into `br0`.

**Interfaces attached:**
- `veth-br0` — peer of the veth inside `ns1`
- `veth-rtr0` — peer of `veth-r0` inside `router-ns`

---

### 5.2 Bridge `br1` — Network 2 Switch

**What it is:** A virtual Layer 2 switch bound to the `10.0.2.0/24` subnet.

**Why it is needed:** Same reason as `br0`, but for Network 2. It connects `ns2` and the router's second interface.

**Interfaces attached:**
- `veth-br1` — peer of the veth inside `ns2`
- `veth-rtr1` — peer of `veth-r1` inside `router-ns`

---

### 5.3 Namespace `ns1` — Host on Network 1

**What it is:** An isolated network stack representing a host with IP `10.0.1.10`.

**Why it is needed:** This is one of the two endpoints we want to establish communication between. By placing it in its own namespace, it has no default knowledge of Network 2 — it must send traffic to its gateway (the router) to reach `ns2`.

**Configuration:**
- Interface `veth-ns1` with IP `10.0.1.10/24`
- Default route via `10.0.1.1` (router)
- Loopback `lo` brought up

---

### 5.4 Namespace `ns2` — Host on Network 2

**What it is:** An isolated network stack representing a host with IP `10.0.2.10`.

**Why it is needed:** This is the second endpoint. It lives on a completely different subnet from `ns1`. It must also send traffic to its own gateway (the router) to reach `ns1`.

**Configuration:**
- Interface `veth-ns2` with IP `10.0.2.10/24`
- Default route via `10.0.2.1` (router)
- Loopback `lo` brought up

---

### 5.5 Namespace `router-ns` — The Router

**What it is:** A namespace with two interfaces — one on each network — with IP forwarding enabled. This makes it act as a software router.

**Why it is needed:** This is the critical component that bridges the two isolated networks. Without it, a packet from `ns1` destined for `10.0.2.10` would have nowhere to go. The router receives that packet on `veth-r0`, looks up its routing table, and forwards it out `veth-r1` toward `br1` and ultimately `ns2`.

**Configuration:**
- Interface `veth-r0` with IP `10.0.1.1/24` (gateway for ns1)
- Interface `veth-r1` with IP `10.0.2.1/24` (gateway for ns2)
- `net.ipv4.ip_forward = 1` enabled inside the namespace

---

### 5.6 Veth Pairs — The Virtual Cables

| Pair Name       | End 1 (Namespace)        | End 2 (Bridge/Host)  |
|-----------------|--------------------------|----------------------|
| `veth-ns1` / `veth-br0`  | `ns1`           | `br0`               |
| `veth-ns2` / `veth-br1`  | `ns2`           | `br1`               |
| `veth-r0` / `veth-rtr0`  | `router-ns`     | `br0`               |
| `veth-r1` / `veth-rtr1`  | `router-ns`     | `br1`               |

**Why veth pairs?** A veth pair is like a patch cable. One end lives inside a namespace; the other is attached to a bridge. The bridge then connects that namespace to all other devices on the same Layer 2 segment.

---

## 6. Bash Automation Script

Save the following as `netns-setup.sh` and run it with `sudo bash netns-setup.sh`.

```bash
#!/usr/bin/env bash
# =============================================================================
# netns-setup.sh
# Linux Network Namespace Simulation: ns1 <--> router-ns <--> ns2
#
# Topology:
#   ns1 (10.0.1.10) --- br0 --- router-ns --- br1 --- ns2 (10.0.2.10)
#
# Usage:
#   sudo bash netns-setup.sh         # create and configure
#   sudo bash netns-setup.sh clean   # tear down everything
# =============================================================================

set -euo pipefail

# ─── Colour helpers ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Privilege check ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)."
  exit 1
fi

# =============================================================================
# CLEANUP FUNCTION
# Removes all bridges, namespaces, and interfaces created by this script.
# Safe to run even if setup was only partially completed.
# =============================================================================
cleanup() {
  info "Starting cleanup..."

  # Delete network namespaces (this automatically deletes veth interfaces inside them)
  for ns in ns1 ns2 router-ns; do
    if ip netns list | grep -qw "$ns"; then
      ip netns del "$ns"
      info "  Deleted namespace: $ns"
    fi
  done

  # Take down and delete bridges
  for br in br0 br1; do
    if ip link show "$br" &>/dev/null; then
      ip link set "$br" down
      ip link del "$br"
      info "  Deleted bridge: $br"
    fi
  done

  # Clean up any orphaned veth ends still on the host
  for iface in veth-br0 veth-br1 veth-rtr0 veth-rtr1; do
    if ip link show "$iface" &>/dev/null; then
      ip link del "$iface"
      info "  Deleted orphan interface: $iface"
    fi
  done

  info "Cleanup complete. All namespaces and bridges removed."
}

# If called with 'clean' argument, just clean up and exit
if [[ "${1:-}" == "clean" ]]; then
  cleanup
  exit 0
fi

# =============================================================================
# STEP 1: CREATE NETWORK BRIDGES
# br0 serves Network 1 (10.0.1.0/24)
# br1 serves Network 2 (10.0.2.0/24)
# =============================================================================
info "Step 1: Creating bridges..."

ip link add name br0 type bridge
ip link add name br1 type bridge

# Bring bridges up (they must be UP to forward frames)
ip link set br0 up
ip link set br1 up

info "  br0 and br1 created and activated."

# =============================================================================
# STEP 2: CREATE NETWORK NAMESPACES
# Three isolated network stacks: ns1, ns2, router-ns
# =============================================================================
info "Step 2: Creating network namespaces..."

ip netns add ns1
ip netns add ns2
ip netns add router-ns

info "  Namespaces created: ns1, ns2, router-ns"
info "  Verification:"
ip netns list

# =============================================================================
# STEP 3: CREATE VETH PAIRS AND CONNECT TO NAMESPACES + BRIDGES
#
# Pair A: veth-ns1 (inside ns1) <--> veth-br0 (on br0)
# Pair B: veth-ns2 (inside ns2) <--> veth-br1 (on br1)
# Pair C: veth-r0  (inside router-ns) <--> veth-rtr0 (on br0)
# Pair D: veth-r1  (inside router-ns) <--> veth-rtr1 (on br1)
# =============================================================================
info "Step 3: Creating veth pairs and attaching to namespaces and bridges..."

# ── Pair A: ns1 <--> br0 ──────────────────────────────────────────────────
ip link add veth-ns1 type veth peer name veth-br0
ip link set veth-ns1 netns ns1          # move one end into ns1
ip link set veth-br0 master br0         # attach other end to bridge br0
ip link set veth-br0 up

# ── Pair B: ns2 <--> br1 ──────────────────────────────────────────────────
ip link add veth-ns2 type veth peer name veth-br1
ip link set veth-ns2 netns ns2          # move one end into ns2
ip link set veth-br1 master br1         # attach other end to bridge br1
ip link set veth-br1 up

# ── Pair C: router-ns <--> br0 ────────────────────────────────────────────
ip link add veth-r0 type veth peer name veth-rtr0
ip link set veth-r0 netns router-ns     # router's Network 1 interface
ip link set veth-rtr0 master br0        # attach to br0
ip link set veth-rtr0 up

# ── Pair D: router-ns <--> br1 ────────────────────────────────────────────
ip link add veth-r1 type veth peer name veth-rtr1
ip link set veth-r1 netns router-ns     # router's Network 2 interface
ip link set veth-rtr1 master br1        # attach to br1
ip link set veth-rtr1 up

info "  All veth pairs created and connected."

# =============================================================================
# STEP 4: CONFIGURE IP ADDRESSES
# Each namespace gets its interface(s) configured and loopback brought up.
# =============================================================================
info "Step 4: Assigning IP addresses..."

# ── ns1: 10.0.1.10/24 ────────────────────────────────────────────────────
ip netns exec ns1 ip link set lo up
ip netns exec ns1 ip link set veth-ns1 up
ip netns exec ns1 ip addr add 10.0.1.10/24 dev veth-ns1
info "  ns1: veth-ns1 = 10.0.1.10/24"

# ── ns2: 10.0.2.10/24 ────────────────────────────────────────────────────
ip netns exec ns2 ip link set lo up
ip netns exec ns2 ip link set veth-ns2 up
ip netns exec ns2 ip addr add 10.0.2.10/24 dev veth-ns2
info "  ns2: veth-ns2 = 10.0.2.10/24"

# ── router-ns: 10.0.1.1/24 and 10.0.2.1/24 ──────────────────────────────
ip netns exec router-ns ip link set lo up
ip netns exec router-ns ip link set veth-r0 up
ip netns exec router-ns ip link set veth-r1 up
ip netns exec router-ns ip addr add 10.0.1.1/24 dev veth-r0
ip netns exec router-ns ip addr add 10.0.2.1/24 dev veth-r1
info "  router-ns: veth-r0 = 10.0.1.1/24, veth-r1 = 10.0.2.1/24"

# =============================================================================
# STEP 5: CONFIGURE ROUTING
#
# a) Enable IP forwarding inside router-ns (makes it act as a router)
# b) Add default routes in ns1 and ns2 pointing to the router
# =============================================================================
info "Step 5: Configuring routing..."

# Enable IP forwarding in router-ns
# Without this, the kernel drops packets destined for a different network
ip netns exec router-ns sysctl -qw net.ipv4.ip_forward=1
info "  IP forwarding enabled in router-ns."

# Default route in ns1: send all non-local traffic to the router on Network 1
ip netns exec ns1 ip route add default via 10.0.1.1
info "  ns1 default route: via 10.0.1.1"

# Default route in ns2: send all non-local traffic to the router on Network 2
ip netns exec ns2 ip route add default via 10.0.2.1
info "  ns2 default route: via 10.0.2.1"

# =============================================================================
# STEP 6: VERIFICATION SUMMARY
# =============================================================================
info "Step 6: Setup complete. Running verification..."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  INTERFACE SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[ ns1 ]"
ip netns exec ns1 ip addr show veth-ns1 | grep -E "inet |state"
echo "[ ns2 ]"
ip netns exec ns2 ip addr show veth-ns2 | grep -E "inet |state"
echo "[ router-ns ]"
ip netns exec router-ns ip addr show veth-r0 | grep -E "inet |state"
ip netns exec router-ns ip addr show veth-r1 | grep -E "inet |state"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ROUTE TABLES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[ ns1 routes ]"
ip netns exec ns1 ip route
echo "[ ns2 routes ]"
ip netns exec ns2 ip route
echo "[ router-ns routes ]"
ip netns exec router-ns ip route
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CONNECTIVITY TESTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_ping() {
  local from_ns=$1 target=$2 label=$3
  echo -n "  Ping $label ... "
  if ip netns exec "$from_ns" ping -c 2 -W 2 "$target" &>/dev/null; then
    echo -e "${GREEN}PASS${NC}"
  else
    echo -e "${RED}FAIL${NC}"
  fi
}

run_ping ns1 10.0.1.1   "ns1 → router (10.0.1.1)"
run_ping ns2 10.0.2.1   "ns2 → router (10.0.2.1)"
run_ping ns1 10.0.2.10  "ns1 → ns2   (10.0.2.10)"
run_ping ns2 10.0.1.10  "ns2 → ns1   (10.0.1.10)"

echo ""
info "All done! To clean up, run: sudo bash netns-setup.sh clean"
```

---

## 7. Manual Step-by-Step Commands

If you prefer to run each command individually (useful for learning and debugging), follow these steps in a root terminal.

### Step 1 — Create Bridges

```bash
# Create br0 for Network 1 and br1 for Network 2
ip link add name br0 type bridge
ip link add name br1 type bridge

# Bridges must be UP to forward frames
ip link set br0 up
ip link set br1 up
```

**Verification:**
```bash
ip link show type bridge
```

---

### Step 2 — Create Namespaces

```bash
ip netns add ns1
ip netns add ns2
ip netns add router-ns
```

**Verification:**
```bash
ip netns list
# Expected output:
# router-ns
# ns2
# ns1
```

---

### Step 3 — Create Veth Pairs and Connect

```bash
# --- ns1 connection to br0 ---
ip link add veth-ns1 type veth peer name veth-br0
ip link set veth-ns1 netns ns1
ip link set veth-br0 master br0
ip link set veth-br0 up

# --- ns2 connection to br1 ---
ip link add veth-ns2 type veth peer name veth-br1
ip link set veth-ns2 netns ns2
ip link set veth-br1 master br1
ip link set veth-br1 up

# --- router-ns connection to br0 ---
ip link add veth-r0 type veth peer name veth-rtr0
ip link set veth-r0 netns router-ns
ip link set veth-rtr0 master br0
ip link set veth-rtr0 up

# --- router-ns connection to br1 ---
ip link add veth-r1 type veth peer name veth-rtr1
ip link set veth-r1 netns router-ns
ip link set veth-rtr1 master br1
ip link set veth-rtr1 up
```

**Verification:**
```bash
# Check bridge membership
bridge link show
```

---

### Step 4 — Configure IP Addresses

```bash
# --- ns1 ---
ip netns exec ns1 ip link set lo up
ip netns exec ns1 ip link set veth-ns1 up
ip netns exec ns1 ip addr add 10.0.1.10/24 dev veth-ns1

# --- ns2 ---
ip netns exec ns2 ip link set lo up
ip netns exec ns2 ip link set veth-ns2 up
ip netns exec ns2 ip addr add 10.0.2.10/24 dev veth-ns2

# --- router-ns ---
ip netns exec router-ns ip link set lo up
ip netns exec router-ns ip link set veth-r0 up
ip netns exec router-ns ip link set veth-r1 up
ip netns exec router-ns ip addr add 10.0.1.1/24 dev veth-r0
ip netns exec router-ns ip addr add 10.0.2.1/24 dev veth-r1
```

**Verification:**
```bash
ip netns exec ns1 ip addr
ip netns exec ns2 ip addr
ip netns exec router-ns ip addr
```

---

### Step 5 — Configure Routing

```bash
# Enable IP forwarding in router-ns (THE most important routing step)
ip netns exec router-ns sysctl -w net.ipv4.ip_forward=1

# Tell ns1 to send all non-local traffic to the router
ip netns exec ns1 ip route add default via 10.0.1.1

# Tell ns2 to send all non-local traffic to the router
ip netns exec ns2 ip route add default via 10.0.2.1
```

**Verification:**
```bash
ip netns exec ns1 ip route
ip netns exec ns2 ip route
ip netns exec router-ns ip route
```

---

## 8. Routing Configuration

### How a Packet Travels from ns1 to ns2

1. `ns1` (10.0.1.10) wants to reach `ns2` (10.0.2.10).
2. `ns1` sees that 10.0.2.10 is **not** on its own subnet (10.0.1.0/24), so it consults its routing table.
3. The default route in `ns1` says: *send everything else to 10.0.1.1*.
4. The packet is sent out `veth-ns1` → through `br0` → into `router-ns` via `veth-r0`.
5. `router-ns` has IP forwarding enabled. It checks its own routing table.
6. The 10.0.2.0/24 route is directly connected via `veth-r1`, so it forwards the packet out `veth-r1`.
7. The packet exits through `veth-rtr1` → through `br1` → into `ns2` via `veth-ns2`.
8. `ns2` receives the packet on 10.0.2.10.
9. The reply follows the reverse path.

### Route Table Summary

| Namespace   | Destination     | Gateway    | Interface   |
|-------------|-----------------|------------|-------------|
| `ns1`       | `10.0.1.0/24`   | directly connected | `veth-ns1` |
| `ns1`       | `default (0.0.0.0/0)` | `10.0.1.1` | `veth-ns1` |
| `ns2`       | `10.0.2.0/24`   | directly connected | `veth-ns2` |
| `ns2`       | `default (0.0.0.0/0)` | `10.0.2.1` | `veth-ns2` |
| `router-ns` | `10.0.1.0/24`   | directly connected | `veth-r0`  |
| `router-ns` | `10.0.2.0/24`   | directly connected | `veth-r1`  |

---

## 9. Testing Procedures & Results

Run all tests from a root terminal after setup.

### Test 1 — ns1 can reach the router

```bash
ip netns exec ns1 ping -c 3 10.0.1.1
```

**Expected output:**
```
PING 10.0.1.1 (10.0.1.1): 56 data bytes
64 bytes from 10.0.1.1: icmp_seq=0 ttl=64 time=X.XX ms
64 bytes from 10.0.1.1: icmp_seq=1 ttl=64 time=X.XX ms
64 bytes from 10.0.1.1: icmp_seq=2 ttl=64 time=X.XX ms
```

**What this tests:** The veth pair between ns1 and br0 is working, and the router's Network 1 interface is reachable.

---

### Test 2 — ns2 can reach the router

```bash
ip netns exec ns2 ping -c 3 10.0.2.1
```

**What this tests:** The veth pair between ns2 and br1 is working, and the router's Network 2 interface is reachable.

---

### Test 3 — ns1 can reach ns2 (cross-network routing)

```bash
ip netns exec ns1 ping -c 3 10.0.2.10
```

**What this tests:** The complete end-to-end path — veth pairs, bridges, IP forwarding in the router, and the return route.

---

### Test 4 — ns2 can reach ns1 (reverse path)

```bash
ip netns exec ns2 ping -c 3 10.0.1.10
```

**What this tests:** Bidirectional routing. The return path is equally important.

---

### Test 5 — Namespace isolation (negative test)

```bash
# This should fail — ns1 has no route to the host or other subnets
ip netns exec ns1 ping -c 2 -W 1 8.8.8.8
```

**Expected:** Request timeout or `Network unreachable`. This confirms that namespace isolation is working — ns1 cannot accidentally reach the outside world.

---

## 10. Cleanup

Always clean up after testing to avoid conflicts with future configurations.

### Using the script

```bash
sudo bash netns-setup.sh clean
```

### Manual cleanup

```bash
# Delete namespaces (also removes veth interfaces inside them)
ip netns del ns1
ip netns del ns2
ip netns del router-ns

# Take down and remove bridges
ip link set br0 down && ip link del br0
ip link set br1 down && ip link del br1

# Remove any orphaned host-side veth interfaces
ip link del veth-br0 2>/dev/null || true
ip link del veth-br1 2>/dev/null || true
ip link del veth-rtr0 2>/dev/null || true
ip link del veth-rtr1 2>/dev/null || true
```

**Why cleanup matters:**
- Network namespaces and bridges persist across your terminal session — they survive until the machine reboots or you explicitly delete them.
- Leftover interfaces with the same names will cause `RTNETLINK answers: File exists` errors if you try to run setup again.
- Leftover `sysctl` changes (like `ip_forward`) are confined to the deleted namespace and disappear automatically.

---
## 11. Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| `RTNETLINK answers: File exists` | Leftover interface from previous run | Run `sudo bash netns-setup.sh clean` first |
| Ping works ns1→router but not ns1→ns2 | IP forwarding not enabled in router-ns | `ip netns exec router-ns sysctl -w net.ipv4.ip_forward=1` |
| Ping fails entirely | Interface not brought UP | Check `ip netns exec <ns> ip link` — all interfaces must show `UP` |
| `Network is unreachable` | Missing default route in ns1 or ns2 | `ip netns exec ns1 ip route add default via 10.0.1.1` |
| `ip: command not found` | Running on minimal container | Install `iproute2`: `apt install iproute2` |
| Permission denied | Not running as root | Prefix all commands with `sudo` or switch to root |

---
