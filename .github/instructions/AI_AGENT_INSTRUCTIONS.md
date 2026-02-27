---
description: Hướng dẫn kỹ thuật chi tiết cho AI Copilot - AI Agent Telegram Bot Project (v1.2)
applyTo: '**/*.{py,sh,md,yml,env,json}'
---

# 🤖 AI AGENT TELEGRAM BOT - TECHNICAL SPECIFICATIONS (v1.2)

**Status:** ✅ Production Ready | **Updated:** 2026-02-27 | **Language:** Vietnamese

## 📋 PROJECT OVERVIEW

### Mục Tiêu
Xây dựng hệ thống **AI Agent local hoàn toàn** trên Linux 8-15GB RAM, cho phép:
- Tương tác qua Telegram Messenger
- Sử dụng Ollama qwen2.5:7b (mô hình LLM tối ưu tiếng Việt)
- Quản lý nhiều user thông qua whitelist
- Lưu trữ conversation history (SQLite)
- Xử lý file text tự động
- Monitor system resources real-time

### Key Features (v1.2)
- **Whitelist System**: `/add`, `/remove`, `/whitelist` - quản lý user
- **8-Thread Optimization**: Tận dụng multi-core CPU
- **Temperature 0.3**: Tăng tính chính xác, giảm hallucination
- **Vietnamese Enforcement**: System prompt + example enforcing Tiếng Việt
- **Lock-based Queue**: Serialize AI requests (no race conditions)
- **SQLite Whitelist Table**: DDL included, auto-created

## 🏗️ SYSTEM ARCHITECTURE

### Components Diagram
```
┌──────────────────────────────────────────┐
│       Telegram Users (Multiple)           │
│  ├─ Admin (ADMIN_CHAT_ID)                │
│  └─ Whitelisted (in DB whitelist table)  │
└─────────────────────┬────────────────────┘
                      │ (Telegram API)
                      ▼
┌──────────────────────────────────────────┐
│    python-telegram-bot (20.7)             │
│    - Application.build()                  │
│    - Polling updater                      │
│    - Async handlers                       │
└─────────────────────┬────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────┐
│   tele_agent.py Main Module               │
│                                            │
│  ├─ Config (lines 54-84)                 │
│  │   ├─ OLLAMA_THREADS=8                 │
│  │   ├─ OLLAMA_MODEL=qwen2.5:7b          │
│  │   └─ MAX_MESSAGE_LENGTH=4000          │
│  │                                        │
│  ├─ ChatDatabase (lines 90-180)          │
│  │   ├─ conversations table               │
│  │   ├─ users table                       │
│  │   ├─ **whitelist table (NEW)**        │
│  │   └─ Methods: get_history, add_to_*   │
│  │                                        │
│  ├─ RequestQueue (lines 194-246)         │
│  │   ├─ async Lock (serialization)       │
│  │   ├─ enqueue(chat_id) → position     │
│  │   └─ mark_done(chat_id)               │
│  │                                        │
│  ├─ AIAgent (lines 343-468)              │
│  │   ├─ generate_response()              │
│  │   ├─ _call_ollama() [CPU inference]   │
│  │   └─ process_file()                   │
│  │                                        │
│  ├─ Handlers (lines 520-705)             │
│  │   ├─ start_handler()                  │
│  │   ├─ **add_user_handler()** (NEW)     │
│  │   ├─ **remove_user_handler()** (NEW)  │
│  │   ├─ **whitelist_handler()** (NEW)    │
│  │   ├─ message_handler()                │
│  │   └─ document_handler()               │
│  │                                        │
│  └─ setup_application()                  │
│      ├─ Add all handlers                 │
│      └─ Attach to app                    │
│                                            │
└─────────────────────┬────────────────────┘
                      │ ollama.chat() API
                      ▼
┌──────────────────────────────────────────┐
│    Ollama (localhost:11434)               │
│                                            │
│    Model: qwen2.5:7b (4.7GB)             │
│    ├─ Threads: 8 cores                   │
│    ├─ Context: 4096 tokens               │
│    ├─ Temperature: 0.3 (low)             │
│    ├─ Top-K: 30, Top-P: 0.8             │
│    └─ Repeat Penalty: 1.2                │
│                                            │
│    Inference Time: ~5-10s on CPU         │
└──────────────────────────────────────────┘

Data Flow:
User → TG API → message_handler → enqueue → lock → AIAgent → ollama.chat()
                                                    → SQLite save → TG reply
```

