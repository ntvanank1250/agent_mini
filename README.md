# 🤖 AI Agent Telegram Bot - Chạy Ollama Local

Hệ thống AI Agent cá nhân hoàn toàn **chạy cục bộ** (Local) trên Linux 8GB RAM, tích hợp Telegram Bot, Ollama AI Engine qwen2.5:7b, và quản lý người dùng whitelist.

**Ngôn ngữ:** Tiếng Việt tối ưu | **Model:** qwen2.5:7b (4.7GB) | **Thread:** 8 cores | **DB:** SQLite

## 📋 Tính Năng Chính

### 🤖 AI & Chat
- ✅ **Ollama qwen2.5:7b** - Model tối ưu tiếng Việt, chạy trên CPU
- ✅ **Telegram Interface** - Tương tác trực tiếp qua Telegram
- ✅ **Conversation Memory** - Lưu lịch sử 20 messages gần nhất
- ✅ **Vietnamese Enforced** - System prompt bắt buộc trả lời tiếng Việt
- ✅ **File Analysis** - Tải lên file .txt để phân tích nội dung

### 🔐 Quản Lý Người Dùng
- ✅ **Whitelist System** - Admin thêm/xóa người dùng có quyền
- ✅ **/add <chat_id>** - Thêm người dùng vào danh sách trắng
- ✅ **/remove <chat_id>** - Xóa người dùng khỏi danh sách
- ✅ **/whitelist** - Xem danh sách người dùng được phép

### ⚙️ Hệ Thống
- ✅ **Queue System** - Xử lý 1 request AI tại một lúc (lock-based)
- ✅ **System Monitor** - Kiểm tra RAM/CPU real-time (/sys)
- ✅ **Garbage Collection** - Tự động giải phóng bộ nhớ
- ✅ **Optimization** - 8 threads, context 4096, temperature 0.3
- ✅ **Auto-restart** - Quản lý script (start/stop/status)

## 🛠️ Yêu Cầu Hệ Thống

```
Hardware:
  - CPU: 12 cores (tối ưu), tối thiểu 4 cores
  - RAM: 15GB total (11GB Ollama+Python, 4GB swap)
  - Disk: 20GB minimum (4.7GB model + data)
  - OS: Linux (Fedora, Ubuntu, Debian)

Đã test trên:
  ✓ Fedora 41 - 12 cores, 15GB RAM
  ✓ Intel 8-core CPU
```

## 🚀 Cài Đặt & Chạy

### Option 1: Automatic Setup (Khuyến nghị)

```bash
cd /home/hieudd/code/agent_mini

# Copy config template
cp .env.example .env

# Chỉnh sửa .env - thêm Telegram bot token
nano .env
# TELEGRAM_API_TOKEN=your_bot_token_here
# ADMIN_CHAT_ID=your_chat_id

# Chạy setup (cài Ollama, Python packages, venv)
chmod +x setup_system.sh
sudo ./setup_system.sh

# Khởi động bot
./manage.sh start

# Kiểm tra trạng thái
./manage.sh status
```

### Option 2: Manual Setup

```bash
# 1. Cài Ollama
curl https://ollama.ai/install.sh | sh

# 2. Tải model
ollama pull qwen2.5:7b

# 3. Khởi động Ollama
ollama serve &

# 4. Cài Python packages
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 5. Thiết lập .env
cp .env.example .env
nano .env  # thêm TELEGRAM_API_TOKEN

# 6. Chạy bot
source venv/bin/activate
python3 tele_agent.py
```

## 📱 Các Lệnh Telegram

### Cho Admin

| Lệnh | Mô Tả | Ví Dụ |
|------|-------|-------|
| `/start` | Hiển thị menu chính | `/start` |
| `/help` | Hướng dẫn chi tiết | `/help` |
| `/sys` | Kiểm tra RAM/CPU/Queue | `/sys` |
| `/clear` | Xóa lịch sử chat | `/clear` |
| `/add <id> [name]` | Thêm user whitelist | `/add 987654321 john` |
| `/remove <id>` | Xóa user whitelist | `/remove 987654321` |
| `/whitelist` | Xem danh sách user | `/whitelist` |
| `[text]` | Chat với AI | `giá vàng hôm nay` |
| `[file.txt]` | Phân tích file | Gửi file .txt |

### Cho Whitelisted Users

- `/start` `/help` `/sys` `/clear` - Lệnh thông thường
- Text chat, file upload - Đầy đủ tính năng

## 📊 Cấu Trúc Project

