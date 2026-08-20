# Entities Specification — Website Dự báo Thời tiết

Tài liệu mô tả chi tiết 15 thực thể dữ liệu (entities), thuộc tính, kiểu dữ liệu, ràng buộc nghiệp vụ và quan hệ. Đây là nguồn tham chiếu cho `schema.sql` và `erd.png`.

---

## 1. USER
Tài khoản người dùng đã đăng ký (Member hoặc Admin). Khách vãng lai (Guest) **không** có bản ghi trong bảng này.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| user_id | UUID | PK | Định danh người dùng |
| name | VARCHAR(120) | NOT NULL | Tên hiển thị |
| email | VARCHAR(255) | UNIQUE, NOT NULL | Email đăng nhập |
| password_hash | VARCHAR(255) | NOT NULL | Mật khẩu đã băm (bcrypt/argon2) |
| avatar_url | VARCHAR(500) | NULL | Ảnh đại diện |
| role | ENUM('member','admin') | NOT NULL, DEFAULT 'member' | Vai trò trong hệ thống |
| status | ENUM('active','suspended','deleted') | NOT NULL, DEFAULT 'active' | Trạng thái tài khoản |
| created_at | TIMESTAMP | NOT NULL, DEFAULT now() | Thời điểm tạo |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT now() | Thời điểm cập nhật gần nhất |

**Business rules**
- Email phải duy nhất trong toàn hệ thống, không phân biệt hoa/thường.
- Tài khoản `status = suspended` không được đăng nhập nhưng dữ liệu vẫn giữ nguyên.
- Vai trò `admin` chỉ được gán thủ công bởi admin khác (không có API tự đăng ký admin).

---

## 2. USER_PREFERENCE
Cấu hình cá nhân hóa, quan hệ 1-1 với USER.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| preference_id | UUID | PK | Định danh |
| user_id | UUID | FK → USER.user_id, UNIQUE, NOT NULL | Chủ sở hữu |
| unit_temp | ENUM('celsius','fahrenheit') | DEFAULT 'celsius' | Đơn vị nhiệt độ |
| unit_wind | ENUM('kmh','mph') | DEFAULT 'kmh' | Đơn vị tốc độ gió |
| language | VARCHAR(5) | DEFAULT 'vi' | Ngôn ngữ hiển thị |
| theme | ENUM('light','dark','auto') | DEFAULT 'auto' | Giao diện |
| alert_opt_in | BOOLEAN | DEFAULT true | Có nhận thông báo cảnh báo thời tiết không |
| updated_at | TIMESTAMP | DEFAULT now() | Cập nhật gần nhất |

**Business rules**
- Được tạo tự động (giá trị mặc định) ngay khi USER đăng ký thành công.
- `alert_opt_in = false` khiến hệ thống bỏ qua người dùng này trong luồng tạo NOTIFICATION cảnh báo.

---

## 3. LOCATION
Địa điểm được theo dõi thời tiết — có thể là vị trí GPS tạm thời (Guest/Member) hoặc địa điểm đã lưu (Member).

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| location_id | UUID | PK | Định danh địa điểm |
| user_id | UUID | FK → USER.user_id, NULL | NULL nếu là vị trí tạm thời của Guest |
| name | VARCHAR(200) | NOT NULL | Tên hiển thị (Thành phố, Quốc gia) |
| country_code | CHAR(2) | NOT NULL | Mã quốc gia ISO-3166 |
| latitude | DECIMAL(9,6) | NOT NULL | Vĩ độ |
| longitude | DECIMAL(9,6) | NOT NULL | Kinh độ |
| timezone | VARCHAR(50) | NOT NULL | Múi giờ IANA (vd: Asia/Ho_Chi_Minh) |
| is_current | BOOLEAN | DEFAULT false | Có phải vị trí GPS hiện tại của phiên làm việc |
| is_saved | BOOLEAN | DEFAULT false | Có được lưu vào danh sách yêu thích |
| created_at | TIMESTAMP | DEFAULT now() | Thời điểm tạo |

**Business rules**
- Một Member được lưu tối đa **10** địa điểm (`is_saved = true`); vượt ngưỡng phải báo lỗi (xem `flow-save-location.png`).
- Vị trí GPS tạm thời (Guest, `user_id NULL`, `is_current = true`) có thể được dọn dẹp định kỳ (TTL) nếu không được lưu lại.
- Cặp (latitude, longitude) làm tròn 6 chữ số thập phân dùng để khử trùng khi tìm kiếm địa điểm đã tồn tại.

