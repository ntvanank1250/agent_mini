# 🤖 AI Agent Telegram Bot - Hệ Thống AI Cá

 Nhân Chạy Local

Hệ thống AI Agent cá nhân chạy hoàn toàn trên máy local (Fedora/Ubuntu) với Telegram Bot + Ollama AI Engine. Tối ưu cho máy 8-16GB RAM.

## ✨ Tính Năng Nổi Bật

- ✅ **Ollama AI Integration**: Model qwen2.5:7b (4.7GB) - tối ưu tiếng Việt
- ✅ **Telegram Bot**: Trò chuyện AI qua Telegram Messenger  
- ✅ **Lưu Trữ Hội Thoại**: SQLite database với lịch sử chat
- ✅ **Hệ Thống Queue**: Xử lý tuần tự requests (tối ưu RAM)
- ✅ **Phân Tích File**: Đọc và tóm tắt file .txt
- ✅ **Giám Sát Hệ Thống**: Kiểm tra RAM/CPU/Queue real-time
- ✅ **Quản Lý Dễ Dàng**: Script tự động start/stop/monitor
- ✅ **Bảo Mật**: Chỉ admin được sử dụng bot

## 🛠️ Yêu Cầu Hệ Thống

```yaml
Hardware:
  CPU: 4-12 cores (khuyến nghị 8+)
  RAM: 8GB tối thiểu, 16GB khuyến nghị
  Disk: 20GB trống (cho model + dữ liệu)
  Network: Kết nối internet ổn định

Hệ Điều Hành:
  - Fedora Linux (đã test)
  - Ubuntu 20.04+ 
  - Debian-based distros
  - CentOS/RHEL 8+

Phần Mềm:
  - Python 3.10+
  - Bash shell
  - curl, git
  - Ollama (script tự động cài)
```

## 🚀 Cài Đặt Nhanh

### Bước 1: Clone Project

```bash
cd ~
git clone <repository-url> agent_mini
cd agent_mini
```

### Bước 2: Cấu Hình Môi Trường

```bash
# Tạo file cấu hình từ template
cp .env.example .env

# Chỉnh sửa thông tin
nano .env
```

**Nội dung `.env` cần điền:**

```env
# Token từ @BotFather trên Telegram
TELEGRAM_API_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz

# Chat ID của bạn (tìm qua @userinfobot)
ADMIN_CHAT_ID=123456789

# Cấu hình Ollama (mặc định OK)
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=qwen2.5:7b

# Hệ thống (giữ nguyên)
MAX_WORKERS=1
QUEUE_CHECK_INTERVAL=2
```

### Bước 3: Chạy Script Cài Đặt

```bash
# Cấp quyền thực thi
chmod +x setup_system.sh

# Chạy script (cần sudo)
sudo ./setup_system.sh
```

**Script sẽ tự động:**
- ✓ Tạo swap file 4GB (nếu chưa có)
- ✓ Cài đặt Ollama AI engine
- ✓ Pull model qwen2.5:7b (~4.7GB, mất 10-20 phút)
- ✓ Tạo Python virtual environment
- ✓ Cài đặt tất cả dependencies
- ✓ Kiểm tra và xác nhận cài đặt thành công

### Bước 4: Khởi Động Bot

```bash
# Cách 1: Sử dụng script quản lý (khuyến nghị)
./manage.sh start

# Cách 2: Khởi động thủ công
source venv/bin/activate
python3 tele_agent.py
```

**Kiểm tra trạng thái:**

```bash
./manage.sh status
```

## 📱 Sử Dụng Bot

### Các Lệnh Telegram

| Lệnh | Chức Năng |
|------|-----------|
| `/start` | Khởi động bot, xem hướng dẫn |
| `/help` | Hiển thị trợ giúp chi tiết |
| `/sys` | Kiểm tra RAM, CPU, queue status |
| `/clear` | Xóa lịch sử hội thoại |

### Ví Dụ Sử Dụng

**Chat Thông Thường:**
```
Bạn: xin chào, bạn là ai?
Bot: Xin chào! Tôi là trợ lý AI chạy local trên máy của bạn...
```

**Kiểm Tra Hệ Thống:**
```
Bạn: /sys
Bot: 📊 SYSTEM STATUS REPORT
     Memory: Total 15.2GB, Used 11.0GB (72%)
     CPU: 12 cores, Usage 45%
     AI Queue: Processing No, Queue 0
     Model: qwen2.5:7b, Threads: 8
```

