// Decides if a box's vaccine is still usable, from aggregated readings + vaccine profile
const mins = (s) => Math.round(s / 60);

function evaluate(r) {
  if (!r.n) return { verdict: 'no_data', reasons: [], offline: false };
  const reasons = [];
  let verdict = 'safe';
  const bad  = (m) => { verdict = 'unusable'; reasons.push(m); };
  const warn = (m) => { if (verdict === 'safe') verdict = 'caution'; reasons.push(m); };

  if (r.min_temp < r.critical_min_c) bad(`Froze: dropped to ${r.min_temp.toFixed(1)} °C`);
  if (r.max_temp > r.critical_max_c) bad(`Overheated: reached ${r.max_temp.toFixed(1)} °C`);
  if (r.excursion_s > r.max_excursion_s)
    bad(`Outside ${r.min_temp_c}–${r.max_temp_c} °C for ${mins(r.excursion_s)} min (limit ${mins(r.max_excursion_s)})`);
  else if (r.excursion_s > 0)
    warn(`Outside safe range for ${mins(r.excursion_s)} min so far`);
  if (r.max_hum > r.max_humidity_pct) warn(`Humidity reached ${r.max_hum.toFixed(0)}%`);
  if (r.shock_events > r.max_shock_events) warn(`${r.shock_events} shocks recorded (limit ${r.max_shock_events})`);
  if (r.lid_open_s > r.max_lid_open_s) warn(`Lid open ${r.lid_open_s}s in total (limit ${r.max_lid_open_s}s)`);

  const offline = r.status === 'in_transit' && Date.now() - new Date(r.last_seen) > 5 * 60 * 1000;
  return { verdict, reasons, offline };
}
module.exports = { evaluate };
