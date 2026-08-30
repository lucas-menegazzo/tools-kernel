const express = require('express');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3001;

// Database connection
// Uses the application role which has NOBYPASSRLS and RLS will be enforced
const dbConfig = {
  // Abort if the database is not reachable on startup instead of hanging.
  connectionTimeoutMillis: 5000,
};

if (process.env.DATABASE_URL) {
  dbConfig.connectionString = process.env.DATABASE_URL;
} else {
  dbConfig.host = process.env.DB_HOST || 'localhost';
  dbConfig.port = process.env.DB_PORT || 5434;
  dbConfig.database = process.env.DB_NAME || 'tools_kernel';
  dbConfig.user = process.env.DB_USER || 'tools_kernel_app';
  dbConfig.password = process.env.DB_PASSWORD || 'tools_kernel_app_password';
}

// Render and most managed Postgres providers require TLS. Use their provided
// hostname (or DATABASE_URL). Railway's self-signed cert is CN=localhost.
if (process.env.DB_SSL === 'true' || process.env.DB_SSL === 'require') {
  dbConfig.ssl = { rejectUnauthorized: false };
} else if (process.env.DB_SSL === 'railway' || process.env.DB_SSL_SERVERNAME) {
  dbConfig.ssl = { rejectUnauthorized: false, servername: process.env.DB_SSL_SERVERNAME || 'localhost' };
}

// pg overwrites our tls.servername with the host when the host is a domain.
// For Railway's localhost cert we must keep the explicit servername.
const net = require('net');
const originalIsIP = net.isIP;
if (dbConfig.ssl && dbConfig.ssl.servername) {
  net.isIP = () => 4;
}

const pool = new Pool(dbConfig);

net.isIP = originalIsIP;

// Log unexpected pool-level errors and release the client if an idle client errors.
pool.on('error', (err, client) => {
  console.error('Unexpected database pool error:', err.message);
  if (client) client.release(true);
});

// Verify that the database is reachable before starting the server.
async function checkDatabase(retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt += 1) {
    const client = await pool.connect().catch(err => ({ error: err }));
    if (client && client.error) {
      console.error(`Database connection attempt ${attempt}/${retries} failed:`, client.error.message);
      if (attempt === retries) {
        throw new Error('Could not connect to PostgreSQL after ' + retries + ' attempts');
      }
      // Wait before the next attempt.
      await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
      continue;
    }
    await client.query('SELECT 1');
    client.release();
    console.log('Database connection verified');
    return true;
  }
  return false;
}

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

// Available actors for testing
const actors = [
  {
    email: 'marina.alves@thefintechcompany.com.br',
    name: 'Marina Alves',
    role: 'Analista Compliance',
    team: 'Team A',
    canRevealPII: false
  },
  {
    email: 'helena.castro@thefintechcompany.com.br',
    name: 'Helena Castro',
    role: 'Supervisor Compliance',
    team: 'Team A',
    canRevealPII: false
  },
  {
    email: 'otavio.branco@thefintechcompany.com.br',
    name: 'Otavio Branco',
    role: 'CISO',
    team: 'Security',
    canRevealPII: true
  }
];

// Available Refunds actors for testing
const refundActors = [
  {
    email: 'larissa.melo@thefintechcompany.com.br',
    name: 'Larissa Melo',
    role: 'Analista Senior',
    team: 'Operacoes',
    canRevealPII: false
  },
  {
    email: 'bruno.tavares@thefintechcompany.com.br',
    name: 'Bruno Tavares',
    role: 'Analista Senior',
    team: 'Operacoes',
    canRevealPII: false
  },
  {
    email: 'paula.werneck@thefintechcompany.com.br',
    name: 'Paula Werneck',
    role: 'Supervisor Operacoes',
    team: 'Operacoes',
    canRevealPII: false
  },
  {
    email: 'ricardo.salles@thefintechcompany.com.br',
    name: 'Ricardo Salles',
    role: 'Gerente Operacoes',
    team: 'Operacoes',
    canRevealPII: true
  }
];

// Available Feature Flag actors for testing
const featureFlagActors = [
  {
    email: 'bruno.martins@thefintechcompany.com.br',
    name: 'Bruno Martins',
    role: 'Engenheiro Plataforma',
    team: 'Platform',
    canRevealPII: false
  },
  {
    email: 'carla.silva@thefintechcompany.com.br',
    name: 'Carla Silva',
    role: 'Engenheiro Plataforma',
    team: 'KYC',
    canRevealPII: false
  },
  {
    email: 'diego.nunes@thefintechcompany.com.br',
    name: 'Diego Nunes',
    role: 'Engenheiro Plataforma',
    team: 'Refunds',
    canRevealPII: false
  },
  {
    email: 'fernanda.lima@thefintechcompany.com.br',
    name: 'Fernanda Lima',
    role: 'Tech Lead Plataforma',
    team: 'Platform',
    canRevealPII: false
  },
  {
    email: 'gabriel.santos@thefintechcompany.com.br',
    name: 'Gabriel Santos',
    role: 'Leitor Plataforma',
    team: 'Risk',
    canRevealPII: false
  }
];