## 🔧 Quản Lý Hệ Thống

### Script `manage.sh`

```bash
./manage.sh start          # Khởi động Ollama + Bot
./manage.sh stop           # Dừng dịch vụ
./manage.sh restart        # Khởi động lại
./manage.sh status         # Kiểm tra trạng thái
./manage.sh logs-live      # Xem logs real-time
./manage.sh db-backup      # Backup database
./manage.sh db-cleanup     # Dọn dẹp database cũ
```

### Các Script Phụ Trợ

```bash
./start.sh        # Khởi động nhanh
./stop.sh         # Dừng nhanh
./status.sh       # Xem trạng thái
./logs.sh         # Hiển thị logs
./monitor.sh      # Giám sát resources
./quick-install.sh # Cài đặt + start tự động
```

## 📁 Cấu Trúc Project

```
agent_mini/
├── tele_agent.py              # Bot chính (700 dòng)
├── setup_system.sh            # Script cài đặt tự động
├── manage.sh                  # Quản lý hệ thống
├── .env                       # Cấu hình (tạo từ .env.example)
├── requirements.txt           # Python dependencies
│
├── Scripts:
│   ├── start.sh, stop.sh, status.sh
│   ├── logs.sh, monitor.sh
│   └── quick-install.sh
│
├── Data:
│   ├── bot_agent.log          # Log file
│   └── data/
│       ├── chat_history.db    # SQLite
│       └── temp_files/        # Temp folder
│
└── Config:
    ├── .env.example           # Template
    ├── docker-compose.yml     # Web UI
    └── tele_agent.service     # Systemd
```

## ⚙️ Tối Ưu Đã Áp Dụng

**Ollama:**
- Threads: 8 (tận dụng CPU)
- Context: 4096 tokens
- Temperature: 0.7, Top-p: 0.9

**Bot:**
- Lock-based queue (1 worker)
- History: 20 messages
- GC: mỗi 5 responses
- Max message: 4000 chars

**Đã Fix:**
- ✅ 409 Conflict (kill duplicate instances)
- ✅ Chat.action error (thay send_action)  
- ✅ Coroutine split (normalize responses)
- ✅ Queue hang (lock-based processing)
- ✅ Slow response (8 threads + 4K context)
- ✅ Mixed language (Việt-Trung prompt)

## 🐛 Xử Lý Lỗi

### Bot Không Phản Hồi

```bash
# Kill duplicate bots
pkill -f tele_agent.py

# Restart
./manage.sh start
```

### Ollama Lỗi

```bash
# Kiểm tra
ollama list
ollama ps

# Restart
ollama serve &
```

### Bot Chậm

```bash
# Xem logs
tail -50 bot_agent.log

# Kiểm tra RAM
free -h

# Restart
./manage.sh restart
```

## 🔑 Lấy Token & Chat ID

### Token Telegram

1. Mở @BotFather
2. `/newbot` → đặt tên/username
3. Copy token vào `.env`

### Chat ID

1. Mở @userinfobot  
2. `/start` → lấy ID
3. Copy vào `.env`

## 📊 Giám Sát

```bash
# Logs real-time
tail -f bot_agent.log

# Database
sqlite3 data/chat_history.db "SELECT * FROM conversations LIMIT 10;"

# Resources
./monitor.sh
```

## 🚀 Nâng Cao

### Chạy Service

```bash
sudo cp tele_agent.service /etc/systemd/system/
sudo systemctl enable tele_agent
sudo systemctl start tele_agent
```

### Thay Model

```bash
ollama pull mistral
nano .env  # OLLAMA_MODEL=mistral
./manage.sh restart
```

### Tùy Chỉnh Prompt

Sửa `tele_agent.py` dòng ~360:
```python
system_prompt = """Bạn là chuyên gia Python..."""
```

## 📚 Tài Liệu

- [Ollama Docs](https://ollama.ai/docs)
- [python-telegram-bot](https://docs.python-telegram-bot.org)
- [Qwen2.5 Model](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct)

## 🤝 Hỗ Trợ

**Checklist Debug:**
- [ ] Files `.env` đúng token/chat ID?
- [ ] Ollama running? (`pgrep ollama`)
- [ ] Bot running? (`pgrep tele_agent`)
- [ ] Venv activated?
- [ ] Dependencies installed?
- [ ] No duplicate bots?

## 📝 License

MIT License - Free for personal/commercial use

---

**Tận hưởng AI của riêng bạn! 🚀**

Made with ❤️ for Vietnamese AI Community
