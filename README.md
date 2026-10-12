# Sistema de Gestão de Ginásio

Script PostgreSQL com CHECK constraints e views de segurança, e ambiente Docker para o testar.

## Testes automatizados

```powershell
.\run_tests.ps1
```

Sobe o Docker, recarrega [gestao_ginasio.sql](gestao_ginasio.sql) e executa [testes_ginasio.sql](testes_ginasio.sql) (20 verificações: constraints, view e permissões). Os testes correm numa transação revertida e o script devolve código de saída 0 (sucesso) ou 1 (falha).

## Ambiente de teste (Docker)

```powershell
# Subir o PostgreSQL
docker compose up -d --wait

# Executar o script (o erro do INSERT inválido é propositado)
docker exec ginasio_postgres psql -U ginasio_admin -d ginasio -f /scripts/gestao_ginasio.sql

# Consola interativa
docker exec -it ginasio_postgres psql -U ginasio_admin -d ginasio

# Parar (mantém os dados) / parar e apagar dados
docker compose down
docker compose down -v
```

Ligação externa (DBeaver, pgAdmin, ...): `localhost:5432`, base `ginasio`, utilizador `ginasio_admin`, password `ginasio_pass`.
