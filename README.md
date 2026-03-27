# k8s-observability

> A production-grade Kubernetes observability stack deployed via Helm.
> Full metrics, logs, dashboards, and alerting — installed in minutes,
> monitoring everything from node CPU to individual pod restarts.

---

## Live Stack !

```
kubectl get pods -n monitoring

alertmanager-kube-prometheus-stack-alertmanager-0   2/2   Running   30m
kube-prometheus-stack-grafana-9748f5cd8-lz2xl       3/3   Running   35m
kube-prometheus-stack-kube-state-metrics            1/1   Running   35m
kube-prometheus-stack-operator                      1/1   Running   35m
kube-prometheus-stack-prometheus-node-exporter      1/1   Running   35m
loki-stack-0                                        1/1   Running   20m
loki-stack-promtail-gjmpp                           1/1   Running   20m
prometheus-kube-prometheus-stack-prometheus-0       2/2   Running   24m

Active Prometheus scrape targets: 14
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (kind)                     │
│                                                                  │
│  ┌─────────────┐    scrapes     ┌──────────────────────────┐   │
│  │  myapp pods │ ─────────────► │      Prometheus           │   │
│  │  /metrics   │                │  14 active targets        │   │
│  └─────────────┘                │  7d retention             │   │
│                                 └────────────┬─────────────┘   │
│  ┌─────────────┐                             │ queries          │
│  │    Node     │ ─── node-exporter ──────────┤                  │
│  │   metrics   │                             │                  │
│  └─────────────┘                             ▼                  │
│                                 ┌──────────────────────────┐   │
│  ┌─────────────┐    collects    │         Grafana           │   │
│  │  All pods   │ ── promtail ─► │  Loki datasource          │   │
│  │    logs     │                │  Prometheus datasource    │   │
│  └─────────────┘                │  Custom myapp dashboard   │   │
│                                 └──────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Alertmanager                                 │  │
│  │   MyAppPodRestarting · MyAppPodNotRunning · HighMemory   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## What This Project Demonstrates

- **Full observability stack** — metrics (Prometheus), logs (Loki), visualization (Grafana), alerting (Alertmanager) all wired together
- **Helm-based deployment** — entire stack installed and reproducible with two `helm install` commands
- **Custom application dashboard** — 6-panel Grafana dashboard built specifically for the myapp namespace: CPU, memory, restarts, pod count, CPU gauge, live logs
- **Alert rules as code** — 3 PrometheusRule CRDs covering pod restarts, pod availability, and memory usage
- **Log aggregation** — Promtail ships logs from every pod to Loki; queryable in Grafana alongside metrics
- **Real scrape targets** — 14 active targets including kubelet, apiserver, coredns, kube-state-metrics, node-exporter, and application pods

---

## Stack Details

| Component | Chart | Version | Purpose |
|-----------|-------|---------|---------|
| Prometheus | kube-prometheus-stack | 82.13.0 | Metrics collection + alerting rules |
| Grafana | kube-prometheus-stack | v0.89.0 | Dashboards + visualization |
| Alertmanager | kube-prometheus-stack | v0.89.0 | Alert routing + deduplication |
| Node Exporter | kube-prometheus-stack | v0.89.0 | Host-level CPU/memory/disk metrics |
| kube-state-metrics | kube-prometheus-stack | v0.89.0 | Kubernetes object metrics |
| Loki | loki-stack | 2.10.3 | Log aggregation + storage |
| Promtail | loki-stack | v2.9.3 | Log collection from all pods |

---

## Custom myapp Dashboard

A purpose-built Grafana dashboard monitoring the myapp namespace from Project 1
([gitops-cicd-pipeline](https://github.com/irfanjat/gitops-cicd-pipeline)).

### 6 panels

| Panel | Type | Query |
|-------|------|-------|
| Pod CPU Usage | Time series | `rate(container_cpu_usage_seconds_total{namespace="myapp"}[5m])` |
| Pod Memory Usage | Time series | `container_memory_working_set_bytes{namespace="myapp"}` |
| Pod Restarts | Stat | `kube_pod_container_status_restarts_total{namespace="myapp"}` |
| Running Pods | Stat | `kube_pod_status_phase{namespace="myapp", phase="Running"}` |
| Node CPU | Gauge | `100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))` |
| Pod Logs | Logs | `{namespace="myapp"}` via Loki |

The logs panel streams live `/health` probe hits and application output from both pods directly into Grafana — no `kubectl logs` needed.

---

## Alert Rules

Three `PrometheusRule` CRDs defined in `alert-rules.yaml`:

### MyAppPodRestarting
```yaml
expr: sum(kube_pod_container_status_restarts_total{namespace="myapp"}) > 0
for: 1m
severity: warning
```
Fires if any myapp pod has restarted. Zero restarts = healthy deployment.

### MyAppPodNotRunning
```yaml
expr: count(kube_pod_status_phase{namespace="myapp", phase="Running"}) < 2
for: 1m
severity: critical
```
Fires if fewer than 2 pods are running. Covers pod crashes, OOM kills, and failed deployments.

### HighMemoryUsage
```yaml
expr: sum(container_memory_working_set_bytes{namespace="myapp", container!=""}) > 100000000
for: 2m
severity: warning
```
Fires if total myapp memory exceeds 100MB. Catches memory leaks before they cause OOM kills.

**Current state: all 3 alerts `inactive`** — myapp is healthy, 0 restarts, 2 pods running.

---

## Quick Start

### Prerequisites
- Kubernetes cluster (kind, minikube, or cloud)
- Helm 3+
- kubectl configured

### Deploy everything

```bash
# Clone the repo
git clone https://github.com/irfanjat/k8s-observability.git
cd k8s-observability

