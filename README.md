## Multi-Cloud Infrastructure-as-Code Portfolio (`multicloud-iac-100`)

A 100-project, flat-monorepo engineering portfolio demonstrating **Google Cloud Platform (GCP)** and **Microsoft Azure** architectural parity using **Terraform**, **Python**, **GitHub Actions CI/CD**, and **keyless OIDC authentication**.

## Engineering Standards

* **Zero Long-Lived Secrets:** All deployments authenticate via Workload Identity Federation (GCP) and Entra ID Federated Credentials (Azure).
* **Isolated Remote State:** Every project maintains dedicated Terraform state paths inside versioned remote backends (`gs://tfstate-shared-dami-akinbi` and `sttfstatedamiakinbi/tfstate`).
* **Scale-to-Zero Economics:** Serverless and consumption SKUs ensure idle cloud spend remains `$0.00`, backed by automated smoke-test and teardown workflows.
* **Remote Container Builds:** Container images build directly in Google Cloud Build (`gcloud builds submit`) and Azure Container Registry (`az acr build`) with zero local Docker daemon dependencies.

---

## Project Catalog

### Tier 1: Simple & Serverless Foundations
| # | Project | GCP Stack | Azure Stack | Status |
| :--- | :--- | :--- | :--- | :--- |
| **001** | [URL Shortener & Edge Analytics](./projects/001-multicloud-url-shortener) | Cloud Run + Firestore + BigQuery | Container Apps + Cosmos DB + Log Analytics | Ready (Live Demo) |
| **002** | Event-Driven Webhook Processor | Cloud Run + Pub/Sub + Firestore | Container Apps + Service Bus + Cosmos DB | Planned |
| **003** | Automated Media & PDF Pipeline | Cloud Storage + Eventarc + Cloud Run Jobs | Blob Storage + Event Grid + Container Apps Jobs | Planned |
| **004** | Ephemeral PR Preview Environments | Cloud Run Revisions + Artifact Registry + Cloud Build | Container Apps Revisions + ACR (`az acr build`) | Planned |

### Tier 2: Intermediate — Networking, Data & Event Streaming
| # | Project | GCP Stack | Azure Stack | Status |
| :--- | :--- | :--- | :--- | :--- |
| **005+** | *Expanding progressively after live verification of Tier 1* | VPC, Cloud SQL, GKE, Cloud Armor | VNet, Azure SQL, AKS, Front Door WAF | Planned |

### Tier 3: Advanced — Platform Engineering, Zero-Trust & MLOps
| # | Project | GCP Stack | Azure Stack | Status |
| :--- | :--- | :--- | :--- | :--- |
| **051+** | *Expanding progressively across security, FinOps & AI inference* | Vertex AI, VPC Service Controls, Anthos/Fleet | Azure OpenAI, Private Link, Sentinel/Defender | Planned |
