#!/usr/bin/env python3

##############################################################################
# tele_agent.py - Telegram AI Agent Bridge (Optimized for 8GB RAM)
# Kết nối Telegram Bot với Ollama AI Engine
##############################################################################

import os
import sys
import json
import gc
import sqlite3
import asyncio
import logging
from datetime import datetime
from typing import Optional, List, Dict, Any
from pathlib import Path
from functools import wraps
import psutil

# Load environment variables from .env file
from dotenv import load_dotenv
load_dotenv()

# Third-party imports
from telegram import Update, Chat
from telegram.ext import Application, CommandHandler, MessageHandler, ContextTypes, filters
from telegram.error import TelegramError
import ollama

# ChatAction constants (compatible with all python-telegram-bot versions)
CHAT_ACTION_TYPING = 'typing'
CHAT_ACTION_UPLOAD_DOCUMENT = 'upload_document'

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('bot_agent.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

##############################################################################
# Configuration
##############################################################################

class Config:
    """Configuration management"""
    
    # Telegram
    TELEGRAM_API_TOKEN = os.getenv('TELEGRAM_API_TOKEN', '')
    ADMIN_CHAT_ID = int(os.getenv('ADMIN_CHAT_ID', 0))
    
    # Ollama
    OLLAMA_URL = os.getenv('OLLAMA_URL', 'http://localhost:11434')
    OLLAMA_MODEL = os.getenv('OLLAMA_MODEL', 'qwen2.5:7b')
    OLLAMA_THREADS = 8  # Tăng threads cho CPU 12 cores
    
    # System
    MAX_WORKERS = 1  # Chỉ xử lý 1 request AI tại một lúc
    QUEUE_CHECK_INTERVAL = 2  # Seconds
    HISTORY_LIMIT = 20  # Max messages in history
    DATABASE_PATH = './data/chat_history.db'
    TEMP_FILES_PATH = './data/temp_files'
    
    # Memory management (8GB RAM optimized)
    MAX_MESSAGE_LENGTH = 4000
    GC_INTERVAL = 5  # Run garbage collection every 5 responses
    MEMORY_THRESHOLD_MB = 1000  # Alert if free memory < 1GB
    
    def __init__(self):
        if not self.TELEGRAM_API_TOKEN:
            raise ValueError("TELEGRAM_API_TOKEN not set in .env file")
        if self.ADMIN_CHAT_ID == 0:
            raise ValueError("ADMIN_CHAT_ID not set in .env file")
        
        # Create directories
        Path(self.TEMP_FILES_PATH).mkdir(parents=True, exist_ok=True)
        Path(Path(self.DATABASE_PATH).parent).mkdir(parents=True, exist_ok=True)

config = Config()

##############################################################################
# Database Management
##############################################################################

class ChatDatabase:
    """SQLite database for conversation history"""
    
    def __init__(self, db_path: str):
        self.db_path = db_path
        self._init_database()
    
    def _init_database(self):
        """Initialize database schema"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''
                CREATE TABLE IF NOT EXISTS conversations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    chat_id INTEGER NOT NULL,
                    user TEXT NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                    tokens INTEGER DEFAULT 0
                )
            ''')
            
            conn.execute('''
                CREATE TABLE IF NOT EXISTS users (
                    chat_id INTEGER PRIMARY KEY,
                    username TEXT UNIQUE,
                    first_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
                    last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
                    message_count INTEGER DEFAULT 0
                )
            ''')
            
            conn.execute('''
                CREATE TABLE IF NOT EXISTS whitelist (
                    chat_id INTEGER PRIMARY KEY,
                    username TEXT,
                    added_by INTEGER,
                    added_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            
            conn.commit()
    
    def add_message(self, chat_id: int, username: str, role: str, content: str):
        """Add message to history"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''
                INSERT INTO conversations (chat_id, user, role, content)
                VALUES (?, ?, ?, ?)
            ''', (chat_id, username, role, content))
            conn.commit()
    
    def get_history(self, chat_id: int, limit: int = 20) -> List[Dict]:
        """Get conversation history"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute('''
                SELECT role, content FROM conversations
                WHERE chat_id = ?
                ORDER BY timestamp DESC
                LIMIT ?
            ''', (chat_id, limit))
            
            # Reverse to get chronological order
            messages = [dict(row) for row in cursor.fetchall()]
            return list(reversed(messages))
    
    def update_user_stats(self, chat_id: int, username: str):
        """Update user statistics"""
        with sqlite3.connect(self.db_path) as conn:
            # Check if user exists
            cursor = conn.execute(
                'SELECT chat_id FROM users WHERE chat_id = ?',
                (chat_id,)
            )
            
            if cursor.fetchone():
                conn.execute('''
                    UPDATE users
                    SET last_seen = CURRENT_TIMESTAMP,
                        message_count = message_count + 1
                    WHERE chat_id = ?
                ''', (chat_id,))
            else:
                conn.execute('''
                    INSERT INTO users (chat_id, username)
                    VALUES (?, ?)
                ''', (chat_id, username))
            
            conn.commit()
    
    def cleanup_old_messages(self, days: int = 30):
        """Delete messages older than specified days"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''
                DELETE FROM conversations
                WHERE datetime(timestamp) < datetime('now', '-' || ? || ' days')
            ''', (days,))
            conn.commit()
    
    def add_to_whitelist(self, chat_id: int, username: str, added_by: int) -> bool:
        """Add user to whitelist"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute('''
                    INSERT OR REPLACE INTO whitelist (chat_id, username, added_by)
                    VALUES (?, ?, ?)
                ''', (chat_id, username, added_by))
                conn.commit()
            return True
        except Exception as e:
            logger.error(f"Error adding to whitelist: {str(e)}")
            return False
    
    def remove_from_whitelist(self, chat_id: int) -> bool:
        """Remove user from whitelist"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute('DELETE FROM whitelist WHERE chat_id = ?', (chat_id,))
                conn.commit()
            return True
        except Exception as e:
            logger.error(f"Error removing from whitelist: {str(e)}")
            return False
    
    def is_whitelisted(self, chat_id: int) -> bool:
        """Check if user is in whitelist"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute('SELECT chat_id FROM whitelist WHERE chat_id = ?', (chat_id,))
                return cursor.fetchone() is not None
        except Exception as e:
            logger.error(f"Error checking whitelist: {str(e)}")
            return False
    
    def get_whitelist(self) -> List[tuple]:
        """Get all whitelisted users"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute('SELECT chat_id, username FROM whitelist ORDER BY added_at DESC')
                return cursor.fetchall()
        except Exception as e:
            logger.error(f"Error getting whitelist: {str(e)}")
            return []

