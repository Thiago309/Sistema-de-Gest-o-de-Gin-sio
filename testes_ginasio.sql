-- =====================================================================
-- Testes automatizados - Sistema de Gestão de Ginásio
-- Pré-requisito: gestao_ginasio.sql já executado (dados de teste carregados).
-- Executar com ON_ERROR_STOP=1: termina com erro se algum teste falhar.
-- Tudo corre numa transação que é revertida no fim (não suja a base).
-- =====================================================================
\set ON_ERROR_STOP on
\pset pager off

BEGIN;

CREATE TEMP TABLE resultados (
    id     SERIAL PRIMARY KEY,
    teste  TEXT    NOT NULL,
    passou BOOLEAN NOT NULL
);

-- Regista o resultado de uma verificação booleana
CREATE FUNCTION pg_temp.verificar(p_teste TEXT, p_ok BOOLEAN) RETURNS VOID AS $$
    INSERT INTO resultados (teste, passou) VALUES (p_teste, COALESCE(p_ok, FALSE));
$$ LANGUAGE sql;

-- Executa um comando (opcionalmente como outro role) e verifica que falha
-- com o SQLSTATE esperado (ou um de vários, separados por vírgula).
-- Se o comando for aceite, o teste falha.
CREATE FUNCTION pg_temp.espera_erro(p_teste TEXT, p_sql TEXT,
                                    p_sqlstate TEXT, p_role TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    IF p_role IS NOT NULL THEN
        EXECUTE format('SET LOCAL ROLE %I', p_role);
    END IF;
    EXECUTE p_sql;
    RESET ROLE;
    INSERT INTO resultados (teste, passou) VALUES (p_teste, FALSE);  -- foi aceite: falha
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    INSERT INTO resultados (teste, passou)
    VALUES (p_teste, SQLSTATE = ANY (string_to_array(p_sqlstate, ',')));
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- A. CHECK CONSTRAINT percentagem_gordura (2.0 a 60.0)
-- ---------------------------------------------------------------------
\o /dev/null
SELECT pg_temp.espera_erro('A1 rejeita gordura = -5.0',
    $q$INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
       VALUES (4, '2030-01-01', 75, 1.78, -5.0)$q$, '23514');
SELECT pg_temp.espera_erro('A2 rejeita gordura = 1.9 (abaixo do mínimo)',
    $q$INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
       VALUES (4, '2030-01-02', 75, 1.78, 1.9)$q$, '23514');
SELECT pg_temp.espera_erro('A3 rejeita gordura = 60.1 (acima do máximo)',
    $q$INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
       VALUES (4, '2030-01-03', 75, 1.78, 60.1)$q$, '23514');
SELECT pg_temp.espera_erro('A4 rejeita gordura = 0',
    $q$INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
       VALUES (4, '2030-01-04', 75, 1.78, 0)$q$, '23514');

INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
VALUES (4, '2030-02-01', 75, 1.78, 2.0), (4, '2030-02-02', 75, 1.78, 60.0),
       (4, '2030-02-03', 75, 1.78, 15.5);
SELECT pg_temp.verificar('A5 aceita limites 2.0 e 60.0 e valor intermédio 15.5',
    (SELECT COUNT(*) = 3 FROM avaliacoes_fisicas
      WHERE id_aluno = 4 AND data_avaliacao BETWEEN '2030-02-01' AND '2030-02-03'));

SELECT pg_temp.verificar('A6 nenhuma linha inválida na tabela',
    NOT EXISTS (SELECT 1 FROM avaliacoes_fisicas
                 WHERE percentagem_gordura NOT BETWEEN 2.0 AND 60.0));

-- ---------------------------------------------------------------------
-- B. Constraints complementares
-- ---------------------------------------------------------------------
SELECT pg_temp.espera_erro('B1 rejeita peso <= 0',
    $q$INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
       VALUES (1, '2031-01-01', 0, 1.70, 20)$q$, '23514');
SELECT pg_temp.espera_erro('B2 rejeita altura fora de 0.50-2.50 m',
    $q$INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
       VALUES (1, '2031-01-02', 70, 3.00, 20)$q$, '23514');
SELECT pg_temp.espera_erro('B3 rejeita avaliação duplicada no mesmo dia',
    $q$INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
       VALUES (1, '2025-01-20', 70, 1.70, 20)$q$, '23505');
SELECT pg_temp.espera_erro('B4 rejeita avaliação de aluno inexistente (FK)',
    $q$INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
       VALUES (9999, '2031-01-03', 70, 1.70, 20)$q$, '23503');

-- ---------------------------------------------------------------------
-- C. VIEW view_instrutores_musculacao (máscara de dados)
-- ---------------------------------------------------------------------
SELECT pg_temp.verificar('C1 view tem exatamente as 4 colunas esperadas',
    (SELECT array_agg(column_name::TEXT ORDER BY ordinal_position)
       FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'view_instrutores_musculacao')
    = ARRAY['nome_aluno','data_ultima_avaliacao','objetivo_principal','percentagem_gordura_atual']);

SELECT pg_temp.verificar('C2 view NÃO expõe morada, telefone nem cartão',
    NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public'
                   AND table_name = 'view_instrutores_musculacao'
                   AND column_name IN ('morada','telefone','dados_cartao_credito')));