## 📝 IMPLEMENTATION DETAILS

### 1. tele_agent.py (873 lines)

#### Config Class (lines 54-84)
```python
class Config:
    # Telegram
    TELEGRAM_API_TOKEN = os.getenv('TELEGRAM_API_TOKEN', '')
    ADMIN_CHAT_ID = int(os.getenv('ADMIN_CHAT_ID', 0))
    
    # Ollama
    OLLAMA_URL = 'http://localhost:11434'
    OLLAMA_MODEL = 'qwen2.5:7b'
    OLLAMA_THREADS = 8  # ← OPTIMIZED for 12-core CPU
    
    # Queue & Memory
    MAX_WORKERS = 1
    HISTORY_LIMIT = 20
    
    def __init__(self):
        if not self.TELEGRAM_API_TOKEN:
            raise ValueError("TELEGRAM_API_TOKEN not set in .env file")
```

**Key Changes in v1.2:**
- OLLAMA_THREADS: 4 → 8 (tận dụng CPU đa-lõi)
- Temperature: 0.7 → 0.3 (tăng chính xác)
- Repeat_penalty: 1.1 → 1.2 (tránh lặp)

#### ChatDatabase Class (lines 90-180)

**Original Tables:**
```sql
CREATE TABLE conversations (
    id INTEGER PRIMARY KEY,
    chat_id INTEGER NOT NULL,
    user TEXT NOT NULL,
    role TEXT NOT NULL,           -- 'user' or 'assistant'
    content TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    tokens INTEGER DEFAULT 0
);

CREATE TABLE users (
    chat_id INTEGER PRIMARY KEY,
    username TEXT UNIQUE,
    first_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
    message_count INTEGER DEFAULT 0
);
```

**NEW in v1.2 - Whitelist Table:**
```sql
CREATE TABLE whitelist (
    chat_id INTEGER PRIMARY KEY,
    username TEXT,
    added_by INTEGER,              -- Admin who added
    added_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**New Methods:**
```python
def add_to_whitelist(self, chat_id: int, username: str, added_by: int) -> bool:
    """Insert or replace into whitelist table"""
    
def remove_from_whitelist(self, chat_id: int) -> bool:
    """Delete from whitelist"""
    
def is_whitelisted(self, chat_id: int) -> bool:
    """Check if user is whitelisted"""
    
def get_whitelist(self) -> List[tuple]:
    """Return all whitelisted (chat_id, username)"""
```

#### RequestQueue Class (lines 194-246)

**Serialization via asyncio.Lock:**
```python
class RequestQueue:
    def __init__(self, max_workers: int = 1):
        self.lock = asyncio.Lock()        # ← NEW
        self.waiting_users: Dict[int, int] = {}
    
    async def enqueue(self, chat_id, username, message) -> int:
        """Return position: 0 = immediate, >0 = queued"""
        if self.lock.locked():
            position = len(self.waiting_users) + 1
        else:
            position = 0
        self.waiting_users[chat_id] = position
        return position
```

**Usage in message_handler (lines 698-726):**
```python
# In message_handler()
async with queue_manager.lock:
    try:
        response = await ai_agent.generate_response(...)
    finally:
        queue_manager.mark_done(chat_id)
```

Result: No race conditions, strict serialization of AI calls.

#### AIAgent Class (lines 343-468)

**generate_response() method:**
```python
async def generate_response(self, chat_id, username, user_message) -> str:
    # 1. Get history (LIMIT 20)
    history = db.get_history(chat_id, limit=20)
    
    # 2. Build messages with ENFORCED system prompt
    system_prompt = """You are a helpful AI assistant. 
    You MUST respond ONLY in Vietnamese language.
    If you don't have real-time information, clearly state you don't...
    """
    
    # 3. Add example conversation (Vietnamese)
    # This teaches model to respond in Vietnamese
    
    # 4. Call Ollama
    response = await asyncio.to_thread(
        self._call_ollama, context_messages
    )
    
    # 5. Save to DB
    db.add_message(chat_id, username, 'user', user_message)
    db.add_message(chat_id, username, 'assistant', response)
    
    return response