# Initialize database
db = ChatDatabase(config.DATABASE_PATH)

##############################################################################
# AI Request Queue Management
##############################################################################

class RequestQueue:
    """
    Manage AI requests with queue system
    Ensures only 1 AI inference at a time (memory optimized for 8GB)
    """
    
    def __init__(self, max_workers: int = 1):
        self.max_workers = max_workers
        self.queue: asyncio.Queue = asyncio.Queue()
        self.processing = False
        self.current_user: Optional[int] = None
        self.waiting_users: Dict[int, int] = {}  # chat_id -> queue position
        self.lock = asyncio.Lock()
    
    async def enqueue(self, chat_id: int, username: str, message: str) -> int:
        """
        Add request to queue
        Returns: position in queue (0 = will process immediately)
        """
        if self.lock.locked() and chat_id in self.waiting_users:
            return self.waiting_users[chat_id]

        position = 0 if not self.lock.locked() else len(self.waiting_users) + 1
        self.waiting_users[chat_id] = position
        return position

    def mark_done(self, chat_id: int) -> None:
        """Remove user from waiting list"""
        if chat_id in self.waiting_users:
            del self.waiting_users[chat_id]
    
    async def process_next(self):
        """Process next request in queue"""
        if self.processing:
            return
        
        try:
            self.processing = True
            chat_id, username, message = await self.queue.get()
            self.current_user = chat_id
            return chat_id, username, message
        except asyncio.QueueEmpty:
            return None
        finally:
            self.processing = False
            if self.current_user in self.waiting_users:
                del self.waiting_users[self.current_user]
            self.current_user = None
    
    def get_queue_status(self) -> Dict[str, Any]:
        """Get current queue status"""
        return {
            'processing': self.processing,
            'current_user': self.current_user,
            'queue_length': self.queue.qsize(),
            'waiting_users': len(self.waiting_users)
        }

queue_manager = RequestQueue(max_workers=config.MAX_WORKERS)

##############################################################################
# System Monitoring
##############################################################################

