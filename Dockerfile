# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (Production Ready Solution)
# ═══════════════════════════════════════════════════════════════════

# -------------------------------------------------------------------
# STAGE 1: Builder
# -------------------------------------------------------------------
# Mục đích: Cài đặt dependencies và build wheels.
# Sử dụng base image slim để giảm dung lượng ngay từ giai đoạn này.
FROM python:3.11-slim AS builder

# Thiết lập thư mục làm việc cho stage build
WORKDIR /app

# Yêu cầu: COPY requirements.txt và pip install TRƯỚC khi COPY source code.
# Việc này giúp Docker tận dụng cache layer. Nếu code thay đổi nhưng
# requirements không đổi, bước cài đặt thư viện sẽ không bị chạy lại.
COPY requirements.txt .

# Cài đặt dependencies vào thư mục cục bộ (ví dụ: /install)
# `--no-cache-dir` giúp image không phình to do lưu trữ cache của pip.
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# -------------------------------------------------------------------
# STAGE 2: Runtime (Production Image)
# -------------------------------------------------------------------
# Đây là image cuối cùng sẽ chạy.
FROM python:3.11-slim

# Yêu cầu: Base image slim (đã chọn ở trên). Không dùng bản full.
# Cài đặt curl để phục vụ cho HEALTHCHECK (nếu image gốc chưa có).
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Yêu cầu: Tạo user thường và chuyển sang bằng lệnh USER.
# Không chạy ứng dụng dưới quyền root. Chúng ta tạo user 'appuser'.
ARG USER_ID=1000
ARG GROUP_ID=1000

RUN groupadd -g ${GROUP_ID} appgroup && \
    useradd -l -u ${USER_ID} -g appgroup -ms /bin/bash appuser

# Thiết lập thư mục làm việc
WORKDIR /app

# Copy toàn bộ thư viện đã cài đặt từ stage 'builder' sang stage này.
# Cài vào /usr/local (đọc/thực thi được bởi mọi user). KHÔNG dùng /root/.local:
# thư mục /root có quyền 700 nên appuser không chạy được uvicorn
# ("sh: uvicorn: Permission denied").
COPY --from=builder /install /usr/local

# Copy source code ứng dụng từ máy host vào image
COPY . .

# Yêu cầu: Có HEALTHCHECK gọi vào endpoint /health.
# Kiểm tra mỗi 30 giây, timeout 5 giây, thử lại 3 lần.
# Dùng curl để gọi nội bộ tới cổng $PORT (sẽ được định nghĩa ở ENV).
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:${PORT:-8000}/health || exit 1

# Yêu cầu: Đọc cổng từ biến môi trường PORT.
# Mặc định là 8000 nếu không được cung cấp.
ENV PORT=8000
EXPOSE ${PORT}

# Chuyển sang user thường đã tạo ở trên
USER appuser

# Lệnh khởi chạy ứng dụng. Sử dụng biến môi trường PORT.
# Cần đảm bảo app.main:app trong CMD khớp với cấu trúc project của bạn.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]