```

**_call_ollama() method:**
```python
def _call_ollama(self, messages: List[Dict]) -> str:
    """Blocking call to Ollama API"""
    response = ollama.chat(
        model=self.model,
        messages=messages,
        stream=False,
        options={
            'num_thread': 8,
            'num_ctx': 4096,
            'temperature': 0.3,    # Low for consistency
            'repeat_penalty': 1.2,
            'top_p': 0.8,
            'top_k': 30,
        }
    )
    return response['message']['content']
```

#### Authorization Rules (lines 517-529)

**Original:**
```python
def require_admin(func):
    @wraps(func)
    async def wrapper(update, context):
        if update.effective_chat.id != config.ADMIN_CHAT_ID:
            await update.message.reply_text("❌ Truy cập bị từ chối")
            return
```

**NEW in v1.2:**
```python
def require_admin(func):
    @wraps(func)
    async def wrapper(update, context):
        chat_id = update.effective_chat.id
        # Check if admin OR whitelisted
        if chat_id == config.ADMIN_CHAT_ID or db.is_whitelisted(chat_id):
            return await func(update, context)
        await update.message.reply_text("❌ Bạn không có quyền...")
```

Result: All `@require_admin` decorated handlers now accept whitelisted users.

#### New Handlers (lines 652-705)

**1. add_user_handler() - /add <chat_id> [username]**
```python
async def add_user_handler(update, context):
    # Only ADMIN_CHAT_ID can call this
    if update.effective_chat.id != config.ADMIN_CHAT_ID: return
    
    # Parse args
    chat_id = int(context.args[0])
    username = context.args[1] if len(context.args) > 1 else "unknown"
    
    # Add to DB
    if db.add_to_whitelist(chat_id, username, update.effective_chat.id):
        await update.message.reply_text(f"✅ Đã thêm {username}")
```

**2. remove_user_handler() - /remove <chat_id>**
```python
async def remove_user_handler(update, context):
    # Only ADMIN
    if update.effective_chat.id != config.ADMIN_CHAT_ID: return
    
    # Parse and remove
    chat_id = int(context.args[0])
    if db.remove_from_whitelist(chat_id):
        await update.message.reply_text(f"✅ Đã xóa user {chat_id}")
```

**3. whitelist_handler() - /whitelist**
```python
async def whitelist_handler(update, context):
    # Only ADMIN
    if update.effective_chat.id != config.ADMIN_CHAT_ID: return
    
    # Get and display all whitelisted users
    whitelist = db.get_whitelist()
    message = "📋 **DANH SÁCH NGƯỜI DÙNG:**\n"
    for chat_id, username in whitelist:
        message += f"• {username} (ID: {chat_id})\n"
    await update.message.reply_text(message, parse_mode='Markdown')
```

#### Handler Registration (lines 810-825)

```python
async def setup_application():
    app = Application.builder().token(config.TELEGRAM_API_TOKEN).build()
    
    # Handlers
    app.add_handler(CommandHandler('start', start_handler))
    app.add_handler(CommandHandler('help', help_handler))
    app.add_handler(CommandHandler('sys', sys_handler))
    app.add_handler(CommandHandler('clear', clear_handler))
    
    # NEW Admin commands (Admin only)
    app.add_handler(CommandHandler('add', add_user_handler))
    app.add_handler(CommandHandler('remove', remove_user_handler))
    app.add_handler(CommandHandler('whitelist', whitelist_handler))
    
    # Message handlers
    app.add_handler(MessageHandler(filters.Document.TEXT, document_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, message_handler))
    
    return app
