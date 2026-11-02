/*
  Cold chain box firmware (ESP32)
  Libraries (Library Manager): PubSubClient, ArduinoJson, OneWire, DallasTemperature,
                               DHT sensor library, Adafruit MPU6050, Adafruit Unified Sensor
  Wiring:
    DS18B20 data -> GPIO4 (4.7k pull-up to 3V3)     DHT22 data -> GPIO5
    MPU6050 SDA -> GPIO21, SCL -> GPIO22            Reed switch -> GPIO27 and GND (magnet on lid)
    Buzzer/LED  -> GPIO26
  Reed switch closed (magnet near) = lid closed.
*/
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <DHT.h>
#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <time.h>

// ---- CONFIGURE THESE ----
const char* WIFI_SSID   = "YOUR_WIFI";
const char* WIFI_PASS   = "YOUR_PASSWORD";
const char* MQTT_HOST   = "YOUR_EC2_PUBLIC_IP";
const int   MQTT_PORT   = 1883;
const char* MQTT_USER   = "esp32";
const char* MQTT_PASS   = "YOUR_MQTT_PASSWORD";
const char* BOX_ID      = "BOX-001";          // unique per box
const int   INTERVAL_S  = 10;                 // seconds between readings
// -------------------------

#define PIN_DS18B20 4
#define PIN_DHT     5
#define PIN_REED    27
#define PIN_ALERT   26
#define QMAX        100                       // readings kept in RAM while offline

OneWire oneWire(PIN_DS18B20);
DallasTemperature ds18b20(&oneWire);
DHT dht(PIN_DHT, DHT22);
Adafruit_MPU6050 mpu;
WiFiClient net;
PubSubClient mqtt(net);

String topic;
String queue[QMAX];
int qHead = 0, qCount = 0;
unsigned long lastSample = 0, lastRetry = 0;

void enqueue(const String& s) {
  if (qCount == QMAX) { qHead = (qHead + 1) % QMAX; qCount--; }   // drop oldest
  queue[(qHead + qCount) % QMAX] = s;
  qCount++;
}

void flushQueue() {
  while (qCount > 0 && mqtt.connected()) {
    if (!mqtt.publish(topic.c_str(), queue[qHead].c_str())) return;
    qHead = (qHead + 1) % QMAX; qCount--;
    mqtt.loop();
  }
}

void ensureConnections() {
  if (millis() - lastRetry < 5000) return;
  lastRetry = millis();
  if (WiFi.status() != WL_CONNECTED) { WiFi.begin(WIFI_SSID, WIFI_PASS); return; }
  if (!mqtt.connected()) {
    String cid = String("esp32-") + BOX_ID;
    if (mqtt.connect(cid.c_str(), MQTT_USER, MQTT_PASS)) Serial.println("MQTT connected");
    else Serial.printf("MQTT failed, rc=%d\n", mqtt.state());
  }
}

// Peak vibration over ~0.5 s, in g, with gravity removed
float readVibrationG(bool& moving) {
  float peak = 0, gyro = 0;
  for (int i = 0; i < 50; i++) {
    sensors_event_t a, g, t;
    mpu.getEvent(&a, &g, &t);
    float mag = sqrt(a.acceleration.x * a.acceleration.x + a.acceleration.y * a.acceleration.y +
                     a.acceleration.z * a.acceleration.z) / 9.81;
    peak = max(peak, fabsf(mag - 1.0f));
    gyro = max(gyro, fabsf(g.gyro.x) + fabsf(g.gyro.y) + fabsf(g.gyro.z));
    delay(10);
  }
  moving = (peak > 0.05f) || (gyro > 0.3f);
  return peak;
}

void sampleAndSend() {
  ds18b20.requestTemperatures();
  float temp = ds18b20.getTempCByIndex(0);
  if (temp == DEVICE_DISCONNECTED_C) { Serial.println("DS18B20 not found"); return; }
  float hum = dht.readHumidity();
  bool moving = false;
  float vib = readVibrationG(moving);
  bool lidOpen = digitalRead(PIN_REED) == HIGH;     // magnet away = lid open

  StaticJsonDocument<256> doc;
  doc["box_id"] = BOX_ID;
  time_t now = time(nullptr);
  doc["ts"] = (now > 1600000000) ? (long)now : 0;   // 0 = clock not synced, server uses its own time
  doc["temp_c"] = serialized(String(temp, 2));
  if (!isnan(hum)) doc["hum_pct"] = serialized(String(hum, 1));
  doc["vib_g"] = serialized(String(vib, 3));
  doc["moving"] = moving;
  doc["lid_open"] = lidOpen;
  doc["interval_s"] = INTERVAL_S;
  doc["rssi"] = WiFi.RSSI();

  String json;
  serializeJson(doc, json);
  Serial.println(json);
  enqueue(json);                                    // always queue, flush below
  flushQueue();

  digitalWrite(PIN_ALERT, lidOpen ? HIGH : LOW);    // simple local alert (customise as needed)
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_REED, INPUT_PULLUP);
  pinMode(PIN_ALERT, OUTPUT);
  Wire.begin(21, 22);
  ds18b20.begin();
  dht.begin();
  if (!mpu.begin()) Serial.println("MPU6050 not found");
  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);

  topic = String("coldchain/") + BOX_ID + "/telemetry";
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(512);

  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) delay(300);
  configTime(0, 0, "pool.ntp.org", "time.google.com");   // UTC timestamps
}

void loop() {
  ensureConnections();
  mqtt.loop();
  if (millis() - lastSample >= (unsigned long)INTERVAL_S * 1000UL) {
    lastSample = millis();
    sampleAndSend();
  }
  if (mqtt.connected()) flushQueue();
}
