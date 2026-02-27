---
description: Hướng dẫn chi tiết cho AI Copilot khi làm việc với AI Agent Telegram Bot Project
applyTo: '**/*.{py,sh,md,yml,env}'
---

# 🤖 AI AGENT TELEGRAM BOT - TECHNICAL INSTRUCTIONS

## 📋 MỤC TIÊU PROJECT (Project Goal)

Xây dựng hệ thống AI Agent cá nhân chạy hoàn toàn local trên Linux (Fedora/Ubuntu), tích hợp:
- **Telegram Bot**: Interface chính để tương tác
- **Ollama AI Engine**: Model qwen2.5:7b (4.7GB) tối ưu tiếng Việt  
- **SQLite Database**: Lưu trữ lịch sử hội thoại
- **Queue System**: Xử lý tuần tự requests
- **Management Scripts**: Tự động hóa quản lý

## 🏗️ KIẾN TRÚC HỆ THỐNG (System Architecture)

### Thành Phần Chính

```
┌─────────────────────────────────────────┐
│         Telegram User                    │
└──────────────┬──────────────────────────┘
               │ Messages
               ▼
┌─────────────────────────────────────────┐
│    Telegram Bot API                      │
│    (python-telegram-bot 20.7)           │
└──────────────┬──────────────────────────┘
               │ Async handlers
               ▼
┌─────────────────────────────────────────┐
│    tele_agent.py (Main Bot)              │
│    ├─ Config (load .env)                │
│    ├─ RequestQueue (lock-based)         │
│    ├─ AIAgent (Ollama client)          │
│    ├─ ChatDatabase (SQLite)             │
│    └─ Handlers (message/command)        │
└──────────────┬──────────────────────────┘
               │ ollama.chat()
               ▼
┌─────────────────────────────────────────┐
│    Ollama AI Engine                      │
│    ├─ Model: qwen2.5:7b (4.7GB)        │
│    ├─ Threads: 8                        │
│    ├─ Context: 4096 tokens              │
│    └─ Port: 11434                       │
└─────────────────────────────────────────┘
```

### Data Flow

1. **User Message** → Telegram API
2. **Telegram API** → `message_handler()` in tele_agent.py
3. **Handler** → Queue check via `RequestQueue.enqueue()`
4. **Queue** → Lock-based processing (1 worker)
5. **AIAgent** → `ollama.chat()` API call
6. **Ollama** → Model inference (5-15s on CPU)
7. **Response** → Save to SQLite → Send to Telegram

## 📝 CHI TIẾT IMPLEMENTATION

### 1. File `tele_agent.py` (694 dòng)

**Core Classes:**

```python
class Config:
    """Load environment variables from .env"""
    - TELEGRAM_API_TOKEN
    - ADMIN_CHAT_ID
    - OLLAMA_URL, OLLAMA_MODEL
    - MAX_WORKERS, QUEUE_CHECK_INTERVAL
    - Threads: 8 (optimized for 12-core CPU)
    - Context: 4096 tokens

class ChatDatabase:
    """SQLite conversation storage"""
    - Tables: conversations, users
    - Methods: add_message(), get_history(), update_user_stats()
    - Auto-cleanup: >30 days old messages

class RequestQueue:
    """Lock-based queue manager"""
    - asyncio.Lock() for serialization
    - enqueue(): Return position (0 = process now)
    - mark_done(): Remove from waiting list
    - get_queue_status(): Stats for /sys command

class SystemMonitor:
    """Resource monitoring"""
    - get_memory_info(): RAM/Swap usage
    - get_cpu_info(): Cores/Load/Percent
    - get_full_status(): Formatted report

class AIAgent:
    """Ollama integration"""
    - generate_response(): Main AI call with history
    - _call_ollama(): Direct ollama.chat() wrapper
    - process_file(): Analyze .txt files
    - GC every 5 responses
```

**Key Handlers:**

