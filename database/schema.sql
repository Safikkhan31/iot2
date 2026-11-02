-- Cold chain monitoring schema (PostgreSQL)
CREATE TABLE IF NOT EXISTS vaccine_profiles (
  id                SERIAL PRIMARY KEY,
  name              TEXT UNIQUE NOT NULL,
  min_temp_c        DOUBLE PRECISION NOT NULL,   -- safe range
  max_temp_c        DOUBLE PRECISION NOT NULL,
  critical_min_c    DOUBLE PRECISION NOT NULL,   -- touching this = instantly unusable (freezing)
  critical_max_c    DOUBLE PRECISION NOT NULL,   -- touching this = instantly unusable (heat)
  max_excursion_s   INTEGER NOT NULL,            -- total allowed seconds outside safe range
  max_humidity_pct  DOUBLE PRECISION NOT NULL,
  max_vib_g         DOUBLE PRECISION NOT NULL,   -- reading above this counts as a shock
  max_shock_events  INTEGER NOT NULL,
  max_lid_open_s    INTEGER NOT NULL             -- total allowed lid-open seconds
);

CREATE TABLE IF NOT EXISTS boxes (
  id            TEXT PRIMARY KEY,                -- e.g. BOX-001 (same as ESP32 BOX_ID)
  name          TEXT NOT NULL,
  profile_id    INTEGER NOT NULL REFERENCES vaccine_profiles(id) DEFAULT 1,
  destination   TEXT,
  status        TEXT NOT NULL DEFAULT 'in_transit' CHECK (status IN ('in_transit','delivered')),
  dispatched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at  TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS readings (
  id          BIGSERIAL PRIMARY KEY,
  box_id      TEXT NOT NULL REFERENCES boxes(id) ON DELETE CASCADE,
  recorded_at TIMESTAMPTZ NOT NULL,
  temp_c      DOUBLE PRECISION NOT NULL,
  hum_pct     DOUBLE PRECISION,
  vib_g       DOUBLE PRECISION NOT NULL DEFAULT 0,
  moving      BOOLEAN NOT NULL DEFAULT false,
  lid_open    BOOLEAN NOT NULL DEFAULT false,
  interval_s  INTEGER NOT NULL DEFAULT 10,       -- seconds this reading represents
  rssi        INTEGER,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_readings_box_time ON readings (box_id, recorded_at DESC);

-- Example profiles (verify against your vaccine's datasheet)
INSERT INTO vaccine_profiles
 (name, min_temp_c, max_temp_c, critical_min_c, critical_max_c, max_excursion_s, max_humidity_pct, max_vib_g, max_shock_events, max_lid_open_s)
VALUES
 ('Standard vaccine (2-8 C)',      2,   8,  -0.5, 15,  3600, 85, 1.5, 3, 300),
 ('Frozen vaccine (-25 to -15 C)', -25, -15, -30, -10, 1800, 85, 1.5, 3, 120)
ON CONFLICT (name) DO NOTHING;
