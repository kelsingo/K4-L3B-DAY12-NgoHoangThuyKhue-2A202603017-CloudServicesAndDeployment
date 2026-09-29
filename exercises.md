# Phiếu Phản Ánh — K4 Level 3B, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng `> *Câu trả lời của bạn*` bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Ngô Hoàng Thụy Khuê  Mã học viên: 2A202603017

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

- Với agent_api_key: str (không mặc định), pydantic ném ValidationError ngay khi Settings() được tạo, nên lỗi hiện ra ở lần deploy đầu tiên và chỉ cần sửa trong vài phút, trước khi có ai gọi API.

- Với mặc định "changeme", app vẫn chạy, health check vẫn xanh. Nhưng URL public đang được bảo vệ bằng một khóa mà ai đọc README hoặc repo cũng biết. Bot chỉ cần gửi X-API-Key: changeme là gọi được /ask và tiêu ngân sách LLM mà không có dấu hiệu lỗi nào.---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

`{"event": "ask_completed", "level": "info", "timestamp": "2026-09-29T06:41:58.123456+00:00", "user_id": "sv01", "cost_usd": 0.0001}
`

Hai việc làm được mà print("đã trả lời xong") không làm được:


- Lọc và tổng hợp theo trường. Tìm event="ask_completed" user_id="sv01" để biết một user gọi bao nhiêu lần, hoặc cộng cost_usd để biết chi phí thật của từng người, vì máy đọc được từng khóa mà không phải đoán trong câu chữ tự do.

- Cảnh báo tự động. Đặt alert khi level="error" (như redis_ping_failed) xuất hiện quá N lần/phút. Câu "đã trả lời xong" không có trường nào để đặt điều kiện, và không phân biệt được lỗi với trạng thái bình thường.---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 317 MB |
| Multi-stage | 412 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Phần chênh lệch là những thứ chỉ cần lúc build mà không cần lúc chạy: cache của pip, công cụ build/biên dịch (gcc, header, wheel tạm) và các file trung gian trong layer của builder. Bản multi-stage chỉ copy thư mục đã cài sẵn (/install) sang image runtime, nên các thứ đó bị bỏ lại ở stage builder. Image nhỏ hơn kéo và khởi động nhanh hơn, và có ít thành phần để kẻ tấn công lợi dụng hơn.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Khi sửa một ký tự trong app/main.py: Dùng lại từ cache: `FROM`, `WORKDIR`, `COPY` `requirements.txt`, `RUN pip install` (vì `requirements.txt` không đổi), và `COPY --from=builder`. -> Chạy lại: layer `COPY` code (nội dung đổi) và mọi layer đứng sau nó. Các bước này rất nhanh. Nếu đặt `COPY . .` lên trước `RUN pip install`: mọi thay đổi ở bất kỳ file nào làm đổi checksum của layer `COPY . .`, nên layer đó và tất cả layer sau nó, gồm cả pip install, bị vô hiệu hóa. Mỗi lần sửa code sẽ tải và cài lại toàn bộ thư viện, mất hàng chục giây đến vài phút thay vì vài giây. Vì vậy thứ tự đúng là copy file ít đổi (`requirements.txt`), cài thư viện, rồi mới copy code hay đổi.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

- Code Python có lỗ hổng (ví dụ deserialize dữ liệu không tin cậy, hoặc chạy lệnh shell với input người dùng). Kẻ tấn công thực thi được lệnh tùy ý trong tiến trình app.

-  Tiến trình đó chạy với UID 0 trong container, nên lệnh của kẻ tấn công cũng có quyền root trong container: đọc/ghi mọi file, cài công cụ, đọc biến môi trường chứa secret.
- Từ root trong container, kẻ tấn công lợi dụng cấu hình yếu (mount `docker.sock`, `--privileged`, thư mục host ghi được, lỗ hổng kernel/runtime) để thoát container và leo sang quyền cao trên máy host, rồi tấn công các container khác. 

`USER` cắt chuỗi ở bước 2: khi bị chiếm, kẻ tấn công chỉ có quyền của user thường, không sửa được file hệ thống, không cài được gói, và nhiều kỹ thuật thoát container đòi hỏi root sẽ không dùng được. Nó không xóa lỗ hổng ở bước 1 nhưng giới hạn tác hại.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