```python
@require_admin  # Decorator: only ADMIN_CHAT_ID allowed
async def message_handler(update, context):
    """
    1. Validate message length (<4000 chars)
    2. Enqueue request → get position
    3. Send "waiting" if position > 0
    4. Lock-based processing (serialize AI calls)
    5. Normalize response (prevent coroutine errors)
    6. Split if >4096 chars
    7. Reply to user
    """

async def sys_handler(update, context):
    """Return formatted system status (RAM/CPU/Queue)"""

async def clear_handler(update, context):
    """Delete chat history for user"""

async def document_handler(update, context):
    """Download .txt file → AI analysis → reply"""
```

**Critical Fixes Applied:**

1. **load_dotenv() before Config** (line 22-23)
   - Issue: TELEGRAM_API_TOKEN not found
   - Fix: Import and call load_dotenv() at module level

2. **Lock-based Queue** (line 200, 585-590)
   - Issue: Queue showing "waiting" but never processing
   - Fix: `async with queue_manager.lock` + no early return

3. **Response Normalization** (line 592-596, 635-639)
   - Issue: 'coroutine' object has no attribute 'split'
   - Fix: Check if coroutine → await, ensure str type

4. **send_action() Instead of chat.action()** (line 587, 630)
   - Issue: 'Chat' object has no attribute 'action'
   - Fix: Changed context manager to simple send_action()

5. **System Prompt Vietnamese-only** (line 359-362)
   - Issue: Mixed Vietnamese-Chinese responses
   - Fix: Clear prompt "CHỈ trả lời bằng TIẾNG VIỆT"

### 2. File `setup_system.sh` (360 dòng)

**Main Functions:**

```bash
check_requirements()
    - Verify: sudo, curl, git, python3
    - Exit if missing critical tools

create_swap_file()
    - Check existing swap
    - Create 4GB /swapfile if <2GB swap
    - Commands: fallocate, mkswap, swapon
    - Add to /etc/fstab for persistence

install_ollama()
    - Download: curl https://ollama.com/install.sh
    - Execute install script
    - Verify: ollama --version

pull_model()
    - Pull qwen2.5:7b model (~4.7GB)
    - Timeout: 20 minutes
    - Retry on failure

setup_docker()
    - Install Docker (apt/dnf based on distro)
    - Enable systemd service
    - Add user to docker group
    - Pull open-webui image (optional)

setup_python_env()
    - Create venv in ./venv
    - Upgrade pip
    - Install from requirements.txt:
      * python-telegram-bot==20.7
      * ollama==0.1.48
      * aiohttp, psutil, python-dotenv

verify_installation()
    - Check all components
    - Display summary report
    - Exit codes: 0=success, 1=failure
```

### 3. File `manage.sh` (795 dòng)

**Core Functions:**

```bash
check_ollama()
check_bot()
    - Use pgrep to find processes
    - Manage .bot.pid file
    - Return 0=running, 1=not running

start_ollama()
    - Check port 11434 availability
    - Run: ollama serve > /tmp/ollama.log &
    - Wait for readiness (10 retries)

start_bot()
    - Verify: venv exists, .env configured
    - Start Ollama if not running
    - Run: nohup python3 tele_agent.py >> bot_agent.log &
    - Save PID to .bot.pid

stop_ollama()
stop_bot()
    - Kill gracefully (SIGTERM)
    - Force kill after 2s (SIGKILL)
    - Clean up PID files

status()
    - Display services (Ollama, Bot)
    - Memory/Swap usage (free -h)
    - CPU usage (top)
    - Ollama models (ollama list)
    - Bot logs (tail -10)

logs_live()
    - tail -f bot_agent.log

db_backup()
    - Timestamp-based backup
    - cp data/chat_history.db data/backup_YYYYMMDD_HHMMSS.db

db_cleanup()
    - sqlite3 DELETE old messages (>30 days)
```

**30+ Commands:**
- start, stop, restart, status
- logs, logs-live, logs-clear
- db-backup, db-cleanup, db-stats
- monitor, test-ollama, test-bot
- etc.

## 🔧 CONFIGURATION FILES

### `.env` (Environment Variables)

```env
# Required
TELEGRAM_API_TOKEN=123456:ABC-XYZ  # From @BotFather
ADMIN_CHAT_ID=123456789            # From @userinfobot

# Ollama
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=qwen2.5:7b

# System (optimized)
MAX_WORKERS=1                      # Single worker queue
QUEUE_CHECK_INTERVAL=2             # Seconds
```