// Set actor context for database session
async function setActorContext(client, actor) {
  await client.query('SELECT set_actor_context($1, $2, $3)', [
    actor.email,
    [actor.role],
    actor.team
  ]);
}

// API endpoint to get available actors
app.get('/api/actors', (req, res) => {
  res.json(actors);
});

// API endpoint to get KYC cases for current actor
app.get('/api/kyc-cases', async (req, res) => {
  const actorEmail = req.query.actor;
  const actor = actors.find(a => a.email === actorEmail);
  
  if (!actor) {
    return res.status(400).json({ error: 'Invalid actor' });
  }
  
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    await setActorContext(client, actor);
    
    const result = await client.query(`
      SELECT 
        case_number,
        full_name,
        mask_cpf(cpf, $1) as cpf,
        risk_level,
        status,
        responsible_analyst,
        opened_at,
        qualification_deadline,
        team
      FROM kyc.kyc_cases
      WHERE deleted_at IS NULL
      ORDER BY case_number
    `, [actor.canRevealPII]);
    
    await client.query('COMMIT');
    
    res.json({
      actor: actor,
      cases: result.rows,
      count: result.rows.length
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error fetching KYC cases:', error);
    res.status(500).json({ error: error.message });
  } finally {
    client.release();
  }
});

// API endpoint to test approval attempt
app.post('/api/test-approval', async (req, res) => {
  const { caseNumber, actorEmail } = req.body;
  const actor = actors.find(a => a.email === actorEmail);
  
  if (!actor) {
    return res.status(400).json({ error: 'Invalid actor' });
  }
  
  const client = await pool.connect();
  
  try {
    await setActorContext(client, actor);
    
    // Try to get the case to see if actor can access it
    const caseResult = await client.query(`
      SELECT responsible_analyst 
      FROM kyc.kyc_cases 
      WHERE case_number = $1 AND deleted_at IS NULL
    `, [caseNumber]);
    
    if (caseResult.rows.length === 0) {
      return res.json({ 
        success: false, 
        reason: 'Case not found or access denied by RLS' 
      });
    }
    
    const kycCase = caseResult.rows[0];
    
    // Check if actor is the proposer (should not approve own case)
    if (kycCase.responsible_analyst === actor.email) {
      // Record the refused attempt in audit trail
      await client.query('SELECT create_audit_entry($1, $2, $3, $4)', [
        'kyc.kyc_cases',
        caseNumber,
        'APPROVAL_REFUSED',
        JSON.stringify({
          reason: 'Proposer cannot approve own case',
          actor_id: actor.email,
          actor_role: actor.role
        })
      ]);
      
      return res.json({ 
        success: false, 
        reason: 'Proposer cannot approve own case',
        auditTrailRecorded: true
      });
    }
    
    // If actor has approval role and is not proposer, approval would succeed
    if (actor.role === 'Supervisor Compliance' || actor.role === 'Gerente Compliance') {
      return res.json({ 
        success: true, 
        reason: 'Actor has approval role and is not the proposer' 
      });
    }
    
    return res.json({ 
      success: false, 
      reason: 'Actor does not have approval role' 
    });
    
  } catch (error) {
    console.error('Error testing approval:', error);
    res.status(500).json({ error: error.message });
  } finally {
    client.release();
  }
});

// API endpoint to get refund actors
app.get('/api/refund-actors', (req, res) => {
  res.json(refundActors);
});

// API endpoint to get refund queue for current actor
app.get('/api/refunds', async (req, res) => {
  const actorEmail = req.query.actor;
  const actor = refundActors.find(a => a.email === actorEmail);
  
  if (!actor) {
    return res.status(400).json({ error: 'Invalid actor' });
  }
  
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    await setActorContext(client, actor);
    
    const result = await client.query(`
      SELECT 
        id,
        case_number,
        nome_cliente,
        mask_cpf(cpf_cliente, $1) as cpf_cliente,
        valor,
        motivo,
        status,
        solicitado_por,
        solicitada_em,
        team
      FROM refunds.devolucoes
      WHERE deleted_at IS NULL AND status <> 'Concluida'
      ORDER BY case_number
    `, [actor.canRevealPII]);
    
    const totalResult = await client.query(`
      SELECT COALESCE(SUM(valor), 0) as total_em_aberto
      FROM refunds.devolucoes
      WHERE deleted_at IS NULL AND status = 'Aguardando aprovacao'
    `);
    
    await client.query('COMMIT');
    
    res.json({
      actor: actor,
      cases: result.rows,
      count: result.rows.length,
      totalEmAberto: parseFloat(totalResult.rows[0].total_em_aberto)
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error fetching refunds:', error);
    res.status(500).json({ error: error.message });
  } finally {
    client.release();
  }
});

// API endpoint to approve one or more refunds (single and bulk share this code path)
app.post('/api/refunds/approve', async (req, res) => {
  const { ids, actorEmail, decision, reason } = req.body;
  const actor = refundActors.find(a => a.email === actorEmail);
  
  if (!actor) {
    return res.status(400).json({ error: 'Invalid actor' });
  }
  
  if (!ids || !Array.isArray(ids) || ids.length === 0) {
    return res.status(400).json({ error: 'Refund ids array is required' });
  }
  
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    await setActorContext(client, actor);
    
    const result = await client.query(`
      SELECT * FROM refunds.aprovar_devolucoes($1, $2, $3)
    `, [ids, decision || 'approved', reason || '']);
    
    await client.query('COMMIT');
    
    res.json({
      actor: actor,
      results: result.rows
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error approving refunds:', error);
    res.status(500).json({ error: error.message });
  } finally {
    client.release();
  }
});

// API endpoint to get feature flag actors
app.get('/api/feature-flag-actors', (req, res) => {
  res.json(featureFlagActors);
});

// API endpoint to get feature flags for current actor
app.get('/api/feature-flags', async (req, res) => {
  const actorEmail = req.query.actor;
  const actor = featureFlagActors.find(a => a.email === actorEmail);
  
  if (!actor) {
    return res.status(400).json({ error: 'Invalid actor' });
  }
  
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    await setActorContext(client, actor);
    
    const result = await client.query(`
      SELECT 
        flag_key,
        description,
        environment,
        is_active,
        owning_team,
        created_by,
        created_at,
        updated_at
      FROM feature_flag.feature_flags
      WHERE deleted_at IS NULL
      ORDER BY flag_key
    `);
    
    await client.query('COMMIT');
    
    res.json({
      actor: actor,
      cases: result.rows,
      count: result.rows.length
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error fetching feature flags:', error);
    res.status(500).json({ error: error.message });
  } finally {
    client.release();
  }
});

// API endpoint to toggle a feature flag
app.post('/api/feature-flags/toggle', async (req, res) => {
  const { flagKey, actorEmail } = req.body;
  const actor = featureFlagActors.find(a => a.email === actorEmail);
  
  if (!actor) {
    return res.status(400).json({ error: 'Invalid actor' });
  }
  
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    await setActorContext(client, actor);
    
    await client.query(`
      UPDATE feature_flag.feature_flags
      SET is_active = NOT is_active
      WHERE flag_key = $1
    `, [flagKey]);
    
    await client.query('COMMIT');
    
    res.json({ success: true, flagKey });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error toggling feature flag:', error);
    res.status(500).json({ error: error.message });
  } finally {
    client.release();
  }
});

// Serve app pages with optional trailing-slash redirect
function servePage(route, file) {
  app.get(route, (req, res) => {
    res.sendFile(path.join(__dirname, '../public', file));
  });
  app.get(route + '/', (req, res) => {
    res.redirect(route);
  });
}

servePage('/', 'index.html');
servePage('/refunds.html', 'refunds.html');
servePage('/feature-flags.html', 'feature-flags.html');

// Health check that also verifies the database is reachable.
app.get('/health', async (req, res) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    res.json({ status: 'ok', database: 'reachable' });
  } catch (error) {
    if (client) client.release(true);
    console.error('Health check failed:', error.message);
    res.status(503).json({ status: 'error', database: 'unreachable', message: error.message });
  }
});

// Global error handler for uncaught exceptions in routes.
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err.message);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server only after the database is reachable.
checkDatabase()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Server running on http://localhost:${PORT}`);
      console.log('Actor selector available for isolation demonstration');
    });
  })
  .catch(err => {
    console.error('Server failed to start:', err.message);
    process.exit(1);
  });

// Graceful shutdown
function gracefulShutdown(signal) {
  return () => {
    console.log(`Received ${signal}. Closing database pool...`);
    pool.end(() => {
      console.log('Database pool closed');
      process.exit(0);
    });
  };
}

process.on('SIGTERM', gracefulShutdown('SIGTERM'));
process.on('SIGINT', gracefulShutdown('SIGINT'));