```

### 2. manage.sh (795 lines)

Key functions:
```bash
check_bot()          # Check via PID file
start_ollama()       # Run ollama serve
start_bot()          # nohup python3 tele_agent.py
stop_bot()           # Kill bot process
get_logs()           # Show bot logs
db_backup()          # Backup SQLite
db_cleanup()         # Delete old messages >30 days
```

### 3. setup_system.sh (360 lines)

Automated steps:
1. Create swap file (4GB)
2. Install Ollama
3. Pull qwen2.5:7b model
4. Create Python venv
5. Install pip packages
6. Setup systemd service (optional)

## 🔍 KEY IMPROVEMENTS (v1.2 vs v1.0)

| Feature | v1.0 | v1.1 | v1.2 |
|---------|------|------|------|
| Single Admin | ✅ | ✅ | ✅ |
| Whitelist Users | ❌ | ❌ | ✅ NEW |
| /add /remove /whitelist | ❌ | ❌ | ✅ NEW |
| Threads | 4 | 4 | 8 ✅ |
| Temperature | 0.7 | 0.7 | 0.3 ✅ |
| Vietnamese Enforcement | Basic | Good | Strong (example) ✅ |
| Lock-based Queue | ❌ | ✅ | ✅ |
| Ollama 409 Conflict | ❌ | ✅ | ✅ |

## 🔐 Security Model

### Access Control
```
┌─ ADMIN_CHAT_ID (from .env)
│  └─ Can do ALL commands (/start, /add, /remove, /sys, /clear)
│
└─ Whitelisted Users (in DB)
   └─ Can do regular commands (/start, /sys, /clear, chat, files)
      BUT NOT /add, /remove, /whitelist
```

### Database Isolation
- Each user's conversation is separate (chat_id as key)
- Whitelist stored in dedicated table
- No cross-user data leakage

### API Token Security
- Never printed to logs
- Loaded from .env (git ignored)
- Used only for Telegram API calls

## 📊 Performance Metrics

### Tested on Fedora 41, 12-core CPU, 15GB RAM

```
Ollama Model Load:
  ├─ First startup: 5-8 seconds
  ├─ Warm load: 1-2 seconds
  └─ GPU: None (CPU only)

Response Time:
  ├─ Simple query ("Xin chào"): ~4 seconds
  ├─ Complex query (long text): ~8-10 seconds
  ├─ File analysis (.txt): ~10-15 seconds
  └─ Whitelist operations: <100ms

Memory Usage:
  ├─ Ollama (model): ~4.7GB
  ├─ Python bot: ~60MB
  ├─ SQLite cache: <5MB
  └─ Total: ~11GB base (+ swap)

Concurrency:
  ├─ Queue handling: Serialized (1 at a time)
  ├─ Lock acquire time: <1ms
  └─ Maximum queue depth: Unlimited (waits in line)
```

## 🛠️ Development Guidelines

### Adding New Commands
```python
async def my_command_handler(update, context):
    chat_id = update.effective_chat.id
    
    # Add decorator if need admin/whitelist
    @require_admin
    
    # Respond
    await update.message.reply_text("Response")
    
    # Register in setup_application()
    app.add_handler(CommandHandler('mycommand', my_command_handler))
```

### Modifying AI Behavior
Locate: `AIAgent.generate_response()` line ~360
```python
if not system_prompt:
    system_prompt = """Your new system prompt..."""
```

### Adding Database Fields
1. Edit `_init_database()` in ChatDatabase
2. Create new table or ALTER existing
3. Add getter/setter methods
4. Test with fresh .db file (or migrate existing)

## 📚 External Dependencies

```
python-telegram-bot==20.7      # Telegram interface
ollama==0.1.48                  # Ollama Python client
aiohttp==3.9.X                  # Async HTTP
psutil==5.9.X                   # System monitors  
python-dotenv==1.0.X            # .env file loading
asyncio-contextmanager==1.0.0   # Compatibility
```

## 🚀 Deployment Checklist

- [ ] Ollama installed and qwen2.5:7b pulled
- [ ] .env file configured with TELEGRAM_API_TOKEN
- [ ] ADMIN_CHAT_ID set correctly in .env
- [ ] Python venv created and packages installed
- [ ] Bot tested with /start command
- [ ] Message response verified
- [ ] Whitelist feature tested (/add, /remove, /whitelist)
- [ ] manage.sh scripts have execute permissions
- [ ] Database backed up
- [ ] Logs monitored for errors

---

**Version:** 1.2-whitelist | **Last Updated:** 2026-02-27 | **Maintained By:** Duy Hieu

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