```
agent_mini/
├── tele_agent.py              # Bot chính (873 dòng)
│   ├─ Config class            # Load .env
│   ├─ ChatDatabase            # SQLite + whitelist table
│   ├─ RequestQueue            # Lock-based queue
│   ├─ AIAgent                 # Ollama client
│   ├─ Handlers                # /start, /add, /remove, /whitelist, etc
│   └─ SystemMonitor           # RAM/CPU check
├── manage.sh                  # Quản lý bot (start/stop/status/logs)
├── setup_system.sh            # Cài đặt tự động (360 dòng)
├── start.sh, stop.sh          # Shortcuts
├── status.sh, logs.sh         # Kiểm tra trạng thái
├── .env.example               # Config template
├── .env                       # Config thực (git ignored)
├── requirements.txt           # Python packages
├── data/
│   └─ chat_history.db        # SQLite database
├── docker-compose.yml         # Open WebUI (optional)
└── README.md (this file)

```

## ⚙️ Cấu Hình (.env)

```bash
# Telegram
TELEGRAM_API_TOKEN=your_bot_token_here
ADMIN_CHAT_ID=your_chat_id_here

# Ollama
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=qwen2.5:7b

# System
MAX_WORKERS=1                  # Chỉ 1 request tại một lúc
QUEUE_CHECK_INTERVAL=2         # Check queue mỗi 2s
HISTORY_LIMIT=20               # Lưu 20 tin nhắn
```

## 🔧 Quản Lý Bot

```bash
# Khởi động
./manage.sh start

# Dừng
./manage.sh stop

# Kiểm tra trạng thái
./manage.sh status

# Xem logs real-time
./manage.sh logs-live

# Backup database
./manage.sh db-backup

# Dọn dẹp dữ liệu cũ (>30 ngày)
./manage.sh db-cleanup

# Reset bot (xóa cache, khởi động lại)
./manage.sh reset
```

## 📈 Performance & Optimization

### Tuned Parameters
```
- Threads: 8 cores (tận dụng CPU multicore)
- Context Window: 4096 tokens
- Temperature: 0.3 (tăng tính chính xác)
- Repeat Penalty: 1.2 (tránh lặp)
- Top-K: 30, Top-P: 0.8 (sampling)
```

### Thời Gian Phản Hồi
- **Lần đầu**: ~10-15 giây (load model)
- **Lần sau**: ~5-8 giây (inference on CPU)
- **Whitelist check**: <100ms

### Memory Usage
- **Ollama**: ~4.7GB (model)
- **Python bot**: ~60MB
- **SQLite**: ~5MB
- **Swap**: 4GB (được cấu hình tự động)

## 🐛 Troubleshooting

### Bot không phản hồi
```bash
# Check nếu bot còn chạy
pgrep -a tele_agent.py

# Xem logs
tail -50 bot_agent.log

# Restart
./manage.sh stop && sleep 2 && ./manage.sh start
```

### Ollama không kết nối
```bash
# Check Ollama running
pgrep ollama

# Kiểm tra port 11434
curl http://localhost:11434/api/tags

# Khởi động lại
ollama serve &
```

### .env não tìm thấy
```bash
# Copy từ template
cp .env.example .env

# Thêm token Telegram
TELEGRAM_API_TOKEN=your_token_here
ADMIN_CHAT_ID=your_id_here
```

## 📚 File Documentations

- [INSTALLATION_GUIDE.md](./INSTALLATION_GUIDE.md) - Hướng dẫn chi tiết
- [AI_AGENT_INSTRUCTIONS.md](./.github/instructions/AI_AGENT_INSTRUCTIONS.md) - Spec kỹ thuật
- [setup_system.sh](./setup_system.sh) - Script setup
- [tele_agent.py](./tele_agent.py) - Source code main

## 🛡️ Bảo Mật

- ✅ Chỉ Admin chính + whitelist users có quyền
- ✅ Mỗi user isolate (riêng SQLite history)
- ✅ API token không in logs
- ✅ File tải lên được xóa sau khi xử lý

## 📝 License

Personal use - Local AI Bot for Vietnamese users

## 👤 Author

Duy Hieu - Vietnamese AI Agent Project

---

**Last Updated:** 2026-02-27 | **Version:** 1.2-whitelist

## 📋 Tính Năng

