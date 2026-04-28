CREATE TABLE IF NOT EXISTS deployments (
    id              SERIAL PRIMARY KEY,
    deployment_name VARCHAR(255) NOT NULL,
    namespace       VARCHAR(100) NOT NULL,
    validated_by_ai BOOLEAN DEFAULT FALSE,
    ai_score        INTEGER CHECK (ai_score BETWEEN 0 AND 100),
    validated_at    TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_reports (
    id              SERIAL PRIMARY KEY,
    deployment_id   INTEGER REFERENCES deployments(id),
    verdict         VARCHAR(3) CHECK (verdict IN ('OUI', 'NON')),
    score           INTEGER,
    risques         JSONB,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

INSERT INTO deployments (deployment_name, namespace, validated_by_ai, ai_score, validated_at)
VALUES ('postgres-v1', 'database', TRUE, 85, NOW());
