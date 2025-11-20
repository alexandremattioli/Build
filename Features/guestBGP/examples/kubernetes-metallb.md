# Example: Kubernetes MetalLB with Guest BGP

**Use Case:** Expose Kubernetes services with real IPv6 addresses via BGP route advertisement

**Prerequisites:**
- CloudStack network with guest BGP enabled
- Kubernetes cluster (3 nodes minimum)
- Network offering with `guestbgppeeringenabled=true`

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ CloudStack Isolated Network (2a01:b000:1046:10:1::/64)     │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │ Virtual Router (VR)                                │    │
│  │ - IPv6: 2a01:b000:1046:10:1::1                     │    │
│  │ - ASN: 65101                                       │    │
│  │ - Listens for guest BGP connections                │    │
│  └────────────────────────────────────────────────────┘    │
│                         ▲                                    │
│                         │ BGP Peering (IPv6)                │
│                         │                                    │
│  ┌──────────────────────┴───────────────────────────────┐  │
│  │ Kubernetes Nodes (3 VMs)                             │  │
│  │ - k8s-node-1: 2a01:b000:1046:10:1::50 (ASN 65201)   │  │
│  │ - k8s-node-2: 2a01:b000:1046:10:1::51 (ASN 65202)   │  │
│  │ - k8s-node-3: 2a01:b000:1046:10:1::52 (ASN 65203)   │  │
│  │                                                       │  │
│  │ MetalLB Controller:                                  │  │
│  │ - Allocates service IPs from pool                   │  │
│  │ - MetalLB speaker announces via BGP                 │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Nginx Service (LoadBalancer)                         │  │
│  │ - External IP: 2a01:b000:1046:10:1::100/128         │  │
│  │ - Advertised by MetalLB to VR via BGP               │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                         │
                         │ Redistributed to ISP
                         ▼
                  (External Internet)
```

---

## Step 1: Create CloudStack Network with Guest BGP

### Create Network Offering

```bash
cloudmonkey create networkoffering \
  name="K8s-Isolated-BGP" \
  displaytext="Kubernetes network with guest BGP support" \
  guestiptype=Isolated \
  supportedservices=Dhcp,Dns,Firewall,Lb,SourceNat,StaticNat,Vpn,DynamicRouting \
  serviceProviderList[0].service=DynamicRouting \
  serviceProviderList[0].provider=VirtualRouter \
  guestbgppeeringenabled=true \
  guestbgpminprefixlength=128 \
  guestbgpmaxprefixlength=128 \
  guestbgpmaxprefixes=50 \
  guestbgpallowedasnmin=65200 \
  guestbgpallowedasnmax=65299
```

**Parameters Explained:**
- `guestbgppeeringenabled=true` → Enable guest BGP
- `guestbgpminprefixlength=128` → Only allow /128 (host routes)
- `guestbgpmaxprefixes=50` → Each node can advertise up to 50 service IPs
- `guestbgpallowedasnmin/max` → ASN range for K8s nodes

---

### Enable Network Offering

```bash
cloudmonkey update networkoffering \
  id=<offering-id> \
  state=Enabled
```

---

### Create Network

```bash
cloudmonkey create network \
  name="k8s-cluster-network" \
  displaytext="Kubernetes cluster with MetalLB BGP" \
  networkofferingid=<offering-id> \
  zoneid=<zone-id>
```

**Result:**
- Network created with CIDR `2a01:b000:1046:10:1::/64` (auto-allocated)
- VR deployed with ASN `65101`
- VR listening for BGP connections on `2a01:b000:1046:10:1::1:179`

---

## Step 2: Deploy Kubernetes Cluster

### Deploy 3 VMs

```bash
# Node 1
cloudmonkey deploy virtualmachine \
  name="k8s-node-1" \
  serviceofferingid=<4vCPU-8GB-offering> \
  templateid=<ubuntu-22.04-template> \
  zoneid=<zone-id> \
  networkids=<network-id>

# Node 2
cloudmonkey deploy virtualmachine \
  name="k8s-node-2" \
  serviceofferingid=<4vCPU-8GB-offering> \
  templateid=<ubuntu-22.04-template> \
  zoneid=<zone-id> \
  networkids=<network-id>

