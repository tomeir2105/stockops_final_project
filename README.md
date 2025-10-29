# StockOps
StockOps is a modular, self-hosted platform for collecting, processing, and visualizing stock data, designed to run efficiently on a Raspberry Pi cluster. It automates data ingestion and real-time analytics while providing clear observability through built-in monitoring and dashboards. With containerized services and reproducible setups, StockOps makes it easy to deploy, track, and manage your data pipelines — giving you full control over your infrastructure without the complexity
---

## Table of Contents
- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Main Components](#main-components)
- [Router Node (k3srouter)](#router-node-k3srouter)
- [Installation](#installation)
- [Required Libraries](#required-libraries)
- [Challenges & Lessons Learned](#challenges--lessons-learned)
- [Usage](#usage)
- [Future Directions](#future-directions)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

**stockops** is a fully automated DevOps and data-operations system that integrates:
- **Data ingestion** (Python fetchers for stocks and news),
- **Observability** (InfluxDB + Grafana dashboards),
- **Automation and CI/CD** (Jenkins and Ansible),
- **Orchestration** (K3s Kubernetes cluster),
- **Storage and persistence** (NFS-based shared storage).

All modules are deployed in a distributed Raspberry Pi environment.  
The project demonstrates how real-world automation and analytics can be implemented on low-power hardware using professional-grade tools.

---

## System Architecture

```
                 ┌─────────────────────────┐
                 │ Raspberry Pi Cluster    │
                 │ (k3srouter, k3s1, ...)  │
                 └─────────────────────────┘
                             │
           ┌─────────────────┴─────────────────┐
           │                                   │
    ┌──────────────┐                    ┌──────────────┐
    │ Jenkins CI   │                    │ NFS Storage  │
    │ Builds, Push │                    │ /mnt/k3s_... │
    └──────────────┘                    └──────────────┘
           │                                   │
    ┌──────────────┐                    ┌──────────────┐
    │ Grafana      │◄──────InfluxDB────►│ Stocks Data  │
    │ Visualization│                    │ Metrics/Logs │
    └──────────────┘                    └──────────────┘
           │
    ┌──────────────┐
    │ Fetchers     │──►  API Feeds
    │ News/Stocks  │
    └──────────────┘
```

Every component runs inside Kubernetes, with persistent storage mounted from a shared **NFS** volume exported by the router node.  
The cluster is fully managed via **Ansible** playbooks that configure NFS, deploy pods, verify mounts, and push/pull Docker images.

---

## Main Components

| Component | Description |
|------------|-------------|
| **Jenkins** | Handles CI/CD pipelines — building, pushing, and deploying Docker images. |
| **Grafana** | Provides live dashboards for system and stock metrics. |
| **InfluxDB** | Time-series database used by fetchers and Grafana. |
| **stocks** | Python app that fetches stock market data and publishes to InfluxDB. |
| **news** | Python app that retrieves financial news data for correlation and sentiment tracking. |
| **feed.yaml** | Central configuration file that defines which fetchers run, their intervals, and targets. |
| **NFS Storage** | Shared persistent storage across all pods (`/mnt/k3s_storage`). Stores Jenkins, Grafana, and InfluxDB data volumes. |

---

## Router Node (k3srouter)

The **k3srouter** is the backbone of the stockops cluster.  
It acts as:
- The **cluster controller** (primary K3s server),
- The **NFS file server** for shared storage,
- The **Ansible control node** (from which all playbooks are executed),
- The **local registry and GitHub bridge** for automation.

### Responsibilities
1. **Network Coordination**
   Routes all inter-node traffic and ensures pods can communicate securely within the 192.168.50.0/24 LAN.

2. **NFS Storage Management**
   Exports `/mnt/k3s_storage` to all cluster nodes with `root_squash` for safe write permissions.

3. **Inventory & Ansible Host**
   Hosts the `inventory.ini` and all playbooks. Runs all provisioning and verification tasks.

4. **GitHub and Docker Hub Integration**
   Maintains SSH keys and credentials for automated GitHub cloning and Docker Hub pushes.

5. **Gateway Services**
   Optionally provides Wi-Fi hotspot or DHCP/DNS for isolated lab setups.

### Installation (Router Node)

1. **Base System Setup**
   ```bash
   sudo apt update && sudo apt install -y python3 python3-venv git ansible nfs-kernel-server docker-ce
   ```

2. **Clone the Project**
   ```bash
   git clone git@github.com:tomeir2105/stockops.git
   cd stockops
   ```

3. **Prepare NFS Storage**
   ```bash
   sudo mkdir -p /mnt/k3s_storage
   sudo chown -R $(whoami):$(whoami) /mnt/k3s_storage
   echo "/mnt/k3s_storage 192.168.50.0/24(rw,sync,no_subtree_check,no_root_squash)" |      sudo tee /etc/exports.d/k3s.exports
   sudo exportfs -rav
   ```

4. **Initialize K3s Server**
   ```bash
   curl -sfL https://get.k3s.io | sh -
   sudo systemctl enable k3s
   sudo systemctl status k3s
   ```

5. **Distribute K3s Token and Join Nodes**
   ```bash
   sudo cat /var/lib/rancher/k3s/server/node-token
   ```

6. **Run Verification Playbook**
   ```bash
   ansible-playbook -i inventory.ini check-cluster-nfs-ssh.yml
   ```

---

## Installation (Full Cluster)

1. **Clone Repository**
   ```bash
   git clone git@github.com:tomeir2105/stockops.git
   cd stockops
   ```

2. **Install Python Requirements**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

3. **Edit Variable Files**
   ```yaml
   NFS_SERVER_IP: 192.168.50.1
   NFS_BASE_PATH: /mnt/k3s_storage
   NFS_MOUNT_POINT: /mnt/k3s
   DOCKERHUB_USER: meir25
   NAMESPACE: stockops
   ```

4. **Deploy in Stages**
   ```bash
   ansible-playbook -i inventory.ini stage1_environment/setup-ssh-nfs.yml
   ansible-playbook -i inventory.ini stage2_k3s/install.yml
   ansible-playbook -i inventory.ini stage3_jenkins/deploy-jenkins.yml
   ansible-playbook -i inventory.ini stage4_grafana-influxdb.yml
   ```

5. **Verify Cluster State**
   ```bash
   kubectl get pods -A
   kubectl get pv,pvc -A
   ```

---

## Required Libraries

### Python
| Library | Purpose |
|----------|----------|
| **requests** | Fetch API data for market and news. |
| **pandas** | Transform and prepare data before inserting into InfluxDB. |
| **influxdb-client** | Write and query time-series data. |
| **PyYAML** | Parse and manage configuration files (`feed.yaml`, `vars.yml`). |
| **schedule / apscheduler** | Run periodic tasks for data fetching. |
| **rich / logging** | Structured logging and colorful console output. |

### Ansible Collections
| Collection | Role |
|-------------|------|
| `community.docker` | Docker image and container management. |
| `kubernetes.core` | Apply Kubernetes manifests and verify resources. |
| `ansible.posix` | Manage file systems and NFS mounts. |

### System Packages
| Package | Role |
|----------|------|
| `docker-ce` | Container runtime for apps. |
| `nfs-kernel-server` | Provides shared storage between cluster nodes. |
| `k3s` | Lightweight Kubernetes orchestrator. |
| `git` | Source control integration with GitHub. |
| `skopeo` | Transfer container images between registries. |

---

## Challenges & Lessons Learned

**1. Multi-Node ARM Cluster Management**
Running a full CI/CD system on Raspberry Pi hardware required ARM64-compatible images and custom Docker builds.

**2. NFS Synchronization and Permissions**
Ensuring writable persistent volumes across users and pods involved experimenting with `root_squash`, fsid consistency, and Ansible idempotency checks.

**3. Jenkins-Agent Communication**
Establishing key-based SSH connections between master and agent containers had to be automated and verified with Ansible.

**4. Orchestration Reliability**
All Ansible playbooks were built to be idempotent — they can be re-run safely without changing cluster state unexpectedly.

**5. Real-Time Data Feeds**
Python fetchers needed robust retry logic, batching, and efficient InfluxDB writes to handle network hiccups and rate limits.

**6. Monitoring and Observability**
Grafana and InfluxDB provided a continuous insight loop — confirming system health and timing for each fetcher in real time.

---

## Usage

### Deploy or Update Services
```bash
ansible-playbook -i inventory.ini update_hub/push-images.yml
ansible-playbook -i inventory.ini stage3_jenkins/deploy-jenkins.yml
```

### Add a New Fetcher
1. Create a folder under `fetchers/` (e.g., `crypto/`).
2. Add configuration to `feed.yaml`:
   ```yaml
   - name: crypto
     interval: 60
     endpoint: https://api.coincap.io/v2/assets
   ```
3. Redeploy:
   ```bash
   ansible-playbook -i inventory.ini deploy-fetchers.yml
   ```

---

## Future Directions

- Integrate **Redis** for caching and data queuing.  
- Add **mobile or Firebase app** for live dashboards.  
- Create a **web-based control panel** for fetcher management.  
- Automate image builds via Jenkins pipelines.  
- Expand fetchers to handle crypto, forex, and ETFs.  
- Implement **alerting system** for data anomalies or service failures.  

---

## Contributing

1. Fork the repository.  
2. Create a feature branch:  
   ```bash
   git checkout -b feature/my-feature
   ```  
3. Commit and push changes.  
4. Open a Pull Request.

Please follow the existing Ansible structure and keep roles modular and idempotent.

---

## License

This project is licensed under the **MIT License**.

---

## Author

**Meir A. (tomeir2105)**  
Built with dedication, patience, and curiosity — to make DevOps, automation, and data analytics accessible on low-cost hardware.

