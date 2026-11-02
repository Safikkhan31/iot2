import { useEffect, useState } from 'react';

const VERDICT = {
  safe: ['Usable', 'safe'],
  caution: ['Use with caution', 'caution'],
  unusable: ['Not usable', 'bad'],
  no_data: ['No data yet', 'idle'],
};
const f = (v, d = 1) => (v == null ? '–' : Number(v).toFixed(d));
const ago = (t) => {
  if (!t) return 'never';
  const s = Math.max(0, Math.round((Date.now() - new Date(t)) / 1000));
  return s < 60 ? `${s}s ago` : s < 3600 ? `${Math.round(s / 60)} min ago` : `${Math.round(s / 3600)} h ago`;
};

// Scale showing the vaccine's safe band and where the box is right now
function Gauge({ b }) {
  const lo = b.min_temp_c - 8, hi = b.max_temp_c + 8;
  const pos = (t) => `${Math.min(100, Math.max(0, ((t - lo) / (hi - lo)) * 100))}%`;
  return (
    <div className="gauge" aria-label={`Current ${f(b.temp_c)} degrees, safe ${b.min_temp_c} to ${b.max_temp_c}`}>
      <div className="band" style={{ left: pos(b.min_temp_c), width: `calc(${pos(b.max_temp_c)} - ${pos(b.min_temp_c)})` }} />
      {b.temp_c != null && <div className="marker" style={{ left: pos(b.temp_c) }} />}
      <span className="lo">{b.min_temp_c}°</span><span className="hi">{b.max_temp_c}°</span>
    </div>
  );
}

function Spark({ id }) {
  const [pts, setPts] = useState([]);
  useEffect(() => {
    const load = () => fetch(`/api/boxes/${id}/readings?limit=60`)
      .then((r) => (r.ok ? r.json() : []))
      .then((d) => setPts(Array.isArray(d) ? d : []))
      .catch(() => {});
    load();
    const t = setInterval(load, 10000);
    return () => clearInterval(t);
  }, [id]);
  if (pts.length < 2) return <div className="spark" />;
  const ys = pts.map((p) => p.temp_c), lo = Math.min(...ys), span = Math.max(...ys) - lo || 1;
  const d = pts.map((p, i) => `${(i / (pts.length - 1)) * 200},${36 - ((p.temp_c - lo) / span) * 32}`).join(' ');
  return <svg className="spark" viewBox="0 0 200 40" preserveAspectRatio="none"><polyline points={d} /></svg>;
}

function BoxCard({ b, onDeliver }) {
  const [label, cls] = VERDICT[b.verdict];
  const used = b.max_excursion_s ? Math.min(100, (b.excursion_s / b.max_excursion_s) * 100) : 0;
  return (
    <article className={`box ${cls}`}>
      <header>
        <div><h2>{b.name}</h2><p>{b.vaccine}{b.destination ? `, to ${b.destination}` : ''}</p></div>
        <span className={`badge ${cls}`}>{label}</span>
      </header>
      <div className="temp">{f(b.temp_c)}<span>°C</span></div>
      <Gauge b={b} />
      <Spark id={b.id} />
      <dl>
        <div><dt>Humidity</dt><dd>{f(b.hum_pct, 0)}%</dd></div>
        <div><dt>Vibration</dt><dd>{f(b.vib_g, 2)} g</dd></div>
        <div><dt>Lid</dt><dd>{b.lid_open ? 'Open' : 'Closed'}</dd></div>
        <div><dt>Motion</dt><dd>{b.moving ? 'Moving' : 'Still'}</dd></div>
      </dl>
      <div className="budget">
        <div className="bar"><span style={{ width: `${used}%` }} /></div>
        <p>Time out of range: {Math.round(b.excursion_s / 60)} of {Math.round(b.max_excursion_s / 60)} min allowed</p>
      </div>
      {b.reasons.length > 0 && <ul className="reasons">{b.reasons.map((r) => <li key={r}>{r}</li>)}</ul>}
      <footer>
        <span className={b.offline ? 'offline' : ''}>{b.offline ? 'Offline. ' : ''}Last reading {ago(b.last_seen)}</span>
        {b.status === 'in_transit'
          ? <button onClick={() => onDeliver(b.id)}>Mark delivered</button>
          : <span>Delivered {ago(b.delivered_at)}</span>}
      </footer>
    </article>
  );
}

export default function App() {
  const [boxes, setBoxes] = useState([]);
  const [error, setError] = useState('');
  const load = () =>
    fetch('/api/boxes')
      .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then((d) => { setBoxes(Array.isArray(d) ? d : []); setError(''); })
      .catch(() => setError('Server error. Check the backend terminal for the database or MQTT message.'));
  useEffect(() => { load(); const t = setInterval(load, 5000); return () => clearInterval(t); }, []);
  const deliver = (id) => fetch(`/api/boxes/${id}/deliver`, { method: 'POST' }).then(load);
  const count = (v) => boxes.filter((b) => b.verdict === v).length;

  return (
    <main>
      <h1>Vaccine boxes</h1>
      <p className="tally">
        <b className="safe">{count('safe')} usable</b>
        <b className="caution">{count('caution')} need a look</b>
        <b className="bad">{count('unusable')} not usable</b>
      </p>
      {error && <p className="error">{error}</p>}
      {!error && boxes.length === 0 && <p className="empty">No boxes yet. A box appears here after its first MQTT message.</p>}
      <section className="grid">{boxes.map((b) => <BoxCard key={b.id} b={b} onDeliver={deliver} />)}</section>
    </main>
  );
}