- ✅ **Ollama AI Integration**: qwen2.5:7b model (tối ưu tiếng Việt)
- ✅ **Telegram Bot**: Tương tác qua Telegram Messenger
- ✅ **Web Interface**: Open WebUI giống Zerobot/ChatGPT (port 3000)
- ✅ **Conversation Memory**: Lưu lịch sử chat vào SQLite
- ✅ **Queue System**: Xứ lý 1 request AI tại một lúc (8GB RAM optimized)
- ✅ **File Processing**: Phân tích file .txt tự động
- ✅ **System Monitoring**: Kiểm tra RAM/CPU real-time
- ✅ **Memory Optimization**: Garbage collection, swap file, caching
- ✅ **Access Control**: Chỉ cho phép 1 admin sử dụng

## 🛠️ Yêu Cầu Hệ Thống

```
Hardware:
  - CPU: 4 Core (khuyến nghị)
  - RAM: 8GB (cần 6GB cho Ollama + 2GB cho hệ thống)
  - Disk: 20GB (cho model + data)
  - Network: Kết nối internet để cài đặt

OS:
  - Ubuntu 20.04 LTS hoặc cao hơn
  - Linux based (Debian, CentOS, etc)
```

## 🚀 Quick Start

### 1️⃣ Clone & Cấu Hình

```bash
cd /home/hieudd/code/agent_mini

# Copy file cấu hình
cp .env.example .env

# Chỉnh sửa .env với thông tin của bạn
nano .env
```

### 2️⃣ Chạy Setup Script

```bash
# Cấp quyền thực thi
chmod +x setup_system.sh

# Chạy script (cần sudo)
sudo ./setup_system.sh

# This sẽ:
# ✓ Tạo 4GB swap file (RAM optimization)
# ✓ Cài Ollama + Pull qwen2.5:7b model (~5GB, mất 10-15 phút)
# ✓ Cài Docker + Open WebUI image
# ✓ Tạo Python venv + install dependencies
# ✓ Kiểm tra toàn bộ cài đặt
```

### 3️⃣ Khởi Động Ollama

```bash
# Cách 1: Sử dụng systemd (recommended)
sudo systemctl start ollama
sudo systemctl enable ollama  # Tự động start khi reboot

# Cách 2: Chạy thủ công
ollama serve

# Kiểm tra
ollama list
```

### 4️⃣ Khởi Động Web UI (Optional)

```bash
# Nếu đã cài Docker
docker run -d -p 3000:8080 --name open-webui \
  -e OLLAMA_BASE_URL=http://localhost:11434 \
  ghcr.io/open-webui/open-webui:latest

# Truy cập: http://localhost:3000
```

### 5️⃣ Khởi Động Telegram Bot

```bash
# Activate virtual environment
source venv/bin/activate

# Chạy bot
python3 tele_agent.py

# Output:
# INFO - Starting AI Agent Bot...
# INFO - Admin Chat ID: 123456789
# INFO - Model: qwen2.5:7b
```

## 📱 Sử Dụng Telegram Bot

### Lệnh Hệ Thống

| Lệnh | Mô tả |
|------|-------|
| `/start` | Khởi động bot, xem thông tin |
| `/help` | Hướng dẫn chi tiết |
| `/sys` | Kiểm tra RAM, CPU, Queue status |
| `/clear` | Xóa lịch sử chat |

### Tương Tác

1. **Chat bình thường**: Gửi text, bot sẽ trả lời
2. **Gửi file**: Upload file .txt, bot sẽ phân tích
3. **Queue notification**: Nếu AI đang xử lý, sẽ thông báo vị trí chờ

**Ví dụ:**
```
Bạn: Hôm nay thời tiết thế nào?
Bot: Đang đợi... (Vị trí trong hàng: #1)
     (sau 30-60 giây)
    Xin lỗi, tôi không có thông tin thời tiết real-time...

Bạn: /sys
Bot: 📊 SYSTEM STATUS REPORT
     Memory: Total: 8.0GB
             Used: 5.2GB (65%)
             Available: 2.8GB
     CPU: Cores: 4
          Usage: 35%
     AI Queue: Processing: Yes
                Queue: 0
```

## 📁 Cấu Trúc File

```
agent_mini/
├── setup_system.sh          # Script cài đặt tự động
├── tele_agent.py            # Telegram Bot + AI Engine
├── .env.example             # Template cấu hình
├── .env                     # Cấu hình thực tế (create từ .env.example)
├── bot_agent.log            # Log file (tự động tạo)
└── data/
    ├── chat_history.db      # SQLite database
    └── temp_files/          # Thư mục tạm file upload
```

## 🔑 Lấy Telegram Bot Token

