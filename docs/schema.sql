-- ============================================================================
-- Website Dự báo Thời tiết — Database Schema (PostgreSQL 14+)
-- Đồng bộ với entities.md và erd.png
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- for gen_random_uuid()

-- ============================================================================
-- ENUM TYPES
-- ============================================================================
CREATE TYPE user_role        AS ENUM ('member', 'admin');
CREATE TYPE user_status      AS ENUM ('active', 'suspended', 'deleted');
CREATE TYPE unit_temp_type   AS ENUM ('celsius', 'fahrenheit');
CREATE TYPE unit_wind_type   AS ENUM ('kmh', 'mph');
CREATE TYPE theme_type       AS ENUM ('light', 'dark', 'auto');
CREATE TYPE rainfall_layer_type   AS ENUM ('radar', 'satellite');
CREATE TYPE alert_severity   AS ENUM ('info', 'warning', 'severe', 'extreme');
CREATE TYPE alert_status     AS ENUM ('detected', 'active', 'escalated', 'expired', 'resolved', 'archived');
CREATE TYPE notification_type   AS ENUM ('alert', 'reminder', 'system');
CREATE TYPE notification_status AS ENUM ('created', 'sent', 'read', 'dismissed');

-- ============================================================================
-- 1. USER
-- ============================================================================
CREATE TABLE app_user (
    user_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    VARCHAR(120) NOT NULL,
    email                   VARCHAR(255) NOT NULL,
    password_hash           VARCHAR(255) NOT NULL,
    avatar_url              VARCHAR(500),
    role                    user_role NOT NULL DEFAULT 'member',
    status                  user_status NOT NULL DEFAULT 'active',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_email UNIQUE (email)
);
CREATE INDEX idx_user_role_status ON app_user (role, status);

-- ============================================================================
-- 2. USER_PREFERENCE
-- ============================================================================
CREATE TABLE user_preference (
    preference_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL,
    unit_temp               unit_temp_type NOT NULL DEFAULT 'celsius',
    unit_wind               unit_wind_type NOT NULL DEFAULT 'kmh',
    language                VARCHAR(5) NOT NULL DEFAULT 'vi',
    theme                   theme_type NOT NULL DEFAULT 'auto',
    alert_opt_in            BOOLEAN NOT NULL DEFAULT true,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_pref_user FOREIGN KEY (user_id) REFERENCES app_user (user_id) ON DELETE CASCADE,
    CONSTRAINT uq_pref_user UNIQUE (user_id)
);

