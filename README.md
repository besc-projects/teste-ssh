# ssh-teste-deploy-py

CRUD simples (FastAPI + SQLite, gerenciado com `uv`) para testar um pipeline de deploy:
push no GitHub → GitHub Actions → SSH numa máquina Windows → `git pull` + restart do serviço na porta 9577.

## Rodar localmente

```bash
uv sync
uv run uvicorn main:app --reload
```

Endpoints: `GET/POST /items`, `GET/PUT/DELETE /items/{id}`, `GET /health`.

## Deploy automático

O workflow [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) roda a cada push em `main`:

1. Conecta via SSH na máquina Windows (`SSH_HOST:SSH_PORT`).
2. Executa [`deploy/deploy.ps1`](deploy/deploy.ps1), que:
   - clona o repo em `C:\Users\cloud\project-ssh-py-api` (ou dá `git fetch` + `reset --hard origin/main` se já existir);
   - instala o `uv` na máquina se não estiver presente;
   - roda `uv sync`;
   - mata o processo que estiver escutando na porta 9577 (deploy anterior);
   - sobe a aplicação em background (`uv run uvicorn main:app --port 9577`), com logs em `app.out.log` / `app.err.log`.

### Secrets necessários (Settings → Secrets and variables → Actions)

| Secret | Valor |
|---|---|
| `SSH_HOST` | `besc-orders-api.defenseti.com.br` |
| `SSH_PORT` | `9585` |
| `SSH_USERNAME` | `cloud` |
| `SSH_PASSWORD` | senha do usuário `cloud` |
| `GH_PAT` | Personal Access Token com escopo `repo` (necessário só se o repositório for privado, para o `git clone`/`git fetch` na máquina Windows) |

Nenhuma credencial fica no código — tudo vem de secrets injetados em tempo de execução.