1. Mở Telegram, tìm `@BotFather`
2. Gửi `/newbot`
3. Đặt tên bot (ví dụ: MyAIBot)
4. Lấy token (ví dụ: `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)
5. Paste vào `.env` file

## 👤 Lấy Chat ID

1. Tìm `@userinfobot` trên Telegram
2. Gửi `/start` 
3. Lấy ID và paste vào `.env`

**Hoặc**: Gửi `/help` cho bot, sẽ hiển thị chat ID

## ⚙️ Optimization cho 8GB RAM

### Swap File
```bash
# Kiểm tra swap
free -h
swapon --show

# Script tự động tạo 4GB swap file
```

### Ollama Optimization
- Model: qwen2.5:7b (~7GB)
- Threads: 4 (tối ưu 4-core CPU)
- Context window: 2048 tokens
- Memory cleanup: Auto gc.collect() every 5 responses

### Python Optimization
- Single worker queue (chỉ 1 AI request tại một lúc)
- History limit: 20 messages
- Message length limit: 4000 chars
- Async/await for non-blocking I/O

## 📊 Monitoring

### Real-time Monitor
```bash
# Terminal 1: Watch system resources
watch -n 1 'free -h && echo && ps aux | grep ollama'

# Terminal 2: Watch bot logs
tail -f bot_agent.log

# Terminal 3: Check Ollama
watch -n 1 'ollama list && echo && ollama ps'
```

### Database Queries
```bash
# Check conversation history
sqlite3 data/chat_history.db "SELECT * FROM conversations LIMIT 10;"

# Check user stats
sqlite3 data/chat_history.db "SELECT * FROM users;"

# Delete old messages (older than 30 days)
sqlite3 data/chat_history.db "
DELETE FROM conversations 
WHERE datetime(timestamp) < datetime('now', '-30 days');
"
```

## 🐛 Troubleshooting

### "Permission denied" on setup_system.sh
```bash
chmod +x setup_system.sh
sudo ./setup_system.sh
```

### Ollama "Address already in use"
```bash
# Kill existing process
pkill -f ollama

# Or check what's using port 11434
lsof -i :11434
```

### ImportError: cannot import name 'ChatAction'
```bash
# Ensure correct python-telegram-bot version
source venv/bin/activate
pip install --upgrade python-telegram-bot==20.7
```

### Bot không respond
```bash
# 1. Check .env file
cat .env | grep TELEGRAM_API_TOKEN

# 2. Test Telegram connection
python3 -c "from telegram import Bot; print(Bot('YOUR_TOKEN').getMe())"

# 3. Check logs
tail -f bot_agent.log
```

### Out of Memory (OOM)
```bash
# Check memory usage
ps aux --sort=-%mem | head -10

# Check swap
free -h

# Increase swap if needed
sudo fallocate -l 4G /swapfile2
sudo mkswap /swapfile2
sudo swapon /swapfile2
```

### Slow Response
```bash
# 1. Check CPU usage
top -b -n 1 | head -10

# 2. Check if queue is building up
# Use /sys command on Telegram

# 3. Reduce context window in code
# Edit tele_agent.py line: 'num_ctx': 1024  (from 2048)
```

## 🔧 Advanced Configuration

### Thay đổi Model
```bash
# Edit .env
OLLAMA_MODEL=qwen2.5:14b  # Chậm hơn, chính xác hơn
# hoặc
OLLAMA_MODEL=mistral  # Nhanh hơn, nhưng kém tiếng Việt

# Pull model
ollama pull qwen2.5:14b

# Restart bot
python3 tele_agent.py
```

### Điều chỉnh Queue
```python
# tele_agent.py - line 83
QUEUE_CHECK_INTERVAL = 1  # Kiểm tra thường xuyên hơn
MAX_WORKERS = 1  # Giữ = 1 để tối ưu

# Hoặc tăng để xử lý nhiều request
MAX_WORKERS = 2  # Nhưng cần 16GB RAM
```

### Custom System Prompt
```python
# tele_agent.py - AIAgent.generate_response() method
system_prompt = """Bạn là một chuyên gia về lập trình Python...
..."""
```

## 📚 Tài Liệu Tham Khảo

- [Ollama Documentation](https://ollama.ai)
- [python-telegram-bot](https://python-telegram-bot.readthedocs.io)
- [Open WebUI](https://github.com/open-webui/open-webui)
- [qwen2.5 Model Info](https://huggingface.co/Qwen/Qwen2.5-7B)

## 📝 License

MIT License - Tự do sử dụng cho mục đích cá nhân

## 🤝 Support

Gặp vấn đề? Kiểm tra:
1. Log file: `bot_agent.log`
2. System resources: `/sys` command
3. Ollama status: `ollama ps`
4. Python version: `python3 --version` (cần 3.10+)

---

**Enjoy your local AI Agent! 🚀**
