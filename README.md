# Cold chain monitoring: setup guide

```
ESP32 --MQTT/JSON--> Mosquitto --> [mqtt-ingest] --writes--> PostgreSQL <--reads-- [backend API] <-- React dashboard
```

| Folder | Role |
|---|---|
| `mqtt-ingest/` | Subscribes to MQTT, validates messages, inserts readings into Postgres |
| `backend/` | REST API and usable / not usable logic. Reads Postgres only |
| `frontend/` | React dashboard (served by nginx in Docker) |
| `database/schema.sql` | Tables and example vaccine profiles |
| `mosquitto/` | Broker config used by Docker |
| `esp32_firmware/` | Box firmware |

The ingest service and the API never call each other. They only meet in the database.

## Deploy to AWS with Terraform and Jenkins
The `terraform/` folder builds the whole AWS setup (VPC, ECR, RDS, servers, Jenkins). Jenkins builds the images from the `Jenkinsfile`, pushes them to ECR and updates the servers when the Git repo changes. See `terraform/README.md`.

## Quick start with Docker (recommended for a single machine)
Each service has its own `Dockerfile`; `docker-compose.yml` runs all five containers (Postgres, Mosquitto, mqtt-ingest, backend, frontend).
```bash
# on an EC2 Ubuntu instance (or any machine) with Docker:
sudo apt update && sudo apt install -y docker.io docker-compose-v2 unzip
unzip coldchain_project.zip && cd coldchain
cp .env.example .env && nano .env          # set the three passwords (letters and digits only)
sudo docker compose up -d --build
sudo docker compose logs -f mqtt-ingest    # should print "MQTT connected"
```
- Dashboard: `http://<server-ip>` (port 80). Security group: open 80 and 1883; keep 22 limited to your IP.
- ESP32: `MQTT_HOST` = server IP, `MQTT_USER` = `esp32`, `MQTT_PASS` = your `ESP32_MQTT_PASSWORD`.
- Tables are created automatically on first start. Reset the database with `sudo docker compose down -v`.
- Useful: `docker compose ps`, `docker compose logs -f backend`, `docker compose restart backend`.

Test without hardware:
```bash
sudo docker compose exec mosquitto mosquitto_pub -u esp32 -P <ESP32_MQTT_PASSWORD> -t coldchain/BOX-001/telemetry \
  -m '{"temp_c":5.2,"hum_pct":55,"vib_g":0.1,"moving":false,"lid_open":false,"interval_s":10}'
```

### Run one service on its own (separate servers, ECS, etc.)
```bash
docker build -t coldchain-ingest ./mqtt-ingest
docker run -d --restart unless-stopped --name ingest \
  -e DATABASE_URL=postgres://coldchain:PW@<db-host>:5432/coldchain \
  -e MQTT_URL=mqtt://<broker-host>:1883 -e MQTT_USER=ingest -e MQTT_PASS=PW coldchain-ingest

docker build -t coldchain-api ./backend
docker run -d --restart unless-stopped --name api -p 3000:3000 \
  -e DATABASE_URL=postgres://coldchain:PW@<db-host>:5432/coldchain coldchain-api

docker build -t coldchain-web ./frontend
docker run -d --restart unless-stopped --name web -p 80:80 \
  -e BACKEND_URL=http://<api-host>:3000 coldchain-web
```
For production: use Amazon RDS instead of the Postgres container (run `database/schema.sql` once), push images to ECR, and add TLS to the dashboard and MQTT (port 8883).

## Without Docker
1. Install: `sudo apt install -y mosquitto mosquitto-clients postgresql`, Node.js 20, and `sudo npm install -g pm2`.
2. Mosquitto: add `listener 1883`, `allow_anonymous false`, `password_file /etc/mosquitto/passwd` to `/etc/mosquitto/conf.d/coldchain.conf`. Create users with `sudo mosquitto_passwd -c /etc/mosquitto/passwd esp32` and `sudo mosquitto_passwd /etc/mosquitto/passwd ingest`, then restart mosquitto.
3. Postgres: create user `coldchain` and database `coldchain`, then `psql -h localhost -U coldchain -d coldchain -f database/schema.sql`.
4. Ingest: `cd mqtt-ingest && cp .env.example .env`, edit `.env`, `npm install`, `pm2 start index.js --name coldchain-ingest`.
5. API: `cd frontend && npm install && npm run build`, then `cd ../backend && cp .env.example .env`, edit `.env`, `npm install`, `pm2 start server.js --name coldchain-api` (it serves `frontend/dist` on port 3000). Run `pm2 startup` and `pm2 save` to survive reboots.
6. On Windows, skip PM2: run `npm start` in `mqtt-ingest` and `backend` in two terminals.

## Useful SQL
```sql
UPDATE boxes SET profile_id = 2, destination = 'City Hospital' WHERE id = 'BOX-001';
UPDATE boxes SET status='in_transit', dispatched_at=now(), delivered_at=NULL WHERE id='BOX-001';
```
(With Docker: `docker compose exec postgres psql -U coldchain -d coldchain`.) Boxes register themselves on their first message. Edit `vaccine_profiles` to match each vaccine's datasheet.

## Troubleshooting
- Dashboard shows a server error: open `/api/boxes` and read the backend logs. Usually the schema isn't loaded or `DATABASE_URL` is wrong.
- No boxes appear: check the `mqtt-ingest` logs for MQTT or database errors.
- `ECONNREFUSED ...:1883`: Mosquitto isn't running. `Not authorized`: the MQTT user or password doesn't match.