---

## 4. WEATHER_CURRENT
Snapshot thời tiết hiện tại của một LOCATION (quan hệ 1-1, luôn được ghi đè/upsert bởi bản ghi mới nhất).

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| weather_current_id | UUID | PK | Định danh |
| location_id | UUID | FK → LOCATION.location_id, UNIQUE, NOT NULL | Địa điểm |
| temperature | DECIMAL(4,1) | NOT NULL | Nhiệt độ thực tế (°C) |
| feels_like | DECIMAL(4,1) | NULL | Nhiệt độ cảm nhận |
| condition_code | VARCHAR(30) | NOT NULL | Mã điều kiện (xem Phụ lục SRS) |
| condition_desc | VARCHAR(200) | NULL | Mô tả chi tiết |
| humidity | SMALLINT | CHECK (0-100) | Độ ẩm (%) |
| uv_index | DECIMAL(3,1) | NULL | Chỉ số UV |
| visibility_km | DECIMAL(5,2) | NULL | Tầm nhìn (km) |
| pressure_hpa | DECIMAL(6,1) | NULL | Áp suất khí quyển |
| provider_id | UUID | FK → API_PROVIDER.provider_id | Nguồn dữ liệu |
| fetched_at | TIMESTAMP | NOT NULL | Thời điểm dữ liệu được lấy |

**Business rules**
- Chỉ giữ **1** bản ghi mới nhất/location (upsert theo `location_id`); lịch sử (nếu cần) lưu ở bảng phân tích riêng ngoài phạm vi MVP.
- Dữ liệu được coi là "stale" (cũ) nếu `fetched_at` quá 30 phút — client hiển thị cảnh báo dữ liệu chưa cập nhật.

---

## 5. WIND_DATA
Chi tiết gió, quan hệ 1-1 với WEATHER_CURRENT.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| wind_id | UUID | PK | Định danh |
| weather_current_id | UUID | FK, UNIQUE, NOT NULL | Tham chiếu WEATHER_CURRENT |
| speed_kmh | DECIMAL(5,1) | NOT NULL | Tốc độ gió trung bình |
| gust_kmh | DECIMAL(5,1) | NULL | Tốc độ gió giật |
| direction_deg | SMALLINT | CHECK (0-360) | Hướng gió theo độ |
| direction_label | VARCHAR(3) | NULL | N, NE, E, SE, S, SW, W, NW |

---

## 6. WEATHER_DAILY_FORECAST
Dự báo theo ngày (10 ngày tới) cho một LOCATION.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| daily_id | UUID | PK | Định danh |
| location_id | UUID | FK → LOCATION.location_id, NOT NULL | Địa điểm |
| forecast_date | DATE | NOT NULL | Ngày dự báo |
| temp_min | DECIMAL(4,1) | NOT NULL | Nhiệt độ thấp nhất |
| temp_max | DECIMAL(4,1) | NOT NULL | Nhiệt độ cao nhất |
| condition_code | VARCHAR(30) | NOT NULL | Mã điều kiện |
| precipitation_prob | SMALLINT | CHECK (0-100) | Xác suất mưa (%) |
| precipitation_mm | DECIMAL(6,2) | NULL | Lượng mưa dự kiến |
| uv_index_max | DECIMAL(3,1) | NULL | Chỉ số UV cao nhất trong ngày |

**Business rules**
- UNIQUE (`location_id`, `forecast_date`) — mỗi ngày chỉ có 1 bản ghi/địa điểm, upsert khi đồng bộ lại.
- Chỉ giữ tối đa 10 bản ghi tương lai gần nhất/location; bản ghi quá khứ có thể xóa định kỳ (job dọn dẹp).

---

## 7. WEATHER_HOURLY_FORECAST
Dự báo chi tiết theo giờ, thuộc về 1 WEATHER_DAILY_FORECAST.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| hourly_id | UUID | PK | Định danh |
| daily_id | UUID | FK → WEATHER_DAILY_FORECAST.daily_id, NOT NULL | Ngày dự báo cha |
| datetime | TIMESTAMP | NOT NULL | Thời điểm dự báo |
| temp | DECIMAL(4,1) | NOT NULL | Nhiệt độ dự kiến |
| precipitation_mm | DECIMAL(6,2) | NULL | Lượng mưa dự kiến |
| wind_speed | DECIMAL(5,1) | NULL | Tốc độ gió dự kiến |
| condition_code | VARCHAR(30) | NULL | Mã điều kiện |

