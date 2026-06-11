const express = require('express');
const pinoHttp = require('pino-http');
const { Pool } = require('pg');

const app = express();
const PORT = process.env.PORT || 8080;

const logger = pinoHttp();
app.use(logger);
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'platform',
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: false
});

// Health check
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', database: 'ok', version: '1.0.0' });
  } catch (err) {
    res.status(503).json({ status: 'error', database: 'unreachable' });
  }
});

// Liveness probe
app.get('/health/live', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

// API - infrastructure info
app.get('/api/info', (req, res) => {
  res.json({
    cluster: process.env.CLUSTER_NAME || 'platform-dev',
    region: process.env.AWS_REGION || 'eu-central-1',
    environment: process.env.ENVIRONMENT || 'dev',
    timestamp: new Date().toISOString()
  });
});

// API - db test
app.get('/api/nodes', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, hostname, status, created_at FROM nodes ORDER BY created_at DESC'
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
# retrigger
x
xx
xxx