SELECT pg_temp.verificar('C3 view devolve 1 linha por aluno',
    (SELECT COUNT(*) FROM view_instrutores_musculacao) = (SELECT COUNT(*) FROM alunos));

SELECT pg_temp.verificar('C4 view mostra a avaliação MAIS RECENTE (Ana: 2025-07-18 / 27.8)',
    EXISTS (SELECT 1 FROM view_instrutores_musculacao
             WHERE nome_aluno = 'Ana Ferreira'
               AND data_ultima_avaliacao = DATE '2025-07-18'
               AND percentagem_gordura_atual = 27.8));

INSERT INTO alunos (nome, objetivo_principal) VALUES ('Aluno Sem Avaliacao', 'Teste');
SELECT pg_temp.verificar('C5 aluno sem avaliações aparece com data e % gordura NULL',
    EXISTS (SELECT 1 FROM view_instrutores_musculacao
             WHERE nome_aluno = 'Aluno Sem Avaliacao'
               AND data_ultima_avaliacao IS NULL
               AND percentagem_gordura_atual IS NULL));

-- ---------------------------------------------------------------------
-- D. Segurança de acesso do perfil instrutor_musculacao
-- ---------------------------------------------------------------------
SELECT pg_temp.espera_erro('D1 instrutor NÃO lê a tabela alunos',
    'SELECT morada, telefone, dados_cartao_credito FROM alunos', '42501', 'instrutor_musculacao');
SELECT pg_temp.espera_erro('D2 instrutor NÃO lê a tabela avaliacoes_fisicas',
    'SELECT * FROM avaliacoes_fisicas', '42501', 'instrutor_musculacao');
SELECT pg_temp.espera_erro('D3 instrutor NÃO escreve na tabela alunos',
    $q$UPDATE alunos SET nome = 'x'$q$, '42501', 'instrutor_musculacao');
SELECT pg_temp.espera_erro('D4 instrutor NÃO escreve na view',
    -- 42501 = sem permissão; 55000 = view não atualizável. Ambos bloqueiam a escrita.
    $q$DELETE FROM view_instrutores_musculacao$q$, '42501,55000', 'instrutor_musculacao');

-- D5: instrutor consegue ler a view (executa e confirma que devolve linhas)
CREATE FUNCTION pg_temp.instrutor_le_view() RETURNS BOOLEAN AS $$
DECLARE n INT;
BEGIN
    SET LOCAL ROLE instrutor_musculacao;
    SELECT COUNT(*) INTO n FROM view_instrutores_musculacao;
    RESET ROLE;
    RETURN n > 0;
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;
SELECT pg_temp.verificar('D5 instrutor CONSEGUE ler a view', pg_temp.instrutor_le_view());

-- ---------------------------------------------------------------------
-- RELATÓRIO
-- ---------------------------------------------------------------------
\o
SELECT teste AS "Teste",
       CASE WHEN passou THEN 'PASSOU' ELSE 'FALHOU' END AS "Resultado"
FROM resultados ORDER BY id;

SELECT COUNT(*) FILTER (WHERE passou)     AS passaram,
       COUNT(*) FILTER (WHERE NOT passou) AS falharam,
       COUNT(*)                           AS total
FROM resultados;

-- Termina com erro (código de saída ≠ 0) se algum teste falhou
DO $$
DECLARE n_falhas INT;
BEGIN
    SELECT COUNT(*) INTO n_falhas FROM resultados WHERE NOT passou;
    IF n_falhas > 0 THEN
        RAISE EXCEPTION '% teste(s) falharam', n_falhas;
    END IF;
END
$$;

ROLLBACK;