# Run the setup script — installs full stack
chmod +x setup.sh
./setup.sh
```

### Access Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana \
  -n monitoring 3000:80 &

# Open http://localhost:3000
# Username: admin
# Password: admin123
```

### Access Prometheus UI

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus \
  -n monitoring 9090:9090 &

# Open http://localhost:9090
```

### Check alert rules

```bash
# See all rules and their state
curl -s http://localhost:9090/api/v1/rules | \
  python3 -c "
import json,sys
data=json.load(sys.stdin)
for g in data['data']['groups']:
    if 'myapp' in g['name']:
        for r in g['rules']:
            print(f'{r[\"name\"]} — {r[\"state\"]}')
"
```

---

## Repository Structure

```
k8s-observability/
├── alert-rules.yaml      ← PrometheusRule CRDs — 3 alert rules for myapp
├── dashboard-myapp.json  ← Custom Grafana dashboard metadata
├── setup.sh              ← One-script full stack deployment
└── README.md
```

---

## Prometheus Scrape Targets (14 active)

```
kube-prometheus-stack-alertmanager
apiserver
coredns
kube-prometheus-stack-grafana
kube-state-metrics
kubelet
node-exporter
prometheus-operator
prometheus
```

All targets `UP` — no scrape failures.

---

## Key Design Decisions

### Why kube-prometheus-stack instead of individual installs?
The Helm chart installs Prometheus, Grafana, Alertmanager, Node Exporter, and kube-state-metrics together with pre-configured integrations, service monitors, and default Kubernetes dashboards. Installing them individually would require manually wiring data sources, scrape configs, and dashboard imports — the stack does this automatically and correctly.

### Why Loki for logs instead of Elasticsearch?
Loki is designed for Kubernetes — it indexes only labels (namespace, pod, container) and stores raw log text compressed. This makes it dramatically cheaper to run than Elasticsearch on a local cluster. It also integrates natively with Grafana, so metrics and logs appear in the same dashboard without switching tools.

### Why PrometheusRule CRDs instead of config files?
PrometheusRule is a Kubernetes Custom Resource — it lives in the cluster as a native object. The Prometheus Operator watches for PrometheusRule resources and automatically reloads Prometheus config when they change. No restarts, no manual config editing, no SSH into pods. Alert rules are version-controlled like any other Kubernetes manifest.

### Why alert on pod count < 2 specifically?
The myapp deployment specifies `replicas: 2`. Alerting on `< 2` means any disruption — crash, OOM kill, failed rolling update — fires immediately. It's tighter than generic "pod not running" alerts because it's calibrated to the specific availability requirement of this application.

---

## What I Would Add Next

- **Slack integration** — Alertmanager webhook to fire Slack messages on critical alerts
- **Custom recording rules** — pre-compute expensive queries so dashboards load faster
- **Persistent storage** — PersistentVolumeClaim for Prometheus and Loki so data survives pod restarts
- **Grafana provisioning** — define dashboards and data sources as ConfigMaps so they persist after Grafana restarts
- **SLO dashboard** — track error rate and latency against defined service level objectives
- **Horizontal Pod Autoscaler alerts** — alert when ASG is at max capacity

---

## Related Projects

| Repo | Purpose |
|------|---------|
| [gitops-cicd-pipeline](https://github.com/irfanjat/gitops-cicd-pipeline) | The app being monitored — GitOps CI/CD with GitHub Actions + ArgoCD |
| [terraform-aws-infra](https://github.com/irfanjat/terraform-aws-infra) | AWS infrastructure provisioned with Terraform modules |
| **k8s-observability** (this repo) | Full observability stack — metrics, logs, dashboards, alerts |

---

## Author

**Irfan Ali** — CS student building production-grade DevOps infrastructure.

[![GitHub](https://img.shields.io/badge/GitHub-irfanjat-181717?logo=github)](https://github.com/irfanjat)
[![Project 1](https://img.shields.io/badge/Project_1-GitOps_Pipeline-185FA5?logo=github)](https://github.com/irfanjat/gitops-cicd-pipeline)
[![Project 2](https://img.shields.io/badge/Project_2-Terraform_AWS-7B42BC?logo=github)](https://github.com/irfanjat/terraform-aws-infra)