Tối đa 20 request trong 2 giây.
Cách đạt được: cách đếm theo phút đồng hồ reset bộ đếm ở giây 00. Người dùng chờ tới giây 59 của phút N và gửi 10 request, được phép vì bộ đếm phút N chưa đầy. Một giây sau đồng hồ sang giây 00 của phút N+1, bộ đếm về 0, và họ gửi thêm 10 request nữa. Vậy 20 request trong khoảng 2 giây, gấp đôi hạn mức 10/phút.
Sliding window 60 giây tính trên 60 giây gần nhất tại mỗi thời điểm, nên 10 request lúc giây 59 vẫn nằm trong cửa sổ khi giây 00 tới, và request thứ 11 bị 429. Trong bất kỳ khoảng 60 giây nào chỉ có tối đa 10 request.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

- Rate limit giới hạn tốc độ (số request trong 60 giây), bảo vệ khỏi spam/bot và giữ hệ thống ổn định. Trả 429. 
- Cost guard giới hạn tổng chi phí tích lũy trong tháng theo user, bảo vệ ngân sách. Trả 402.

Rate limit cho qua nhưng cost guard chặn: user gửi đều 5 request/phút (dưới hạn mức 10) nhưng mỗi câu hỏi rất dài, tốn nhiều token. Cuối tháng tổng chi phí chạm ngân sách, nên bị 402 dù tốc độ vẫn bình thường.
Ngược lại: user mới, ngân sách còn gần nguyên, chạy script gửi 50 câu hỏi ngắn trong 5 giây. Tổng chi phí chỉ vài cent nên không bị 402, nhưng từ request thứ 11 trở đi bị 429 vì vượt tốc độ.---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Nếu gộp làm một endpoint có kiểm tra Redis, khi Redis mất kết nối 30 giây với cụm 3 container:

- Redis ngắt. Cả 3 container vẫn chạy bình thường, nhưng endpoint gộp bắt đầu trả 503 ở cả 3.

- Orchestrator (liveness probe) thấy cả 3 "không khỏe" sau vài lần thất bại liên tiếp và restart cả 3 container.

- Trong lúc restart không container nào nhận traffic, nên toàn bộ dịch vụ ngừng hẳn dù app không hỏng, chỉ là dependency tạm mất.

- Redis quay lại sau 30 giây nhưng các container vẫn đang khởi động lại, kéo dài downtime và có thể gây restart loop nếu probe quá nhạy.

Tách ra thì đúng: `/health` không kiểm tra Redis nên container không bị restart oan. Chỉ `/ready` trả 503, load balancer tạm ngừng gửi request, và khi Redis phục hồi `/ready` trả 200 lại nên traffic quay về mà không có restart nào.---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Với Redis: history_length tăng đều theo số lượt hỏi của cùng user (2, 4, 6, ..., tối đa 20), bất kể request rơi vào container nào, vì cả 3 container đọc/ghi cùng một List.


Với dict Python: mỗi container có dict riêng trong RAM, và load balancer phân phối luân phiên. Cùng một X-User-Id sẽ cho history_length nhảy lung tung, không tăng đơn điệu, ví dụ 2, 2, 2, 4, 4, 6..., vì mỗi container chỉ biết các lượt nó tự xử lý. Ngữ cảnh hội thoại cũng "mất" mỗi khi request sang container khác, và khi container restart thì lịch sử của nó mất hẳn.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

Lỗi: `sh: 1: uvicorn: Permission denied`

Cách tìm nguyên nhân: đọc Deploy Logs của Railway. "Permission denied" (không phải "not found") nghĩa là file tồn tại nhưng user hiện tại không thực thi được. Đối chiếu với Dockerfile: builder chạy pip install --user nên cài vào /root/.local/bin, rồi runtime chuyển sang USER appuser. Thư mục /root có quyền 700 nên appuser không truy cập được, và cũng không import được module (đó là lý do lần sau báo "No module named uvicorn").


Cách sửa: builder cài vào prefix trung lập bằng pip install --prefix=/install; runtime dùng COPY --from=builder /install /usr/local (mọi user đều đọc/thực thi được) và bỏ ENV PATH=/root/.local/bin. Thêm RUN python -c "import uvicorn, fastapi, redis" để build fail sớm nếu thiếu thư viện. Container vẫn chạy bằng non-root appuser.

