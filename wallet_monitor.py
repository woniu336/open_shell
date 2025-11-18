import requests
import json
import time
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime
import hashlib

# ============ 配置区域 ============
# 钱包地址
WALLET_ADDRESS = "TCTzWxB668iFqGZy7FbrSmiSR28XsnowTk"

# 邮件配置
SMTP_SERVER = "smtp.qq.com"  # 例如: smtp.gmail.com, smtp.qq.com, smtp.163.com
SMTP_PORT = 587
SENDER_EMAIL = "111111@qq.com"  # 发件人邮箱
SENDER_PASSWORD = "2222222"  # 邮箱授权码（不是登录密码）
RECEIVER_EMAIL = "333333@qq.com"  # 收件人邮箱

# 监控间隔（秒）
CHECK_INTERVAL = 900  # 每900秒检查一次

# 数据存储文件
CACHE_FILE = "wallet_cache.json"
# ================================

class WalletMonitor:
    def __init__(self):
        self.api_base = "https://api.trongrid.io"
        self.last_transactions = self.load_cache()
        
    def load_cache(self):
        """加载上次的交易记录"""
        try:
            with open(CACHE_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except FileNotFoundError:
            return {"usdt": [], "trx": []}
    
    def save_cache(self, transactions):
        """保存交易记录到缓存"""
        with open(CACHE_FILE, 'w', encoding='utf-8') as f:
            json.dump(transactions, f, ensure_ascii=False, indent=2)
    
    def get_account_info(self):
        """获取账户基本信息"""
        try:
            url = f"{self.api_base}/v1/accounts/{WALLET_ADDRESS}"
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                if data.get('data'):
                    account = data['data'][0]
                    balance_sun = account.get('balance', 0)
                    trx_balance = balance_sun / 1_000_000  # SUN转TRX
                    return {
                        'trx_balance': trx_balance,
                        'create_time': account.get('create_time', 0)
                    }
        except Exception as e:
            print(f"获取账户信息失败: {e}")
        return None
    
    def get_usdt_transactions(self):
        """获取USDT交易记录（TRC20）"""
        try:
            # TRC20-USDT合约地址
            contract_address = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
            url = f"{self.api_base}/v1/accounts/{WALLET_ADDRESS}/transactions/trc20"
            params = {
                "limit": 20,
                "contract_address": contract_address
            }
            response = requests.get(url, params=params, timeout=10)
            if response.status_code == 200:
                data = response.json()
                transactions = []
                for tx in data.get('data', []):
                    transactions.append({
                        'hash': tx.get('transaction_id'),
                        'from': tx.get('from'),
                        'to': tx.get('to'),
                        'value': int(tx.get('value', 0)) / 1_000_000,  # USDT 6位小数
                        'timestamp': tx.get('block_timestamp'),
                        'type': 'in' if tx.get('to') == WALLET_ADDRESS else 'out'
                    })
                return transactions
        except Exception as e:
            print(f"获取USDT交易失败: {e}")
        return []
    
    def get_trx_transactions(self):
        """获取TRX交易记录"""
        try:
            url = f"{self.api_base}/v1/accounts/{WALLET_ADDRESS}/transactions"
            params = {"limit": 20}
            response = requests.get(url, params=params, timeout=10)
            if response.status_code == 200:
                data = response.json()
                transactions = []
                for tx in data.get('data', []):
                    if tx.get('raw_data', {}).get('contract', [{}])[0].get('type') == 'TransferContract':
                        contract = tx['raw_data']['contract'][0]
                        value_sun = contract.get('parameter', {}).get('value', {}).get('amount', 0)
                        transactions.append({
                            'hash': tx.get('txID'),
                            'from': contract.get('parameter', {}).get('value', {}).get('owner_address'),
                            'to': contract.get('parameter', {}).get('value', {}).get('to_address'),
                            'value': value_sun / 1_000_000,
                            'timestamp': tx.get('block_timestamp'),
                            'type': 'in' if contract.get('parameter', {}).get('value', {}).get('to_address') == WALLET_ADDRESS else 'out'
                        })
                return transactions
        except Exception as e:
            print(f"获取TRX交易失败: {e}")
        return []
    
    def send_email(self, subject, body):
        """发送邮件通知"""
        try:
            msg = MIMEMultipart()
            msg['From'] = SENDER_EMAIL
            msg['To'] = RECEIVER_EMAIL
            msg['Subject'] = subject
            
            msg.attach(MIMEText(body, 'html', 'utf-8'))
            
            server = smtplib.SMTP(SMTP_SERVER, SMTP_PORT)
            server.starttls()
            server.login(SENDER_EMAIL, SENDER_PASSWORD)
            server.send_message(msg)
            server.quit()
            print(f"✓ 邮件发送成功: {subject}")
            return True
        except Exception as e:
            print(f"✗ 邮件发送失败: {e}")
            return False
    
    def format_transaction_email(self, new_transactions):
        """格式化交易信息为邮件内容"""
        html = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; }}
                .header {{ background-color: #4CAF50; color: white; padding: 10px; }}
                .transaction {{ border: 1px solid #ddd; margin: 10px 0; padding: 10px; border-radius: 5px; }}
                .in {{ background-color: #e8f5e9; }}
                .out {{ background-color: #ffebee; }}
                .info {{ color: #666; font-size: 12px; }}
            </style>
        </head>
        <body>
            <div class="header">
                <h2>🔔 钱包交易提醒</h2>
                <p>钱包地址: {WALLET_ADDRESS}</p>
                <p>检测时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            </div>
        """
        
        if new_transactions.get('usdt'):
            html += "<h3>💰 新的USDT交易:</h3>"
            for tx in new_transactions['usdt']:
                direction = "转入 ↓" if tx['type'] == 'in' else "转出 ↑"
                css_class = tx['type']
                html += f"""
                <div class="transaction {css_class}">
                    <strong>{direction} {tx['value']:.2f} USDT</strong><br>
                    <span class="info">对方: {tx['to'] if tx['type'] == 'out' else tx['from']}</span><br>
                    <span class="info">时间: {datetime.fromtimestamp(tx['timestamp']/1000).strftime('%Y-%m-%d %H:%M:%S')}</span><br>
                    <span class="info">交易哈希: {tx['hash'][:16]}...</span>
                </div>
                """
        
        if new_transactions.get('trx'):
            html += "<h3>⚡ 新的TRX交易:</h3>"
            for tx in new_transactions['trx']:
                direction = "转入 ↓" if tx['type'] == 'in' else "转出 ↑"
                css_class = tx['type']
                html += f"""
                <div class="transaction {css_class}">
                    <strong>{direction} {tx['value']:.2f} TRX</strong><br>
                    <span class="info">对方: {tx['to'] if tx['type'] == 'out' else tx['from']}</span><br>
                    <span class="info">时间: {datetime.fromtimestamp(tx['timestamp']/1000).strftime('%Y-%m-%d %H:%M:%S')}</span><br>
                    <span class="info">交易哈希: {tx['hash'][:16]}...</span>
                </div>
                """
        
        html += """
        </body>
        </html>
        """
        return html
    
    def check_for_changes(self):
        """检查交易变化"""
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 正在检查交易...")
        
        # 获取最新交易
        current_usdt = self.get_usdt_transactions()
        current_trx = self.get_trx_transactions()
        
        # 检测新交易
        new_transactions = {'usdt': [], 'trx': []}
        
        # 检查USDT新交易
        last_usdt_hashes = {tx['hash'] for tx in self.last_transactions.get('usdt', [])}
        for tx in current_usdt:
            if tx['hash'] not in last_usdt_hashes:
                new_transactions['usdt'].append(tx)
        
        # 检查TRX新交易
        last_trx_hashes = {tx['hash'] for tx in self.last_transactions.get('trx', [])}
        for tx in current_trx:
            if tx['hash'] not in last_trx_hashes:
                new_transactions['trx'].append(tx)
        
        # 如果有新交易，发送邮件
        if new_transactions['usdt'] or new_transactions['trx']:
            total_new = len(new_transactions['usdt']) + len(new_transactions['trx'])
            subject = f"🔔 检测到 {total_new} 笔新交易"
            body = self.format_transaction_email(new_transactions)
            self.send_email(subject, body)
            
            # 更新缓存
            self.last_transactions = {'usdt': current_usdt, 'trx': current_trx}
            self.save_cache(self.last_transactions)
            print(f"✓ 检测到 {total_new} 笔新交易")
        else:
            print("○ 暂无新交易")
    
    def run(self):
        """启动监控"""
        print("="*50)
        print("🚀 USDT钱包监控程序启动")
        print(f"📍 监控地址: {WALLET_ADDRESS}")
        print(f"📧 通知邮箱: {RECEIVER_EMAIL}")
        print(f"⏱️  检查间隔: {CHECK_INTERVAL}秒")
        print("="*50)
        
        # 首次运行，初始化缓存
        if not self.last_transactions.get('usdt') and not self.last_transactions.get('trx'):
            print("首次运行，初始化交易记录...")
            self.last_transactions = {
                'usdt': self.get_usdt_transactions(),
                'trx': self.get_trx_transactions()
            }
            self.save_cache(self.last_transactions)
            print("✓ 初始化完成，开始监控...")
        
        while True:
            try:
                self.check_for_changes()
                time.sleep(CHECK_INTERVAL)
            except KeyboardInterrupt:
                print("\n程序已停止")
                break
            except Exception as e:
                print(f"✗ 发生错误: {e}")
                time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    # 使用前请先配置邮箱信息
    monitor = WalletMonitor()
    monitor.run()