# Node 3
cloudmonkey deploy virtualmachine \
  name="k8s-node-3" \
  serviceofferingid=<4vCPU-8GB-offering> \
  templateid=<ubuntu-22.04-template> \
  zoneid=<zone-id> \
  networkids=<network-id>
```

**VM IPs (auto-assigned):**
- k8s-node-1: `2a01:b000:1046:10:1::50`
- k8s-node-2: `2a01:b000:1046:10:1::51`
- k8s-node-3: `2a01:b000:1046:10:1::52`

---

### Install Kubernetes

```bash
# On all 3 nodes:
ssh ubuntu@2a01:b000:1046:10:1::50

# Install kubeadm, kubelet, kubectl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubeadm kubelet kubectl
sudo apt-mark hold kubeadm kubelet kubectl

# Initialize cluster on node-1
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Join nodes 2 and 3 (copy join command from node-1 output)
sudo kubeadm join 2a01:b000:1046:10:1::50:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

---

## Step 3: Install FRR on Kubernetes Nodes

### Install FRR

```bash
# On all 3 nodes:
sudo apt update
sudo apt install -y frr

# Enable BGP daemon
sudo sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo systemctl restart frr
```

---

### Configure BGP on Each Node

**k8s-node-1 (`2a01:b000:1046:10:1::50`):**

```bash
sudo vtysh

configure terminal

router bgp 65201
  bgp router-id 10.1.0.50
  no bgp ebgp-requires-policy
  neighbor 2a01:b000:1046:10:1::1 remote-as 65101
  
  address-family ipv6 unicast
    network 2a01:b000:1046:10:1::50/128
    neighbor 2a01:b000:1046:10:1::1 activate
  exit-address-family

exit
write memory
```

**k8s-node-2 (`2a01:b000:1046:10:1::51`):**

```bash
sudo vtysh

configure terminal

router bgp 65202
  bgp router-id 10.1.0.51
  no bgp ebgp-requires-policy
  neighbor 2a01:b000:1046:10:1::1 remote-as 65101
  
  address-family ipv6 unicast
    network 2a01:b000:1046:10:1::51/128
    neighbor 2a01:b000:1046:10:1::1 activate
  exit-address-family

exit
write memory
```

**k8s-node-3 (`2a01:b000:1046:10:1::52`):**

```bash
sudo vtysh

configure terminal

router bgp 65203
  bgp router-id 10.1.0.52
  no bgp ebgp-requires-policy
  neighbor 2a01:b000:1046:10:1::1 remote-as 65101
  
  address-family ipv6 unicast
    network 2a01:b000:1046:10:1::52/128
    neighbor 2a01:b000:1046:10:1::1 activate
  exit-address-family

exit
write memory
```

---

### Verify BGP Sessions

```bash
# On any node:
sudo vtysh -c 'show bgp ipv6 unicast summary'
```

**Expected Output:**
```
Neighbor              V   AS  MsgRcvd MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
2a01:b000:1046:10:1::1 4 65101     10      12        0    0    0 00:05:00            1
```

**Verify in CloudStack:**
```bash
cloudmonkey list bgp guest peering sessions networkid=<network-id>
```

**Expected Response:**
```json
{
  "count": 3,
  "bgppeeringsession": [
    {"guestip": "2a01:b000:1046:10:1::50", "state": "Established"},
    {"guestip": "2a01:b000:1046:10:1::51", "state": "Established"},
    {"guestip": "2a01:b000:1046:10:1::52", "state": "Established"}
  ]
}
```

---

## Step 4: Install MetalLB

### Install MetalLB via Helm

```bash
# On k8s-node-1:
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb --namespace metallb-system --create-namespace
```

---

### Configure MetalLB BGP Mode

Create `metallb-config.yaml`:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: cloudstack-pool
  namespace: metallb-system
spec:
  addresses:
  - 2a01:b000:1046:10:1::100-2a01:b000:1046:10:1::150  # Pool of 51 IPs
  autoAssign: true