### `requirements.txt`

```
python-telegram-bot==20.7          # Telegram API wrapper
ollama==0.1.48                     # Ollama Python client
aiohttp==3.9.2                     # Async HTTP
asyncio-contextmanager==1.0.0      # Context manager support
psutil==5.9.8                      # System monitoring
python-dotenv==1.0.0               # .env loading
```

### `docker-compose.yml` (Optional Web UI)

```yaml
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:latest
    ports:
      - "3000:8080"
    environment:
      - OLLAMA_BASE_URL=http://localhost:11434
    volumes:
      - open-webui:/app/backend/data
```

## ⚙️ OPTIMIZATION SETTINGS

### RAM Optimization (8GB Target)

- **Swap**: 4GB file (reduce OOM risk)
- **Model**: qwen2.5:7b (4.7GB loaded)
- **Queue**: MAX_WORKERS=1 (serialize AI calls)
- **History**: Limit 20 messages
- **GC**: Auto gc.collect() every 5 responses
- **Context**: 4096 tokens (balance quality/memory)

### CPU Optimization

- **Threads**: 8 (on 12-core CPU)
- **Load Balancing**: Single queue prevents overload
- **Async I/O**: Non-blocking Telegram/Ollama calls

### Response Time Optimization

**Before:**
- Threads: 4
- Context: 2048
- Average: 15-20s per response

**After:**
- Threads: 8 (+100% CPU usage)
- Context: 4096 (+better quality)
- Average: 8-12s per response

## 🐛 COMMON ISSUES & SOLUTIONS

### 1. Telegram 409 Conflict

**Error:**
```
telegram.error.Conflict: terminated by other getUpdates request
```

**Cause:** Multiple bot instances polling same token

**Fix:**
```bash
pkill -f tele_agent.py           # Kill all
./manage.sh start                # Start single instance
```

**Prevention:** Always use manage.sh, check for duplicates

### 2. Chat.action AttributeError

**Error:**
```
'Chat' object has no attribute 'action'
```

**Cause:** Version incompatibility or deprecated API

**Fix:**
```python
# Before (broken):
async with update.message.chat.action(CHAT_ACTION_TYPING):
    ...

# After (working):
await update.message.chat.send_action(CHAT_ACTION_TYPING)
# Process without context manager
```

### 3. Coroutine Split Error

**Error:**
```
'coroutine' object has no attribute 'split'
```

**Cause:** Response not awaited before string operations

**Fix:**
```python
# Add defensive checks:
if asyncio.iscoroutine(response):
    response = await response
if not isinstance(response, str):
    response = str(response)
```

### 4. Queue Hang (Never Processing)

**Symptom:** Bot says "waiting #1" but never processes

**Cause:** Early return in handler prevented execution

**Fix:**
```python
# Before:
if position > 0:
    await reply("waiting...")
    return  # ← WRONG: exits handler

# After:
if position > 0:
    await reply("waiting...")
# Continue to processing (lock will serialize)
```

### 5. Environment Variables Not Loaded

**Error:**
```
ValueError: TELEGRAM_API_TOKEN not set in .env file
```

**Cause:** load_dotenv() called after Config class init

**Fix:**
```python
# At module top (line 21-23):
from dotenv import load_dotenv
load_dotenv()  # ← BEFORE Config class

class Config:
    TELEGRAM_API_TOKEN = os.getenv(...)  # ← Now works
```

## 📊 MONITORING & DEBUGGING

### Log Analysis

```bash
# Real-time logs
tail -f bot_agent.log

# Search errors
grep -i error bot_agent.log | tail -20

# User activity
grep -i "Processed message" bot_agent.log | wc -l

# Ollama calls
grep -i "Generating response" bot_agent.log
```

### Database Queries

```sql
-- Recent conversations
SELECT * FROM conversations 
ORDER BY timestamp DESC 
LIMIT 20;

-- User stats
SELECT 
    user, 
    COUNT(*) as messages,
    MAX(timestamp) as last_active
FROM conversations 
GROUP BY user;

-- Conversation by chat_id
SELECT role, content, timestamp
FROM conversations 
WHERE chat_id = 123456789
ORDER BY timestamp;
```