class SystemMonitor:
    """Monitor system resources"""
    
    @staticmethod
    def get_memory_info() -> Dict[str, Any]:
        """Get memory usage information"""
        vm = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        return {
            'total_gb': vm.total / (1024**3),
            'used_gb': vm.used / (1024**3),
            'available_gb': vm.available / (1024**3),
            'percent': vm.percent,
            'swap_total_gb': swap.total / (1024**3),
            'swap_used_gb': swap.used / (1024**3),
            'swap_percent': swap.percent,
        }
    
    @staticmethod
    def get_cpu_info() -> Dict[str, Any]:
        """Get CPU usage information"""
        return {
            'cores': psutil.cpu_count(),
            'percent': psutil.cpu_percent(interval=0.5),
            'per_core': psutil.cpu_percent(interval=0.5, percpu=True),
            'load_avg': os.getloadavg(),
        }
    
    @staticmethod
    def get_full_status() -> str:
        """Get full system status report"""
        mem = SystemMonitor.get_memory_info()
        cpu = SystemMonitor.get_cpu_info()
        queue_status = queue_manager.get_queue_status()
        
        status = f"""
📊 **SYSTEM STATUS REPORT**

**Memory:**
├─ Total: {mem['total_gb']:.1f}GB
├─ Used: {mem['used_gb']:.1f}GB ({mem['percent']:.1f}%)
├─ Available: {mem['available_gb']:.1f}GB
└─ Swap: {mem['swap_used_gb']:.1f}GB / {mem['swap_total_gb']:.1f}GB

**CPU:**
├─ Cores: {cpu['cores']}
├─ Usage: {cpu['percent']:.1f}%
└─ Load Avg: {cpu['load_avg'][0]:.2f}, {cpu['load_avg'][1]:.2f}, {cpu['load_avg'][2]:.2f}

**AI Queue:**
├─ Processing: {'Yes' if queue_status['processing'] else 'No'}
├─ Waiting Queue: {queue_status['queue_length']}
└─ Waiting Users: {queue_status['waiting_users']}

**Model:** {config.OLLAMA_MODEL}
**Threads:** {config.OLLAMA_THREADS}
        """
        return status.strip()

##############################################################################
# Ollama AI Integration
##############################################################################

class AIAgent:
    """
    AI Agent with Ollama integration
    Optimized for 8GB RAM usage
    """
    
    def __init__(self):
        self.model = config.OLLAMA_MODEL
        self.url = config.OLLAMA_URL
        self.response_count = 0
    
    async def generate_response(
        self,
        chat_id: int,
        username: str,
        user_message: str,
        system_prompt: Optional[str] = None
    ) -> str:
        """
        Generate AI response with memory optimization
        
        Args:
            chat_id: Telegram chat ID
            username: Telegram username
            user_message: User's message
            system_prompt: Optional custom system prompt
        
        Returns:
            AI response text
        """
        
        try:
            # Get conversation history (limited for memory optimization)
            history = db.get_history(chat_id, limit=config.HISTORY_LIMIT)
            
            # Build context with memory efficiency
            context_messages = []
            
            # Add system prompt
            if not system_prompt:
                system_prompt = f"""You are a helpful AI assistant. You MUST respond ONLY in Vietnamese language.
User: {username}

CRITICAL RULES:
- NEVER use Chinese, English, or any language other than Vietnamese
- Always respond in Vietnamese (Tiếng Việt)
- If you don't have real-time information (gold prices, weather, news), clearly state you don't have internet access
- Keep answers concise and accurate"""
            
            context_messages.append({
                'role': 'system',
                'content': system_prompt
            })
            
            # Add Vietnamese language enforcement example
            context_messages.append({
                'role': 'user',
                'content': 'Hello, how are you?'
            })
            context_messages.append({
                'role': 'assistant',
                'content': 'Xin chào! Tôi là trợ lý AI. Tôi khỏe, cảm ơn bạn đã hỏi. Tôi có thể giúp gì cho bạn?'
            })
            
            # Add history
            for msg in history:
                context_messages.append(msg)
            
            # Add current message
            context_messages.append({
                'role': 'user',
                'content': user_message
            })
            
            # Call Ollama with optimized parameters
            logger.info(f"[{username}] Generating response... (context: {len(history)} messages)")
            
            response = await asyncio.to_thread(
                self._call_ollama,
                context_messages
            )
            
            # Store in database
            db.add_message(chat_id, username, 'user', user_message)
            db.add_message(chat_id, username, 'assistant', response)
            
            # Garbage collection every N responses (memory optimization)
            self.response_count += 1
            if self.response_count % config.GC_INTERVAL == 0:
                gc.collect()
                logger.debug("Garbage collection triggered")
            
            return response
            
        except Exception as e:
            logger.error(f"Error generating response: {str(e)}")
            return f"❌ Lỗi: {str(e)}"
    
    def _call_ollama(self, messages: List[Dict]) -> str:
        """Call Ollama API"""
        try:
            response = ollama.chat(
                model=self.model,
                messages=messages,
                stream=False,
                options={
                    'num_thread': config.OLLAMA_THREADS,
                    'num_ctx': 4096,
                    'repeat_penalty': 1.2,
                    'temperature': 0.3,  # Giảm để tăng tính nhất quán
                    'top_p': 0.8,
                    'top_k': 30,
                }
            )
            
            return response.get('message', {}).get('content', 'No response')
        
        except Exception as e:
            logger.error(f"Ollama API error: {str(e)}")
            raise
    
    async def process_file(self, file_path: str, file_name: str, chat_id: int) -> str:
        """Process uploaded text file"""
        try:
            if not file_name.endswith('.txt'):
                return "❌ Chỉ hỗ trợ file .txt"
            
            # Read file (with size limit for memory)
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read(config.MAX_MESSAGE_LENGTH)
            
            if len(content) == 0:
                return "❌ File trống hoặc không thể đọc"
            
            # Generate summary/analysis
            summary_prompt = f"""Phân tích và tóm tắt nội dung file sau ({file_name}):

{content}

Hãy:
1. Tóm tắt quá trình chính
2. Những điểm chính
3. Đề xuất hành động (nếu có)"""
            
            response = await self.generate_response(
                chat_id,
                'File Analysis',
                summary_prompt
            )
            
            return response
        
        except Exception as e:
            logger.error(f"Error processing file: {str(e)}")
            return f"❌ Lỗi xử lý file: {str(e)}"

