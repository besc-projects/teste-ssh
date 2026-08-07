# ssh-teste-deploy-py

CRUD simples (FastAPI + SQLite, gerenciado com `uv`) usado para testar estratégias de deploy
numa máquina Windows atrás de firewall restritivo. A aplicação roda na porta **9577**.

## Rodar localmente

```bash
uv sync
uv run uvicorn main:app --reload
```

Endpoints: `GET/POST /items`, `GET/PUT/DELETE /items/{id}`, `GET /health`.

## Restrição de rede da máquina de destino

A máquina alvo tem uma allowlist de saída que libera só parte do GitHub:

| Host | Status |
|---|---|
| `github.com`, `api.github.com`, `codeload.github.com` | acessível (intermitente) |
| `objects.githubusercontent.com`, `vstoken.actions.githubusercontent.com` | acessível |
| `pipelines*.actions.githubusercontent.com` | **bloqueado** (timeout) |

Também não aceita conexão SSH de entrada vinda dos runners hospedados do GitHub.

Consequências:

- **Deploy via SSH a partir de runner hospedado**: inviável — o runner não alcança a máquina.
- **Runner self-hosted**: inviável enquanto `*.actions.githubusercontent.com` estiver bloqueado —
  o runner registra, mas nunca recebe job.
- **Polling** (estratégia atual): funciona, porque só depende de `github.com` / `codeload.github.com`
  e tolera a instabilidade via retry a cada ciclo.

## Deploy por polling (estratégia ativa)

Uma tarefa agendada roda [`deploy/poll-deploy.ps1`](deploy/poll-deploy.ps1) a cada 5 minutos:

1. `git fetch` no repositório; se o `HEAD` local já é igual ao `origin/main`, encerra sem fazer nada.
2. Havendo commit novo, `git reset --hard origin/main` e chama
   [`deploy/restart-service.ps1`](deploy/restart-service.ps1), que sincroniza deps com `uv sync`,
   derruba o processo na porta 9577 e sobe a nova versão.
3. Tudo é registrado em `poll-deploy.log`, ao lado da pasta da aplicação.

Se a rede estiver fora no momento do ciclo, o `git fetch` falha, o script sai com erro e a
próxima execução (5 min depois) tenta de novo — sem intervenção.

### Instalação (uma vez, PowerShell como Administrador)

```powershell
./deploy/install-scheduled-task.ps1
```

A tarefa roda como `supra\cloud` em modo S4U, ou seja, funciona mesmo sem sessão interativa aberta
e sem armazenar senha.

## Deploy via GitHub Actions (bloqueado hoje)

O workflow [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) está pronto para um runner
self-hosted e passa a funcionar assim que a rede liberar saída na 443 para
`*.actions.githubusercontent.com`. Enquanto isso, ele não tem runner disponível e fica na fila.
