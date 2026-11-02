require('dotenv').config();
const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const pool = require('./db');
const { evaluate } = require('./viability');

const app = express();
app.use(cors());
app.use(express.json());

// One row per box: latest reading + totals since dispatch (or until delivery) + vaccine limits
const BOXES_SQL = `
SELECT b.id, b.name, b.destination, b.status, b.dispatched_at, b.delivered_at,
       p.name AS vaccine, p.min_temp_c, p.max_temp_c, p.critical_min_c, p.critical_max_c,
       p.max_excursion_s, p.max_humidity_pct, p.max_vib_g, p.max_shock_events, p.max_lid_open_s,
       l.recorded_at AS last_seen, l.temp_c, l.hum_pct, l.vib_g, l.moving, l.lid_open,
       a.n, a.min_temp, a.max_temp, a.max_hum, a.excursion_s, a.shock_events, a.lid_open_s
FROM boxes b
JOIN vaccine_profiles p ON p.id = b.profile_id
LEFT JOIN LATERAL (
  SELECT * FROM readings r WHERE r.box_id = b.id ORDER BY r.recorded_at DESC LIMIT 1) l ON true
LEFT JOIN LATERAL (
  SELECT COUNT(*)::int AS n, MIN(r.temp_c) AS min_temp, MAX(r.temp_c) AS max_temp, MAX(r.hum_pct) AS max_hum,
         COALESCE(SUM(r.interval_s) FILTER (WHERE r.temp_c < p.min_temp_c OR r.temp_c > p.max_temp_c), 0)::int AS excursion_s,
         (COUNT(*) FILTER (WHERE r.vib_g > p.max_vib_g))::int AS shock_events,
         COALESCE(SUM(r.interval_s) FILTER (WHERE r.lid_open), 0)::int AS lid_open_s
  FROM readings r
  WHERE r.box_id = b.id AND r.recorded_at >= b.dispatched_at
    AND r.recorded_at <= COALESCE(b.delivered_at, now())) a ON true
ORDER BY b.id`;

app.get('/health', (_req, res) => res.send('ok'));

app.get('/api/boxes', async (_req, res) => {
  try {
    const { rows } = await pool.query(BOXES_SQL);
    res.json(rows.map((r) => ({ ...r, ...evaluate(r) })));
  } catch (e) { console.error(e); res.status(500).json({ error: 'Database error' }); }
});

app.get('/api/boxes/:id/readings', async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 60, 500);
  try {
    const { rows } = await pool.query(
      `SELECT recorded_at, temp_c FROM (
         SELECT recorded_at, temp_c FROM readings WHERE box_id = $1 ORDER BY recorded_at DESC LIMIT $2
       ) t ORDER BY recorded_at`, [req.params.id, limit]);
    res.json(rows);
  } catch (e) { console.error(e); res.status(500).json({ error: 'Database error' }); }
});

app.post('/api/boxes/:id/deliver', async (req, res) => {
  try {
    await pool.query(
      "UPDATE boxes SET status='delivered', delivered_at=now() WHERE id=$1 AND status='in_transit'", [req.params.id]);
    res.json({ ok: true });
  } catch (e) { console.error(e); res.status(500).json({ error: 'Database error' }); }
});

// Serve the built React dashboard if present (not needed when nginx serves the frontend)
const dist = path.join(__dirname, '../frontend/dist');
if (fs.existsSync(dist)) {
  app.use(express.static(dist));
  app.get('*', (_req, res) => res.sendFile(path.join(dist, 'index.html')));
}

app.listen(process.env.PORT || 3000, () => console.log('API listening on', process.env.PORT || 3000));