ai_agent = AIAgent()

##############################################################################
# Telegram Bot Handlers
##############################################################################

# Authorization decorator
def require_admin(func):
    """Decorator to require admin access or whitelist"""
    @wraps(func)
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        chat_id = update.effective_chat.id
        # Check if admin or whitelisted
        if chat_id == config.ADMIN_CHAT_ID or db.is_whitelisted(chat_id):
            return await func(update, context)
        
        await update.message.reply_text(
            "❌ Bạn không có quyền truy cập bot này."
        )
        return
    return wrapper

async def start_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command"""
    if update.effective_chat.id != config.ADMIN_CHAT_ID:
        await update.message.reply_text("❌ Truy cập bị từ chối")
        return
    
    welcome_message = f"""
🤖 **Welcome to AI Agent Bot**

Xin chào {update.effective_user.first_name}! 👋

Tôi là một AI Agent được cấp quyền chạy cục bộ trên máy của bạn.
Có thể trò chuyện, trả lời câu hỏi, và phân tích tài liệu.

**Các lệnh chính:**
• /start - Hiển thị trợ giúp
• /sys - Kiểm tra tình trạng hệ thống
• /clear - Xóa lịch sử chat
• /help - Hướng dẫn chi tiết

**Admin commands:**
• /add <chat_id> [username] - Thêm người dùng vào whitelist
• /remove <chat_id> - Xóa người dùng khỏi whitelist
• /whitelist - Xem danh sách người dùng có quyền

**Tính năng:**
✓ Trò chuyện AI với tiếng Việt tốt
✓ Lưu lịch sử hội thoại
✓ Phân tích file .txt
✓ Hệ thống xếp hàng (Queue)

Cứ nhắn cho tôi bất cứ điều gì! 💬
    """
    
    await update.message.reply_text(welcome_message, parse_mode='Markdown')
    db.update_user_stats(update.effective_chat.id, update.effective_user.username or 'Unknown')

@require_admin
async def help_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command"""
    help_text = """
📖 **HƯỚNG DẪN CHI TIẾT**

**1. Chat với AI:**
   Gửi bất kỳ tin nhắn, tôi sẽ trả lời

**2. Phân tích File:**
   Gửi file .txt, tôi sẽ phân tích nội dung

**3. Lệnh Hệ Thống:**
   /sys - Xem RAM, CPU, Queue status
   /clear - Xóa lịch sử chat
   /stats - Thống kê sử dụng

**4. Queue System:**
   - Chỉ xử lý 1 request AI tại một lúc
   - Nếu đang xử lý, bạn sẽ nhận thông báo "Đang đợi"
   - Thứ tự được giữ lại

**Lưu Ý:**
⚠️  Thời gian phản hồi phụ thuộc vào độ phức tạp câu hỏi
⚠️  Lịch sử được lưu để cải thiện câu trả lời
⚠️  RAM giới hạn ở 8GB nên hệ thống được tối ưu hóa
    """
    
    await update.message.reply_text(help_text, parse_mode='Markdown')