### Resource Monitoring

```bash
# Memory usage
free -h && swapon --show

# Ollama process
ps aux | grep ollama

# Bot process  
ps aux | grep tele_agent

# CPU load
top -bn1 | head -10

# Disk usage
df -h | grep -E "/$|/home"
```

## 🚀 DEPLOYMENT BEST PRACTICES

### Production Checklist

- [ ] .env file with valid token/chat ID
- [ ] Ollama running with model loaded
- [ ] Swap file created (4GB+)
- [ ] Virtual environment activated
- [ ] All dependencies installed
- [ ] No duplicate bot processes
- [ ] Firewall allows port 11434
- [ ] Systemd service configured (optional)
- [ ] Log rotation configured
- [ ] Database backup scheduled

### Security Considerations

1. **Token Protection:**
   ```bash
   chmod 600 .env           # Owner read/write only
   echo ".env" >> .gitignore
   ```

2. **Admin-only Access:**
   ```python
   @require_admin  # All sensitive handlers
   ```

3. **Rate Limiting:** Queue system naturally limits abuse

4. **Input Validation:** Max 4000 chars per message

5. **File Upload:** Only .txt files, size limit via Telegram

### Performance Tuning

**For Faster Response (less quality):**
```python
OLLAMA_THREADS = 12              # Max CPU
'num_ctx': 2048                  # Smaller context
'temperature': 0.5               # More deterministic
```

**For Better Quality (slower):**
```python
OLLAMA_MODEL = "qwen2.5:14b"     # Larger model
'num_ctx': 8192                  # More context
'temperature': 0.9               # More creative
```

**For Lower RAM:**
```python
OLLAMA_MODEL = "qwen2.5-coder:1.5b"  # 986MB model
HISTORY_LIMIT = 10                    # Less context
```

## 📚 DEVELOPER NOTES

### Code Style

- **Python:** PEP 8, type hints encouraged
- **Bash:** ShellCheck compliant
- **Comments:** Vietnamese for user-facing, English for code
- **Logging:** INFO for normal, ERROR for issues
- **Async:** Use async/await consistently

### Testing Workflow

1. **Unit Test** (manual):
   ```bash
   python3 -c "from tele_agent import Config; print(Config().OLLAMA_MODEL)"
   ```

2. **Integration Test:**
   ```bash
   ./manage.sh start
   # Send /start to bot
   # Verify response
   ./manage.sh stop
   ```

3. **Load Test:**
   - Send 10 consecutive messages
   - Check queue handling
   - Monitor RAM usage

### Version Control

```bash
# Before commit
git status
git diff

# Commit structure
git add .
git commit -m "feat: add Vietnamese README

- Complete rewrite in Vietnamese
- Add troubleshooting section
- Update architecture diagram"

# Branch naming
feature/add-web-ui
fix/telegram-409-conflict
docs/update-readme
```

## 🎯 ROADMAP FEATURES

### Planned Enhancements

1. **Multi-user Support:**
   - User quota system
   - Per-user history
   - Admin dashboard

2. **Enhanced AI:**
   - RAG with vector DB
   - Tool/function calling
   - Voice message support

3. **Web UI:**
   - Open WebUI full integration
   - Chat history viewer
   - System metrics dashboard

4. **Deployment:**
   - Docker Compose setup
   - Kubernetes manifests
   - CI/CD pipelines

5. **Monitoring:**
   - Prometheus metrics
   - Grafana dashboards
   - Alert system

## 📖 REFERENCES

### Official Documentation

- [Ollama API](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [python-telegram-bot](https://docs.python-telegram-bot.org/en/stable/)
- [Qwen2.5 Model Card](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct)
- [SQLite Python](https://docs.python.org/3/library/sqlite3.html)

### Useful Resources

- [Async Programming Python](https://realpython.com/async-io-python/)
- [Telegram Bot API](https://core.telegram.org/bots/api)
- [Linux System Admin](https://www.linuxcommand.org/)

---

**Document Version:** 2.0  
**Last Updated:** 2026-02-27  
**Maintained by:** Vietnamese AI Agent Community