-- ============================================================================
-- 3. LOCATION
-- ============================================================================
CREATE TABLE location (
    location_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NULL,
    name                    VARCHAR(200) NOT NULL,
    country_code            CHAR(2) NOT NULL,
    latitude                DECIMAL(9,6) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude               DECIMAL(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    timezone                VARCHAR(50) NOT NULL,
    is_current              BOOLEAN NOT NULL DEFAULT false,
    is_saved                BOOLEAN NOT NULL DEFAULT false,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_location_user FOREIGN KEY (user_id) REFERENCES app_user (user_id) ON DELETE CASCADE
);
CREATE INDEX idx_location_user_saved ON location (user_id, is_saved);
CREATE INDEX idx_location_coords ON location (latitude, longitude);

-- Ràng buộc nghiệp vụ "tối đa 10 địa điểm đã lưu / user" được thực thi ở tầng
-- ứng dụng (xem flow-save-location.png) hoặc bằng trigger tùy chọn bên dưới:
-- CREATE OR REPLACE FUNCTION check_saved_location_limit() RETURNS TRIGGER AS $$
-- BEGIN
--   IF NEW.is_saved = true AND (
--        SELECT COUNT(*) FROM location WHERE user_id = NEW.user_id AND is_saved = true
--      ) >= 10 THEN
--     RAISE EXCEPTION 'Đã đạt giới hạn 10 địa điểm đã lưu';
--   END IF;
--   RETURN NEW;
-- END; $$ LANGUAGE plpgsql;
-- CREATE TRIGGER trg_check_saved_location_limit
--   BEFORE INSERT ON location FOR EACH ROW EXECUTE FUNCTION check_saved_location_limit();

-- ============================================================================
-- 13. API_PROVIDER  (khai báo trước vì được tham chiếu bởi WEATHER_CURRENT/ALERT)
-- ============================================================================
CREATE TABLE api_provider (
    provider_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    VARCHAR(100) NOT NULL,
    base_url                VARCHAR(300) NOT NULL,
    api_key_ref             VARCHAR(200),
    rate_limit_per_min      INT,
    priority                SMALLINT NOT NULL DEFAULT 1,
    is_active               BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT uq_provider_name UNIQUE (name)
);

-- ============================================================================
-- 4. WEATHER_CURRENT
-- ============================================================================
CREATE TABLE weather_current (
    weather_current_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id             UUID NOT NULL,
    temperature             DECIMAL(4,1) NOT NULL,
    feels_like              DECIMAL(4,1),
    condition_code          VARCHAR(30) NOT NULL,
    condition_desc          VARCHAR(200),
    humidity                SMALLINT CHECK (humidity BETWEEN 0 AND 100),
    uv_index                DECIMAL(3,1),
    visibility_km           DECIMAL(5,2),
    pressure_hpa            DECIMAL(6,1),
    provider_id             UUID,
    fetched_at              TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_wc_location FOREIGN KEY (location_id) REFERENCES location (location_id) ON DELETE CASCADE,
    CONSTRAINT fk_wc_provider FOREIGN KEY (provider_id) REFERENCES api_provider (provider_id) ON DELETE SET NULL,
    CONSTRAINT uq_wc_location UNIQUE (location_id)
);

-- ============================================================================
-- 5. WIND_DATA
-- ============================================================================
CREATE TABLE wind_data (
    wind_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    weather_current_id      UUID NOT NULL,
    speed_kmh               DECIMAL(5,1) NOT NULL,
    gust_kmh                DECIMAL(5,1),
    direction_deg           SMALLINT CHECK (direction_deg BETWEEN 0 AND 360),
    direction_label         VARCHAR(3),
    CONSTRAINT fk_wind_wc FOREIGN KEY (weather_current_id) REFERENCES weather_current (weather_current_id) ON DELETE CASCADE,
    CONSTRAINT uq_wind_wc UNIQUE (weather_current_id)
);

-- ============================================================================
-- 6. WEATHER_DAILY_FORECAST
-- ============================================================================
CREATE TABLE weather_daily_forecast (
    daily_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id             UUID NOT NULL,
    forecast_date           DATE NOT NULL,
    temp_min                DECIMAL(4,1) NOT NULL,
    temp_max                DECIMAL(4,1) NOT NULL,
    condition_code          VARCHAR(30) NOT NULL,
    precipitation_prob      SMALLINT CHECK (precipitation_prob BETWEEN 0 AND 100),
    precipitation_mm        DECIMAL(6,2),
    uv_index_max            DECIMAL(3,1),
    CONSTRAINT fk_daily_location FOREIGN KEY (location_id) REFERENCES location (location_id) ON DELETE CASCADE,
    CONSTRAINT uq_daily_location_date UNIQUE (location_id, forecast_date)
);
CREATE INDEX idx_daily_location_date ON weather_daily_forecast (location_id, forecast_date);

-- ============================================================================
-- 7. WEATHER_HOURLY_FORECAST
-- ============================================================================
CREATE TABLE weather_hourly_forecast (
    hourly_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    daily_id                UUID NOT NULL,
    datetime                TIMESTAMPTZ NOT NULL,
    temp                    DECIMAL(4,1) NOT NULL,
    precipitation_mm        DECIMAL(6,2),
    wind_speed              DECIMAL(5,1),
    condition_code          VARCHAR(30),
    CONSTRAINT fk_hourly_daily FOREIGN KEY (daily_id) REFERENCES weather_daily_forecast (daily_id) ON DELETE CASCADE,
    CONSTRAINT uq_hourly_daily_dt UNIQUE (daily_id, datetime)
);
CREATE INDEX idx_hourly_daily ON weather_hourly_forecast (daily_id);

-- ============================================================================
-- 8. SUN_DATA
-- ============================================================================
CREATE TABLE sun_data (
    sun_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id             UUID NOT NULL,
    date                    DATE NOT NULL,
    sunrise_time            TIME NOT NULL,
    sunset_time             TIME NOT NULL,
    CONSTRAINT fk_sun_location FOREIGN KEY (location_id) REFERENCES location (location_id) ON DELETE CASCADE,
    CONSTRAINT uq_sun_location_date UNIQUE (location_id, date)
);

-- ============================================================================
-- 9. MOON_DATA
-- ============================================================================
CREATE TABLE moon_data (
    moon_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id             UUID NOT NULL,
    date                    DATE NOT NULL,
    moon_phase              VARCHAR(30) NOT NULL,
    illumination_pct        SMALLINT CHECK (illumination_pct BETWEEN 0 AND 100),
    moonrise_time           TIME,
    moonset_time            TIME,
    CONSTRAINT fk_moon_location FOREIGN KEY (location_id) REFERENCES location (location_id) ON DELETE CASCADE,
    CONSTRAINT uq_moon_location_date UNIQUE (location_id, date)
);

-- ============================================================================
-- 10. RAINFALL_MAP_LAYER
-- ============================================================================
CREATE TABLE rainfall_map_layer (
    layer_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id             UUID NOT NULL,
    timestamp               TIMESTAMPTZ NOT NULL,
    tile_layer_url          VARCHAR(500) NOT NULL,
    layer_type              rainfall_layer_type NOT NULL,
    intensity_level         VARCHAR(20),
    CONSTRAINT fk_rain_location FOREIGN KEY (location_id) REFERENCES location (location_id) ON DELETE CASCADE
);
CREATE INDEX idx_rain_location_ts ON rainfall_map_layer (location_id, timestamp DESC);

-- ============================================================================
-- 11. WEATHER_ALERT
-- ============================================================================
CREATE TABLE weather_alert (
    alert_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id             UUID NOT NULL,
    alert_type              VARCHAR(50) NOT NULL,
    severity                alert_severity NOT NULL,
    title                   VARCHAR(200) NOT NULL,
    description             TEXT,
    provider_id             UUID,
    starts_at               TIMESTAMPTZ NOT NULL,
    ends_at                 TIMESTAMPTZ,
    status                  alert_status NOT NULL DEFAULT 'detected',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_alert_location FOREIGN KEY (location_id) REFERENCES location (location_id) ON DELETE CASCADE,
    CONSTRAINT fk_alert_provider FOREIGN KEY (provider_id) REFERENCES api_provider (provider_id) ON DELETE SET NULL
);
CREATE INDEX idx_alert_location_status ON weather_alert (location_id, status);

-- ============================================================================
-- 12. NOTIFICATION
-- ============================================================================
CREATE TABLE notification (
    notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL,
    alert_id                UUID NULL,
    location_id             UUID NOT NULL,
    type                    notification_type NOT NULL,
    message                 TEXT NOT NULL,
    status                  notification_status NOT NULL DEFAULT 'created',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at                 TIMESTAMPTZ,
    CONSTRAINT fk_notif_user FOREIGN KEY (user_id) REFERENCES app_user (user_id) ON DELETE CASCADE,
    CONSTRAINT fk_notif_alert FOREIGN KEY (alert_id) REFERENCES weather_alert (alert_id) ON DELETE SET NULL,
    CONSTRAINT fk_notif_location FOREIGN KEY (location_id) REFERENCES location (location_id) ON DELETE CASCADE
);
CREATE INDEX idx_notif_user_status ON notification (user_id, status);

-- ============================================================================
-- 14. API_REQUEST_LOG
-- ============================================================================
CREATE TABLE api_request_log (
    log_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id             UUID NOT NULL,
    endpoint                VARCHAR(300) NOT NULL,
    status_code             SMALLINT NOT NULL,
    response_time_ms        INT,
    requested_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_log_provider FOREIGN KEY (provider_id) REFERENCES api_provider (provider_id) ON DELETE CASCADE
);
CREATE INDEX idx_log_provider_time ON api_request_log (provider_id, requested_at DESC);

-- ============================================================================
-- 15. AUDIT_LOG
-- ============================================================================
CREATE TABLE audit_log (
    audit_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id                UUID NOT NULL,
    action                  VARCHAR(100) NOT NULL,
    target_entity           VARCHAR(50) NOT NULL,
    target_id               UUID,
    detail                  JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_audit_admin FOREIGN KEY (admin_id) REFERENCES app_user (user_id) ON DELETE CASCADE
);
CREATE INDEX idx_audit_admin_time ON audit_log (admin_id, created_at DESC);

-- ============================================================================
-- SEED DATA (ví dụ khởi tạo API_PROVIDER)
-- ============================================================================
INSERT INTO api_provider (name, base_url, rate_limit_per_min, priority, is_active) VALUES
    ('Open-Meteo', 'https://api.open-meteo.com', 600, 1, true),
    ('OpenWeatherMap', 'https://api.openweathermap.org', 60, 2, true);

-- ============================================================================
-- TRIGGER: tự động cập nhật updated_at
-- ============================================================================
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_updated_at
  BEFORE UPDATE ON app_user
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