@require_admin
async def sys_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /sys command - System status"""
    status = SystemMonitor.get_full_status()
    await update.message.reply_text(f"```\n{status}\n```", parse_mode='Markdown')

@require_admin
async def clear_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /clear command - Clear chat history"""
    chat_id = update.effective_chat.id
    try:
        with sqlite3.connect(config.DATABASE_PATH) as conn:
            conn.execute('DELETE FROM conversations WHERE chat_id = ?', (chat_id,))
            conn.commit()
        
        await update.message.reply_text("✅ Lịch sử chat đã được xóa")
    except Exception as e:
        await update.message.reply_text(f"❌ Lỗi: {str(e)}")

async def add_user_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /add command - Add user to whitelist (admin only)"""
    # Only admin can add users
    if update.effective_chat.id != config.ADMIN_CHAT_ID:
        await update.message.reply_text("❌ Chỉ admin có thể thêm người dùng")
        return
    
    if not context.args or len(context.args) < 1:
        await update.message.reply_text(
            "❌ Cách dùng: /add <chat_id> [username]\n"
            "Ví dụ: /add 1234567890\n"
            "Ví dụ: /add 1234567890 john_doe"
        )
        return
    
    try:
        chat_id = int(context.args[0])
        username = context.args[1] if len(context.args) > 1 else "unknown"
        
        if db.add_to_whitelist(chat_id, username, update.effective_chat.id):
            await update.message.reply_text(
                f"✅ Đã thêm người dùng {username} (ID: {chat_id}) vào whitelist"
            )
            logger.info(f"Admin {update.effective_user.username} added user {chat_id} to whitelist")
        else:
            await update.message.reply_text("❌ Lỗi khi thêm người dùng")
    except ValueError:
        await update.message.reply_text("❌ Chat ID phải là một số nguyên")
    except Exception as e:
        await update.message.reply_text(f"❌ Lỗi: {str(e)}")

async def remove_user_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /remove command - Remove user from whitelist (admin only)"""
    # Only admin can remove users
    if update.effective_chat.id != config.ADMIN_CHAT_ID:
        await update.message.reply_text("❌ Chỉ admin có thể xóa người dùng")
        return
    
    if not context.args or len(context.args) < 1:
        await update.message.reply_text(
            "❌ Cách dùng: /remove <chat_id>\n"
            "Ví dụ: /remove 1234567890"
        )
        return
    
    try:
        chat_id = int(context.args[0])
        
        if db.remove_from_whitelist(chat_id):
            await update.message.reply_text(f"✅ Đã xóa người dùng (ID: {chat_id}) khỏi whitelist")
            logger.info(f"Admin {update.effective_user.username} removed user {chat_id} from whitelist")
        else:
            await update.message.reply_text("❌ Lỗi khi xóa người dùng")
    except ValueError:
        await update.message.reply_text("❌ Chat ID phải là một số nguyên")
    except Exception as e:
        await update.message.reply_text(f"❌ Lỗi: {str(e)}")

