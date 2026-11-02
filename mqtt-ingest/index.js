// MQTT ingest service: subscribes to the broker and stores every telemetry message in PostgreSQL.
// Runs separately from the API backend (node index.js).
const mqtt = require('mqtt');
const pool = require('./db');
const num = (v) => (v !== null && v !== undefined && Number.isFinite(+v) ? +v : null);

function startIngest() {
  const client = mqtt.connect(process.env.MQTT_URL, {
    username: process.env.MQTT_USER,
    password: process.env.MQTT_PASS,
    clientId: 'coldchain-ingest-' + process.pid,
  });
  client.on('connect', () => {
    console.log('MQTT connected');
    client.subscribe('coldchain/+/telemetry', { qos: 1 });
  });
  client.on('error', (e) => console.error('MQTT error:', e.message));

  client.on('message', async (topic, payload) => {
    try {
      const boxId = topic.split('/')[1];
      const d = JSON.parse(payload.toString());
      if (num(d.temp_c) === null) throw new Error('temp_c missing');
      const when = d.ts > 1.6e9 ? new Date(d.ts * 1000) : new Date(); // fall back to server time
      await pool.query(
        'INSERT INTO boxes (id, name) VALUES ($1, $1) ON CONFLICT (id) DO NOTHING', [boxId]);
      await pool.query(
        `INSERT INTO readings (box_id, recorded_at, temp_c, hum_pct, vib_g, moving, lid_open, interval_s, rssi)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [boxId, when, num(d.temp_c), num(d.hum_pct), num(d.vib_g) ?? 0,
         !!d.moving, !!d.lid_open, num(d.interval_s) ?? 10, num(d.rssi)]);
    } catch (e) {
      console.error('Rejected message on', topic, '-', e.message);
    }
  });
}
startIngest();
