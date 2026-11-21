# Quay Registry Setup

Perform this one-time setup before deploying any component. It creates the organizations, repositories, and robot accounts used by the deployment guides.

## Step 1 — Create Organizations and Repositories

Log in to Quay Enterprise and create the following structure:

| Organization | Repositories |
|---|---|
| `argoproj` | `argocd`, `redis` |
| `byop` | `byop-broker`, `byop-catalog-app`, `mariadb`, `mongo` |
| `gitea` | `gitea`, `postgres`, `redis` |

For each organization: **Create New Organization** → navigate into it → **Create New Repository** for each entry above.

## Step 2 — Create Robot Accounts

For each organization, create one robot account with write access to all repositories in that organization:

| Organization | Robot name | Login username |
|---|---|---|
| `argoproj` | `argocd_push` | `argoproj+argocd_push` |
| `byop` | `byop_push` | `byop+byop_push` |
| `gitea` | `gitea_push` | `gitea+gitea_push` |

For each robot account: **Robot Accounts** in the left sidebar → **Create Robot Account** → enter the name → grant **Write** to all repositories in that organization → save the generated token.

> Store each token securely. You will need them when following the ArgoCD, Gitea, and BYOP Broker deployment guides.

---
*Made with IBM Bob*
