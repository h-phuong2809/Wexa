# RBAC Matrix — Website Dự báo Thời tiết

Tài liệu định nghĩa ma trận phân quyền theo vai trò (Role-Based Access Control), dùng làm cơ sở triển khai middleware xác thực/phân quyền tại backend, khớp với `api-spec.yaml` và `usecase-diagram.png`.

## 1. Danh sách vai trò

| Vai trò | Mã | Mô tả |
|---|---|---|
| Khách (chưa đăng nhập) | `guest` | Không có bản ghi USER; xác định qua việc không có token hợp lệ. |
| Thành viên | `member` | Đã đăng ký, đăng nhập bằng JWT. Kế thừa toàn bộ quyền của Guest. |
| Quản trị viên | `admin` | Quản lý hệ thống, dữ liệu API, người dùng. Kế thừa toàn bộ quyền của Member. |

> Ghi chú: `member` và `admin` đều là giá trị của cột `role` trong bảng `app_user`. `guest` là trạng thái ngầm định khi request không kèm `Authorization: Bearer <token>`.

## 2. Ký hiệu

- ✅ = Được phép
- ❌ = Không được phép
- 🟡 = Được phép có điều kiện (xem cột Ghi chú)

## 3. Ma trận phân quyền theo chức năng

| # | Chức năng / Endpoint liên quan | Guest | Member | Admin | Ghi chú |
|---|---|---|---|---|---|
| 1 | Xem thời tiết hiện tại — `GET /weather/current` | ✅ | ✅ | ✅ | Công khai hoàn toàn |
| 2 | Xem dự báo 10 ngày — `GET /weather/forecast/daily` | ✅ | ✅ | ✅ | Công khai |
| 3 | Xem dự báo theo giờ — `GET /weather/forecast/hourly` | ✅ | ✅ | ✅ | Công khai |
| 4 | Xem gió / mặt trời / mặt trăng — `GET /weather/sun`, `/weather/moon` | ✅ | ✅ | ✅ | Công khai |
| 5 | Xem bản đồ mưa (radar) — `GET /weather/rainfall-map` | ✅ | ✅ | ✅ | Công khai |
| 6 | Xem cảnh báo thời tiết theo khu vực — `GET /weather/alerts` | ✅ | ✅ | ✅ | Công khai |
| 7 | Tìm kiếm địa điểm — `GET /locations/search` | ✅ | ✅ | ✅ | Công khai |
| 8 | Đăng ký / Đăng nhập — `POST /auth/register`, `/auth/login` | ✅ | 🟡 | 🟡 | Member/Admin đã đăng nhập không cần gọi lại (chặn ở FE) |
| 9 | Xem danh sách địa điểm đã lưu — `GET /locations/saved` | ❌ | ✅ | ✅ | Yêu cầu `bearerAuth` |
| 10 | Lưu địa điểm yêu thích — `POST /locations/saved` | ❌ | 🟡 | ✅ | Giới hạn tối đa 10 địa điểm/Member (xem `flow-save-location.png`) |
| 11 | Xóa địa điểm đã lưu — `DELETE /locations/saved/{id}` | ❌ | 🟡 | ✅ | Chỉ được xóa địa điểm **của chính mình** (kiểm tra `user_id`) |
| 12 | Xem hồ sơ cá nhân — `GET /users/me` | ❌ | ✅ | ✅ | |
| 13 | Xem/cập nhật cấu hình cá nhân — `GET/PUT /users/me/preferences` | ❌ | ✅ | ✅ | Chỉ áp dụng cho tài khoản của chính mình |
| 14 | Xem danh sách thông báo — `GET /notifications` | ❌ | ✅ | ✅ | Chỉ xem thông báo gửi cho chính mình |
| 15 | Đánh dấu đã đọc thông báo — `POST /notifications/{id}/read` | ❌ | 🟡 | ✅ | Chỉ với thông báo thuộc về mình |
| 16 | Quản lý nhà cung cấp API — `GET/POST /admin/api-providers` | ❌ | ❌ | ✅ | Chỉ Admin |
| 17 | Quản lý người dùng (xem danh sách) — `GET /admin/users` | ❌ | ❌ | ✅ | Chỉ Admin |
| 18 | Tạm khóa người dùng — `POST /admin/users/{id}/suspend` | ❌ | ❌ | ✅ | Ghi vào `AUDIT_LOG`; không tự khóa chính mình |
| 19 | Xem log gọi API bên thứ 3 — `GET /admin/logs/api-requests` | ❌ | ❌ | ✅ | Chỉ Admin |
| 20 | Xem audit log hệ thống — `GET /admin/logs/audit` | ❌ | ❌ | ✅ | Chỉ Admin |
| 21 | Tạo/cấu hình cảnh báo thời tiết thủ công — `POST /admin/alerts` | ❌ | ❌ | ✅ | Chỉ Admin; ghi `AUDIT_LOG` |
| 22 | Bản đồ phân tích trực quan nâng cao (Phase 2) | ✅ | ✅ | ✅ | Dự kiến công khai như các chức năng xem dữ liệu khác |

