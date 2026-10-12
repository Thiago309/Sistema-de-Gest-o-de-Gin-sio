# Sistema de Gestão de Ginásio

Script PostgreSQL com CHECK constraints e views de segurança, e ambiente Docker para o testar.

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