---

## 8. SUN_DATA
Giờ mặt trời mọc/lặn theo ngày cho 1 LOCATION.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| sun_id | UUID | PK | Định danh |
| location_id | UUID | FK, NOT NULL | Địa điểm |
| date | DATE | NOT NULL | Ngày áp dụng |
| sunrise_time | TIME | NOT NULL | Giờ mặt trời mọc (giờ địa phương) |
| sunset_time | TIME | NOT NULL | Giờ mặt trời lặn |

UNIQUE (`location_id`, `date`).

---

## 9. MOON_DATA
Thông tin mặt trăng theo ngày cho 1 LOCATION.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| moon_id | UUID | PK | Định danh |
| location_id | UUID | FK, NOT NULL | Địa điểm |
| date | DATE | NOT NULL | Ngày áp dụng |
| moon_phase | VARCHAR(30) | NOT NULL | Pha mặt trăng (new_moon, waxing_crescent, full_moon...) |
| illumination_pct | SMALLINT | CHECK (0-100) | Phần trăm bề mặt chiếu sáng |
| moonrise_time | TIME | NULL | Giờ mặt trăng mọc (có thể không có trong ngày) |
| moonset_time | TIME | NULL | Giờ mặt trăng lặn |

UNIQUE (`location_id`, `date`). Tính toán bằng thư viện thiên văn (vd. SunCalc) dựa trên tọa độ + ngày giờ, không phụ thuộc API thời tiết.

---

## 10. RAINFALL_MAP_LAYER
Lớp dữ liệu bản đồ mưa/radar trực quan cho 1 LOCATION.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| layer_id | UUID | PK | Định danh |
| location_id | UUID | FK, NOT NULL | Địa điểm trung tâm bản đồ |
| timestamp | TIMESTAMP | NOT NULL | Thời điểm ảnh radar/vệ tinh |
| tile_layer_url | VARCHAR(500) | NOT NULL | URL lớp tile bản đồ |
| layer_type | ENUM('radar','satellite') | NOT NULL | Loại lớp bản đồ |
| intensity_level | VARCHAR(20) | NULL | Mức cường độ mưa tổng quan (light/moderate/heavy) |

---

## 11. WEATHER_ALERT
Cảnh báo thời tiết ở cấp hệ thống (độc lập với từng người dùng), gắn với 1 LOCATION/khu vực.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| alert_id | UUID | PK | Định danh |
| location_id | UUID | FK, NOT NULL | Khu vực ảnh hưởng |
| alert_type | VARCHAR(50) | NOT NULL | Loại cảnh báo (storm, heavy_rain, heatwave...) |
| severity | ENUM('info','warning','severe','extreme') | NOT NULL | Mức độ nghiêm trọng |
| title | VARCHAR(200) | NOT NULL | Tiêu đề cảnh báo |
| description | TEXT | NULL | Mô tả chi tiết |
| provider_id | UUID | FK → API_PROVIDER.provider_id, NULL | Nguồn phát hiện (nếu từ API) |
| starts_at | TIMESTAMP | NOT NULL | Thời điểm bắt đầu hiệu lực |
| ends_at | TIMESTAMP | NULL | Thời điểm hết hiệu lực dự kiến |
| status | ENUM('detected','active','escalated','expired','resolved','archived') | NOT NULL, DEFAULT 'detected' | Trạng thái (xem `state-diagram.png`) |
| created_at | TIMESTAMP | DEFAULT now() | Thời điểm tạo |

**Business rules**
- Vòng đời trạng thái bắt buộc tuân theo `state-diagram.png` — không được nhảy trực tiếp từ `detected` sang `resolved`.
- Chỉ NOTIFICATION được tạo khi `status` chuyển sang `active` hoặc `escalated`.

---