## 4. Ma trận theo thực thể dữ liệu (Data-level)

| Thực thể | Guest | Member (dữ liệu của chính mình) | Member (dữ liệu người khác) | Admin |
|---|---|---|---|---|
| USER | — | Đọc/Sửa hồ sơ mình | ❌ | Đọc/Sửa/Khóa tất cả |
| USER_PREFERENCE | — | Đọc/Sửa | ❌ | Đọc tất cả (hỗ trợ) |
| LOCATION (`is_saved=true`) | ❌ | Tạo/Đọc/Xóa (giới hạn 10) | ❌ | Đọc tất cả |
| LOCATION (tạm thời, Guest) | Tạo/Đọc (phiên hiện tại) | — | — | Đọc tất cả |
| WEATHER_CURRENT / FORECAST / SUN / MOON / RAINFALL | Đọc (công khai) | Đọc (công khai) | Đọc (công khai) | Đọc/Ghi (qua job đồng bộ) |
| WEATHER_ALERT | Đọc (công khai) | Đọc (công khai) | Đọc (công khai) | Tạo/Sửa/Đóng |
| NOTIFICATION | ❌ | Đọc/Đánh dấu đã đọc (của mình) | ❌ | Đọc tất cả (hỗ trợ), không sửa nội dung |
| API_PROVIDER | ❌ | ❌ | ❌ | Tạo/Sửa/Kích hoạt-Tắt |
| API_REQUEST_LOG | ❌ | ❌ | ❌ | Chỉ đọc |
| AUDIT_LOG | ❌ | ❌ | ❌ | Chỉ đọc (không tự sửa/xóa log của mình) |

## 5. Nguyên tắc thực thi (Enforcement principles)

1. **Xác thực (Authentication):** mọi endpoint không thuộc nhóm "công khai" ở mục 3 bắt buộc middleware kiểm tra JWT hợp lệ (`bearerAuth`) trước khi vào tầng xử lý nghiệp vụ.
2. **Phân quyền theo vai trò (Role check):** endpoint nhóm `/admin/*` bắt buộc kiểm tra `role = 'admin'` sau bước xác thực; trả `403 Forbidden` nếu không đủ quyền — theo đúng response mẫu trong `api-spec.yaml`.
3. **Phân quyền theo chủ sở hữu (Ownership check):** với các thao tác trên LOCATION, NOTIFICATION, USER_PREFERENCE của Member, backend phải đối chiếu `user_id` trong token với `user_id` của bản ghi; không được chỉ dựa vào `role = member`.
4. **Ghi vết (Audit):** mọi hành động Admin làm thay đổi trạng thái hệ thống (khóa user, sửa API_PROVIDER, tạo/đóng WEATHER_ALERT thủ công) bắt buộc ghi 1 bản ghi vào `AUDIT_LOG`.
5. **Nguyên tắc đặc quyền tối thiểu (Least privilege):** Admin mặc định **không** chỉnh sửa trực tiếp dữ liệu thời tiết thô (WEATHER_CURRENT/FORECAST) — dữ liệu này chỉ được ghi bởi job đồng bộ hệ thống (service account riêng), tránh sai lệch dữ liệu thủ công.
6. **Tài khoản Admin đầu tiên:** không có endpoint public để tự đăng ký `role=admin`; tài khoản Admin đầu tiên được tạo qua seed script/migration nội bộ, các Admin tiếp theo chỉ được gán bởi Admin hiện có (ngoài phạm vi API công khai ở bản MVP).