---
apiVersion: metallb.io/v1beta2
kind: BGPAdvertisement
metadata:
  name: cloudstack-bgp
  namespace: metallb-system
spec:
  ipAddressPools:
  - cloudstack-pool
  aggregationLength: 128        # Advertise /128 host routes
  localPref: 100

---
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: cloudstack-vr
  namespace: metallb-system
spec:
  myASN: 65201                   # Must match node FRR ASN
  peerASN: 65101                 # VR ASN
  peerAddress: 2a01:b000:1046:10:1::1
```

**Apply Configuration:**
```bash
kubectl apply -f metallb-config.yaml
```

**Notes:**
- Each K8s node has different ASN (65201, 65202, 65203)
- MetalLB speaker on each node uses that node's ASN
- All speakers peer with VR at `2a01:b000:1046:10:1::1`

---

## Step 5: Deploy Test Service

### Create Nginx Deployment

```yaml
# nginx-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80

---
apiVersion: v1
kind: Service
metadata:
  name: nginx-loadbalancer
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
```

**Deploy:**
```bash
kubectl apply -f nginx-deployment.yaml
```

---

### Verify Service External IP

```bash
kubectl get svc nginx-loadbalancer
```

**Expected Output:**
```
NAME                 TYPE           CLUSTER-IP      EXTERNAL-IP                  PORT(S)        AGE
nginx-loadbalancer   LoadBalancer   10.96.100.50    2a01:b000:1046:10:1::100     80:30080/TCP   1m
```

**MetalLB allocated IP:** `2a01:b000:1046:10:1::100/128`

---

### Verify BGP Route Advertisement

**On any K8s node:**
```bash
sudo vtysh -c 'show bgp ipv6 unicast'
```

**Expected Output:**
```
   Network                      Next Hop            Metric LocPrf Weight Path
*> 2a01:b000:1046:10:1::100/128 ::                       0         32768 i
```

**In CloudStack:**
```bash
cloudmonkey list bgp guest routes state=Accepted
```

**Expected Response:**
```json
{
  "count": 1,
  "bgpguestroute": [
    {
      "prefix": "2a01:b000:1046:10:1::100/128",
      "state": "Accepted",
      "nexthop": "2a01:b000:1046:10:1::50"
    }
  ]
}
```

**VR automatically redistributes route to ISP!**

---

## Step 6: Test External Connectivity

### From External Internet

```bash
curl -v http://[2a01:b000:1046:10:1::100]
```

**Expected Response:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

✅ **Success!** Service is publicly accessible via BGP-advertised IP.

---

### Traffic Flow

```
External Client (IPv6 Internet)
      │
      │ curl http://[2a01:b000:1046:10:1::100]
      ▼
ISP Router (learned route via BGP)
      │
      │ Next hop: CloudStack VR
      ▼
Virtual Router (2a01:b000:1046:10:1::1)
      │
      │ Routing table: 2a01:b000:1046:10:1::100 via 2a01:b000:1046:10:1::50
      ▼
k8s-node-1 (2a01:b000:1046:10:1::50)
      │
      │ kube-proxy forwards to nginx pod
      ▼
Nginx Pod (10.244.1.5)
      │
      │ HTTP response
      ▼
(Return path: Pod → Node → VR → ISP → Client)
```

---

## Step 7: High Availability Test

### Deploy Second Service

```bash
kubectl expose deployment nginx --name=nginx-ha --type=LoadBalancer --port=8080
```

**MetalLB allocates:** `2a01:b000:1046:10:1::101/128`

---

### Verify Multiple Routes

```bash
cloudmonkey list bgp guest routes state=Accepted
```

**Expected:**
```json
{
  "count": 2,
  "bgpguestroute": [
    {"prefix": "2a01:b000:1046:10:1::100/128", "nexthop": "...::50"},
    {"prefix": "2a01:b000:1046:10:1::101/128", "nexthop": "...::51"}
  ]
}
```

**Both IPs externally reachable!**

---

### Simulate Node Failure

```bash
# On k8s-node-1:
sudo systemctl stop frr

