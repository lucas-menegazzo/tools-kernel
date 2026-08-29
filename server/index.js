const express = require('express');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3001;

// Database connection
// Uses the application role which has NOBYPASSRLS and RLS will be enforced
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5434,
  database: process.env.DB_NAME || 'tools_kernel',
  user: process.env.DB_USER || 'tools_kernel_app',
  password: process.env.DB_PASSWORD || 'tools_kernel_app_password',
});

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

// Serve the main page
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

// Start server
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
  console.log('Actor selector available for isolation demonstration');
});

// Graceful shutdown
process.on('SIGTERM', () => {
  pool.end(() => {
    console.log('Database pool closed');
    process.exit(0);
  });
});