## 12. NOTIFICATION
Thông báo gửi tới từng USER, có thể liên kết với 1 WEATHER_ALERT hoặc là nhắc nhở/thông báo hệ thống.

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| notification_id | UUID | PK | Định danh |
| user_id | UUID | FK → USER.user_id, NOT NULL | Người nhận |
| alert_id | UUID | FK → WEATHER_ALERT.alert_id, NULL | Cảnh báo liên quan (nếu có) |
| location_id | UUID | FK → LOCATION.location_id, NOT NULL | Địa điểm liên quan |
| type | ENUM('alert','reminder','system') | NOT NULL | Loại thông báo |
| message | TEXT | NOT NULL | Nội dung |
| status | ENUM('created','sent','read','dismissed') | NOT NULL, DEFAULT 'created' | Trạng thái gửi/đọc |
| created_at | TIMESTAMP | DEFAULT now() | Thời điểm tạo |
| read_at | TIMESTAMP | NULL | Thời điểm người dùng đọc |

---

## 13. API_PROVIDER
Cấu hình nhà cung cấp dữ liệu thời tiết bên thứ 3 (quản lý bởi Admin).

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| provider_id | UUID | PK | Định danh |
| name | VARCHAR(100) | NOT NULL | Tên nhà cung cấp (Open-Meteo, OpenWeatherMap...) |
| base_url | VARCHAR(300) | NOT NULL | Base URL của API |
| api_key_ref | VARCHAR(200) | NULL | Tham chiếu tới secret lưu key (không lưu key thô trong DB) |
| rate_limit_per_min | INT | NULL | Giới hạn số lượt gọi/phút |
| priority | SMALLINT | NOT NULL, DEFAULT 1 | Thứ tự ưu tiên gọi (1 = cao nhất) |
| is_active | BOOLEAN | DEFAULT true | Đang được sử dụng hay tạm tắt |

---

## 14. API_REQUEST_LOG
Nhật ký các lượt gọi tới API_PROVIDER, phục vụ theo dõi hiệu năng/lỗi (Admin).

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| log_id | UUID | PK | Định danh |
| provider_id | UUID | FK → API_PROVIDER.provider_id, NOT NULL | Nhà cung cấp được gọi |
| endpoint | VARCHAR(300) | NOT NULL | Endpoint được gọi |
| status_code | SMALLINT | NOT NULL | Mã HTTP trả về |
| response_time_ms | INT | NULL | Thời gian phản hồi |
| requested_at | TIMESTAMP | DEFAULT now() | Thời điểm gọi |

Bảng này nên có chiến lược xoay vòng/lưu trữ (partition theo tháng) vì tăng trưởng nhanh.

---

## 15. AUDIT_LOG
Nhật ký hành động quản trị, phục vụ truy vết trách nhiệm (Admin).

| Trường | Kiểu | Ràng buộc | Mô tả |
|---|---|---|---|
| audit_id | UUID | PK | Định danh |
| admin_id | UUID | FK → USER.user_id, NOT NULL | Admin thực hiện hành động |
| action | VARCHAR(100) | NOT NULL | Hành động (vd: UPDATE_API_PROVIDER, SUSPEND_USER) |
| target_entity | VARCHAR(50) | NOT NULL | Thực thể bị tác động |
| target_id | UUID | NULL | ID bản ghi bị tác động |
| detail | JSONB | NULL | Chi tiết thay đổi (before/after) |
| created_at | TIMESTAMP | DEFAULT now() | Thời điểm |

---

## Tổng hợp quan hệ chính

```
USER (1) ── (1) USER_PREFERENCE
USER (1) ── (N) LOCATION
USER (1) ── (N) NOTIFICATION
USER (1) ── (N) AUDIT_LOG            [chỉ admin_id]
LOCATION (1) ── (1) WEATHER_CURRENT
WEATHER_CURRENT (1) ── (1) WIND_DATA
LOCATION (1) ── (N) WEATHER_DAILY_FORECAST
WEATHER_DAILY_FORECAST (1) ── (N) WEATHER_HOURLY_FORECAST
LOCATION (1) ── (N) SUN_DATA
LOCATION (1) ── (N) MOON_DATA
LOCATION (1) ── (N) RAINFALL_MAP_LAYER
LOCATION (1) ── (N) WEATHER_ALERT
WEATHER_ALERT (1) ── (N) NOTIFICATION
API_PROVIDER (1) ── (N) WEATHER_CURRENT
API_PROVIDER (1) ── (N) WEATHER_ALERT
API_PROVIDER (1) ── (N) API_REQUEST_LOG
```

Xem sơ đồ trực quan đầy đủ tại `erd.png`.