# BGP session drops
# MetalLB speaker on node-1 stops advertising
# CloudStack detects session down
```

**Verify:**
```bash
cloudmonkey list bgp guest peering sessions virtualmachineid=<node-1-vm-id>
```

**Expected:**
```json
{"state": "Idle"}
```

**Route automatically withdrawn from VR!**

---

## Troubleshooting

### Issue: BGP Session Stuck in "Idle"

**Diagnosis:**
```bash
# On K8s node:
sudo vtysh -c 'show bgp ipv6 neighbors 2a01:b000:1046:10:1::1'
```

**Common Causes:**
1. **Wrong ASN:** Check node ASN matches CloudStack allowed range (65200-65299)
2. **Firewall blocking port 179:** Ensure VR allows TCP/179 from guest network
3. **Wrong VR IP:** Verify VR IP is `<network-cidr>::1`

**Solution:**
```bash
# Reconfigure FRR with correct ASN
sudo vtysh
configure terminal
no router bgp <old-asn>
router bgp 65201  # Use correct ASN
...
```

---

### Issue: Routes Rejected by VR

**Diagnosis:**
```bash
cloudmonkey list bgp guest routes state=Rejected
```

**Common Causes:**
1. **Prefix outside network CIDR:**
   - Advertising `2a01:b000:1046:20:1::100` but network is `2a01:b000:1046:10:1::/64`
   - **Solution:** Only advertise IPs within network CIDR

2. **Prefix length exceeds max:**
   - Advertising `/64` but network offering allows max `/128`
   - **Solution:** Use `/128` host routes

---

### Issue: External Connectivity Fails

**Diagnosis:**
1. **Verify route in VR:**
```bash
# SSH to VR
ssh root@<vr-ip>
ip -6 route show | grep 2a01:b000:1046:10:1::100
```

**Expected:**
```
2a01:b000:1046:10:1::100 via 2a01:b000:1046:10:1::50 dev eth1 proto bgp metric 20
```

2. **Verify route advertised to ISP:**
```bash
# On ISP router
show bgp ipv6 unicast neighbors <vr-ip> received-routes
```

**Solution:**
- If missing in VR: Check CloudStack route acceptance
- If missing at ISP: Check VR upstream BGP config

---

## Monitoring

### CloudStack Metrics

```bash
# Session uptime
cloudmonkey get bgp guest peering metrics id=<peer-id>

# Recent events
cloudmonkey list bgp guest peering events \
  peeringid=<peer-id> \
  startdate="2025-11-20T00:00:00Z"
```

---

### Kubernetes Metrics

```bash
# MetalLB speaker logs
kubectl logs -n metallb-system -l app=metallb,component=speaker

# Service status
kubectl get svc -o wide
```

---

## Cleanup

```bash
# Delete Kubernetes resources
kubectl delete svc nginx-loadbalancer nginx-ha
kubectl delete deployment nginx

# Stop FRR on nodes (optional)
sudo systemctl stop frr

# CloudStack automatically withdraws routes
# BGP sessions move to "Idle" state
```

---

## Summary

✅ **Achieved:**
- Kubernetes services with real IPv6 addresses
- Automatic failover (BGP route withdrawal on node failure)
- External Internet accessibility
- No manual route configuration (MetalLB handles everything)

**Key Benefits:**
- **No NAT:** Direct connectivity to pods
- **True Load Balancing:** Multiple paths via ECMP
- **Fast Failover:** <5 second convergence
- **Scalability:** 50 services per network (max-prefix limit)

---

## Next Steps

- **Production Hardening:**
  - Enable BGP MD5 authentication (CloudStack 4.24)
  - Configure VRRP for redundant VRs
  - Set up Prometheus monitoring

- **Advanced Features:**
  - BGP communities for traffic engineering
  - Prefix filtering per service
  - IPv4 dual-stack support

---

**Reference Files:**
- Network Offering: `K8s-Isolated-BGP`
- MetalLB Config: `metallb-config.yaml`
- Nginx Deployment: `nginx-deployment.yaml`

**Last Updated:** November 20, 2025
