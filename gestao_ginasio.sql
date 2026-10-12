-- =====================================================================
-- Sistema de Gestão de Ginásio - PostgreSQL
-- Foco: segurança e integridade de dados (CHECK Constraints e Views)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Limpeza (permite re-executar o script)
-- ---------------------------------------------------------------------
DROP VIEW  IF EXISTS view_instrutores_musculacao;
DROP TABLE IF EXISTS avaliacoes_fisicas;
DROP TABLE IF EXISTS alunos;

-- ---------------------------------------------------------------------
-- 1. TABELAS PRINCIPAIS
-- ---------------------------------------------------------------------
CREATE TABLE alunos (
    id                   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome                 VARCHAR(120) NOT NULL,
    morada               VARCHAR(255),
    telefone             VARCHAR(20),
    -- Dado sensível. Em produção NUNCA guardar o PAN em claro (PCI-DSS):
    -- usar token do gateway de pagamento ou cifrar (ex.: pgcrypto).
    dados_cartao_credito VARCHAR(255),
    objetivo_principal   VARCHAR(100),
    data_matricula       DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE avaliacoes_fisicas (
    id                  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_aluno            INTEGER NOT NULL
                        REFERENCES alunos (id) ON DELETE CASCADE,
    data_avaliacao      DATE NOT NULL DEFAULT CURRENT_DATE,
    peso                NUMERIC(5,2) NOT NULL,   -- kg
    altura              NUMERIC(3,2) NOT NULL,   -- metros
    percentagem_gordura NUMERIC(4,1) NOT NULL,

    -- -----------------------------------------------------------------
    -- REQUISITO 1: CHECK CONSTRAINT (segurança na inserção)
    -- Só aceita percentagem de gordura entre 2.0 e 60.0
    -- -----------------------------------------------------------------
    CONSTRAINT ck_percentagem_gordura_valida
        CHECK (percentagem_gordura BETWEEN 2.0 AND 60.0),

    -- Regras de integridade complementares
    CONSTRAINT ck_peso_positivo   CHECK (peso > 0),
    CONSTRAINT ck_altura_valida   CHECK (altura BETWEEN 0.50 AND 2.50),

    -- Um aluno não pode ter duas avaliações no mesmo dia
    CONSTRAINT uq_aluno_data UNIQUE (id_aluno, data_avaliacao)
);

CREATE INDEX idx_avaliacoes_aluno_data
    ON avaliacoes_fisicas (id_aluno, data_avaliacao DESC);

-- ---------------------------------------------------------------------
-- 2. REQUISITO 2: VIEW (segurança no acesso)
-- Expõe apenas: nome, data da última avaliação, objetivo principal e
-- percentagem de gordura atual. Morada, telefone e dados do cartão
-- NÃO fazem parte da view.
-- ---------------------------------------------------------------------
CREATE VIEW view_instrutores_musculacao
WITH (security_barrier = true) AS
SELECT
    a.nome                      AS nome_aluno,
    ult.data_avaliacao          AS data_ultima_avaliacao,
    a.objetivo_principal        AS objetivo_principal,
    ult.percentagem_gordura     AS percentagem_gordura_atual
FROM alunos a
LEFT JOIN LATERAL (
    SELECT af.data_avaliacao, af.percentagem_gordura
    FROM avaliacoes_fisicas af
    WHERE af.id_aluno = a.id
    ORDER BY af.data_avaliacao DESC, af.id DESC
    LIMIT 1
) ult ON TRUE;

-- Perfil dos instrutores: acesso APENAS à view (nunca às tabelas base)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'instrutor_musculacao') THEN
        CREATE ROLE instrutor_musculacao NOLOGIN;
    END IF;
END
$$;

REVOKE ALL ON alunos, avaliacoes_fisicas FROM instrutor_musculacao;
GRANT  SELECT ON view_instrutores_musculacao TO instrutor_musculacao;

-- ---------------------------------------------------------------------
-- 3. DADOS DE TESTE VÁLIDOS
-- (dados_cartao_credito contém tokens fictícios, não números reais)
-- ---------------------------------------------------------------------
INSERT INTO alunos (nome, morada, telefone, dados_cartao_credito, objetivo_principal, data_matricula) VALUES
('Ana Ferreira',  'Rua das Flores, 12, Lisboa',        '912345678', 'tok_visa_4242_XXXX',  'Perda de peso',          '2025-01-15'),
('Bruno Costa',   'Av. da Liberdade, 200, Porto',      '934567890', 'tok_mc_5555_XXXX',    'Hipertrofia muscular',   '2025-03-02'),
('Carla Mendes',  'Travessa do Sol, 5, Coimbra',       '965432109', 'tok_visa_1111_XXXX',  'Resistência cardiovascular', '2025-06-20'),
('Diogo Pereira', 'Rua do Comércio, 77, Braga',        '921098765', 'tok_amex_0005_XXXX',  'Definição muscular',     '2026-02-10');

INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura) VALUES
-- Ana: duas avaliações (a view deve mostrar só a mais recente)
(1, '2025-01-20', 78.50, 1.65, 32.5),
(1, '2025-07-18', 71.20, 1.65, 27.8),
-- Bruno
(2, '2025-03-05', 82.00, 1.80, 18.4),
(2, '2025-09-10', 85.30, 1.80, 16.9),
-- Carla
(3, '2025-06-25', 60.40, 1.70, 24.1),
-- Diogo: sem avaliações (aparece na view com valores NULL)
-- Valores-limite aceites
(3, '2026-01-10', 59.00, 1.70,  2.0),
(2, '2026-03-15', 86.00, 1.80, 60.0);

-- ---------------------------------------------------------------------
-- 4. INSERT PROPOSITADAMENTE INVÁLIDO
-- Deve FALHAR com:
--   ERROR: new row for relation "avaliacoes_fisicas" violates check
--          constraint "ck_percentagem_gordura_valida"
-- (Se executar via psql, use \set ON_ERROR_STOP off para continuar.)
-- ---------------------------------------------------------------------
INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
VALUES (4, '2026-04-01', 75.00, 1.78, -5.0);

-- Variante que demonstra o bloqueio sem interromper o script:
DO $$
BEGIN
    INSERT INTO avaliacoes_fisicas (id_aluno, data_avaliacao, peso, altura, percentagem_gordura)
    VALUES (4, '2026-04-01', 75.00, 1.78, -5.0);
    RAISE NOTICE 'ERRO: o INSERT inválido foi aceite!';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK - Constraint bloqueou a transação: %', SQLERRM;
END
$$;

-- Prova: nenhuma linha com gordura inválida foi gravada (resultado esperado: 0)
SELECT COUNT(*) AS linhas_invalidas
FROM avaliacoes_fisicas
WHERE percentagem_gordura NOT BETWEEN 2.0 AND 60.0;

-- ---------------------------------------------------------------------
-- 5. DEMONSTRAÇÃO DA MÁSCARA DE ACESSO
-- ---------------------------------------------------------------------
-- Visão do instrutor: apenas 4 colunas, sem morada/telefone/cartão
SELECT *
FROM view_instrutores_musculacao
ORDER BY nome_aluno;

-- Simulação como instrutor: a view funciona, as tabelas base estão bloqueadas
SET ROLE instrutor_musculacao;

SELECT nome_aluno, data_ultima_avaliacao, objetivo_principal, percentagem_gordura_atual
FROM view_instrutores_musculacao
ORDER BY nome_aluno;

-- Deve falhar: ERROR: permission denied for table alunos
-- SELECT morada, telefone, dados_cartao_credito FROM alunos;

RESET ROLE;