async def whitelist_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /whitelist command - Show all whitelisted users (admin only)"""
    # Only admin can view whitelist
    if update.effective_chat.id != config.ADMIN_CHAT_ID:
        await update.message.reply_text("❌ Chỉ admin có thể xem whitelist")
        return
    
    whitelist = db.get_whitelist()
    
    if not whitelist:
        await update.message.reply_text("📝 Whitelist trống")
        return
    
    message = "📋 **DANH SÁCH NGƯỜI DÙNG CÓ QUYỀN:**\n\n"
    for chat_id, username in whitelist:
        message += f"• {username} (ID: {chat_id})\n"
    
    await update.message.reply_text(message, parse_mode='Markdown')

@require_admin
async def message_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle regular messages"""
    chat_id = update.effective_chat.id
    username = update.effective_user.username or update.effective_user.first_name
    
    # Validate message length
    message_text = update.message.text
    if len(message_text) > config.MAX_MESSAGE_LENGTH:
        await update.message.reply_text(
            f"❌ Tin nhắn quá dài (tối đa {config.MAX_MESSAGE_LENGTH} ký tự)"
        )
        return
    
    # Add to queue and get position
    try:
        position = await queue_manager.enqueue(chat_id, username, message_text)
        
        if position == 0:
            # Immediately processing
            await update.message.chat.send_action(CHAT_ACTION_TYPING)
        else:
            # In queue
            await update.message.reply_text(
                f"⏳ Đang đợi... (Vị trí trong hàng: #{position})\n"
                f"Trước bạn có {position-1} yêu cầu."
            )

        # Process the message (serialized by lock)
        async with queue_manager.lock:
            try:
                await update.message.chat.send_action(CHAT_ACTION_TYPING)
                response = await ai_agent.generate_response(chat_id, username, message_text)
            finally:
                queue_manager.mark_done(chat_id)
        
        # Defensive: normalize unexpected coroutine/response types
        if asyncio.iscoroutine(response):
            response = await response
        if not isinstance(response, str):
            response = str(response)

        # Split response if too long
        if len(response) > 4096:
            for i in range(0, len(response), 4096):
                chunk = response[i:i+4096]
                await update.message.reply_text(chunk)
        else:
            await update.message.reply_text(response)
        
        # Log message
        logger.info(f"[{username}] Processed message (queue pos: #{position})")
        
    except Exception as e:
        logger.error(f"Error processing message: {str(e)}")
        await update.message.reply_text(f"❌ Lỗi: {str(e)}")

@require_admin
async def document_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle file uploads"""
    chat_id = update.effective_chat.id
    username = update.effective_user.username or update.effective_user.first_name
    
    try:
        file = await update.message.document.get_file()
        file_name = update.message.document.file_name
        file_path = os.path.join(config.TEMP_FILES_PATH, file_name)
        
        # Download file
        await file.download_to_drive(file_path)
        
        # Process file
        async with queue_manager.lock:
            try:
                await update.message.chat.send_action(CHAT_ACTION_TYPING)
                response = await ai_agent.process_file(file_path, file_name, chat_id)
            finally:
                queue_manager.mark_done(chat_id)
        
        # Defensive: normalize unexpected coroutine/response types
        if asyncio.iscoroutine(response):
            response = await response
        if not isinstance(response, str):
            response = str(response)
        await update.message.reply_text(response)
        
        # Cleanup
        os.remove(file_path)
        
        logger.info(f"[{username}] Processed file: {file_name}")
        
    except Exception as e:
        logger.error(f"Error handling document: {str(e)}")
        await update.message.reply_text(f"❌ Lỗi xử lý file: {str(e)}")

##############################################################################
# Application Setup
##############################################################################

async def setup_application():
    """Setup Telegram application"""
    application = Application.builder().token(config.TELEGRAM_API_TOKEN).build()
    
    # Add handlers
    application.add_handler(CommandHandler('start', start_handler))
    application.add_handler(CommandHandler('help', help_handler))
    application.add_handler(CommandHandler('sys', sys_handler))
    application.add_handler(CommandHandler('clear', clear_handler))
    application.add_handler(CommandHandler('add', add_user_handler))
    application.add_handler(CommandHandler('remove', remove_user_handler))
    application.add_handler(CommandHandler('whitelist', whitelist_handler))
    application.add_handler(MessageHandler(filters.Document.TEXT, document_handler))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, message_handler))
    
    return application

##############################################################################
# Main Entry Point
##############################################################################

async def main():
    """Main entry point"""
    logger.info("Starting AI Agent Bot...")
    logger.info(f"Admin Chat ID: {config.ADMIN_CHAT_ID}")
    logger.info(f"Model: {config.OLLAMA_MODEL}")
    logger.info(f"Database: {config.DATABASE_PATH}")
    
    # Check Ollama connectivity
    try:
        models = ollama.list()
        model_entries = models.get('models', []) if isinstance(models, dict) else []
        model_names = [m.get('name') or m.get('model') or 'unknown' for m in model_entries]
        logger.info(f"Available models: {model_names}")
    except Exception as e:
        logger.error(f"Cannot connect to Ollama: {str(e)}")
        sys.exit(1)
    
    # Setup and start application
    application = await setup_application()
    
    try:
        await application.initialize()
        await application.start()
        await application.updater.start_polling()
        
        # Keep running
        while True:
            await asyncio.sleep(1)
    
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    
    finally:
        await application.stop()
        await application.shutdown()

if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nBot stopped by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Fatal error: {str(e)}")
        sys.exit(1)
