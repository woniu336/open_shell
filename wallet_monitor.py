import requests
import json
import time
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime

# ============ 配置区域 ============
# 钱包地址
WALLET_ADDRESS = "TM1zzNDZD2DPASbKcgdVoTYhfmYgtfwx9R"

# 邮件配置
SMTP_SERVER = "smtp.qq.com"  # QQ邮箱
SMTP_PORT = 587
SENDER_EMAIL = "your_email@qq.com"  # 发件人邮箱
SENDER_PASSWORD = "your_auth_code"  # 邮箱授权码（不是登录密码！）
RECEIVER_EMAIL = "receiver@qq.com"  # 收件人邮箱

# 监控间隔（秒）- 建议不少于900秒（15分钟）
CHECK_INTERVAL = 900  # 默认15分钟

# 数据存储文件
CACHE_FILE = "wallet_cache.json"
# ================================

class WalletMonitor:
    def __init__(self):
        self.api_base = "https://api.trongrid.io"
        self.last_transactions = self.load_cache()
        self.validate_config()
        
    def validate_config(self):
        """验证配置完整性"""
        if SENDER_PASSWORD == 'your_auth_code':
            print("⚠️  警告: 未配置邮箱授权码，邮件通知将无法使用")
            print("   QQ邮箱获取授权码: 邮箱设置 -> 账户 -> POP3/SMTP服务")
        
        if CHECK_INTERVAL < 900:
            print(f"⚠️  警告: 检查间隔({CHECK_INTERVAL}秒)过短，可能触发API限流")
            print("   建议设置为900秒（15分钟）或以上")
        
    def load_cache(self):
        """加载上次的交易记录"""
        try:
            with open(CACHE_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except FileNotFoundError:
            return {"usdt": [], "trx": []}
        except json.JSONDecodeError:
            print("⚠️  缓存文件损坏，重新初始化")
            return {"usdt": [], "trx": []}
    
    def save_cache(self, transactions):
        """保存交易记录到缓存"""
        try:
            with open(CACHE_FILE, 'w', encoding='utf-8') as f:
                json.dump(transactions, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"✗ 保存缓存失败: {e}")
    
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
            elif response.status_code == 403:
                print("⚠️  API访问被限流(403)，请等待30秒或考虑申请API Key")
            else:
                print(f"⚠️  API返回错误: {response.status_code}")
        except Exception as e:
            print(f"✗ 获取账户信息失败: {e}")
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
            elif response.status_code == 403:
                print("⚠️  API访问被限流(403)，跳过本次USDT查询")
            else:
                print(f"⚠️  获取USDT交易失败: {response.status_code}")
        except Exception as e:
            print(f"✗ 获取USDT交易失败: {e}")
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
                    raw_data = tx.get('raw_data', {})
                    contracts = raw_data.get('contract', [])
                    
                    if contracts and contracts[0].get('type') == 'TransferContract':
                        contract = contracts[0]
                        param_value = contract.get('parameter', {}).get('value', {})
                        value_sun = param_value.get('amount', 0)
                        
                        transactions.append({
                            'hash': tx.get('txID'),
                            'from': param_value.get('owner_address'),
                            'to': param_value.get('to_address'),
                            'value': value_sun / 1_000_000,
                            'timestamp': tx.get('block_timestamp'),
                            'type': 'in' if param_value.get('to_address') == WALLET_ADDRESS else 'out'
                        })
                return transactions
            elif response.status_code == 403:
                print("⚠️  API访问被限流(403)，跳过本次TRX查询")
            else:
                print(f"⚠️  获取TRX交易失败: {response.status_code}")
        except Exception as e:
            print(f"✗ 获取TRX交易失败: {e}")
        return []
    
    def send_email(self, subject, body):
        """发送邮件通知"""
        if SENDER_PASSWORD == 'your_auth_code':
            print("✗ 邮件未发送: 请先配置邮箱授权码")
            return False
            
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
    
    def format_transaction_email(self, new_transactions, account_info):
        """格式化交易信息为邮件内容"""
        trx_balance = account_info.get('trx_balance', 0) if account_info else 0
        
        html = f"""
        <html>
        <head>
            <style>
                body {{ font-family: 'Arial', 'Microsoft YaHei', sans-serif; background-color: #f5f5f5; padding: 20px; }}
                .container {{ max-width: 600px; margin: 0 auto; background-color: white; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
                .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; text-align: center; }}
                .header h2 {{ margin: 0; font-size: 24px; }}
                .balance {{ background-color: #f8f9fa; padding: 15px; margin: 15px; border-radius: 8px; text-align: center; }}
                .balance-value {{ font-size: 28px; font-weight: bold; color: #667eea; }}
                .transaction {{ border: 1px solid #e0e0e0; margin: 15px; padding: 15px; border-radius: 8px; }}
                .in {{ background-color: #e8f5e9; border-left: 4px solid #4caf50; }}
                .out {{ background-color: #ffebee; border-left: 4px solid #f44336; }}
                .tx-amount {{ font-size: 20px; font-weight: bold; margin-bottom: 10px; }}
                .tx-info {{ color: #666; font-size: 13px; line-height: 1.6; }}
                .tx-hash {{ background-color: #f5f5f5; padding: 5px; border-radius: 3px; font-family: monospace; word-break: break-all; }}
                .footer {{ text-align: center; padding: 15px; color: #999; font-size: 12px; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h2>🔔 钱包交易提醒</h2>
                    <p style="margin: 5px 0; font-size: 12px;">检测时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
                </div>
                
                <div class="balance">
                    <div style="color: #666; font-size: 14px; margin-bottom: 5px;">当前余额</div>
                    <div class="balance-value">{trx_balance:.2f} TRX</div>
                    <div style="color: #999; font-size: 12px; margin-top: 5px;">地址: {WALLET_ADDRESS[:10]}...{WALLET_ADDRESS[-6:]}</div>
                </div>
        """
        
        if new_transactions.get('usdt'):
            html += '<div style="padding: 0 15px;"><h3 style="color: #333;">💰 新的 USDT 交易</h3></div>'
            for tx in new_transactions['usdt']:
                direction = "转入 ↓" if tx['type'] == 'in' else "转出 ↑"
                direction_color = "#4caf50" if tx['type'] == 'in' else "#f44336"
                css_class = tx['type']
                counterparty = tx['to'] if tx['type'] == 'out' else tx['from']
                
                html += f"""
                <div class="transaction {css_class}">
                    <div class="tx-amount" style="color: {direction_color};">{direction} {tx['value']:.2f} USDT</div>
                    <div class="tx-info">
                        <strong>对方地址:</strong> {counterparty[:10]}...{counterparty[-6:]}<br>
                        <strong>交易时间:</strong> {datetime.fromtimestamp(tx['timestamp']/1000).strftime('%Y-%m-%d %H:%M:%S')}<br>
                        <strong>交易哈希:</strong><br>
                        <div class="tx-hash">{tx['hash']}</div>
                    </div>
                </div>
                """
        
        if new_transactions.get('trx'):
            html += '<div style="padding: 0 15px;"><h3 style="color: #333;">⚡ 新的 TRX 交易</h3></div>'
            for tx in new_transactions['trx']:
                direction = "转入 ↓" if tx['type'] == 'in' else "转出 ↑"
                direction_color = "#4caf50" if tx['type'] == 'in' else "#f44336"
                css_class = tx['type']
                counterparty = tx['to'] if tx['type'] == 'out' else tx['from']
                
                html += f"""
                <div class="transaction {css_class}">
                    <div class="tx-amount" style="color: {direction_color};">{direction} {tx['value']:.6f} TRX</div>
                    <div class="tx-info">
                        <strong>对方地址:</strong> {counterparty[:10]}...{counterparty[-6:]}<br>
                        <strong>交易时间:</strong> {datetime.fromtimestamp(tx['timestamp']/1000).strftime('%Y-%m-%d %H:%M:%S')}<br>
                        <strong>交易哈希:</strong><br>
                        <div class="tx-hash">{tx['hash']}</div>
                    </div>
                </div>
                """
        
        html += """
                <div class="footer">
                    由 TRON 钱包监控系统自动发送<br>
                    请勿回复此邮件
                </div>
            </div>
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
            account_info = self.get_account_info()
            
            subject = f"🔔 检测到 {total_new} 笔新交易 - {datetime.now().strftime('%m/%d %H:%M')}"
            body = self.format_transaction_email(new_transactions, account_info)
            self.send_email(subject, body)
            
            # 更新缓存
            self.last_transactions = {'usdt': current_usdt, 'trx': current_trx}
            self.save_cache(self.last_transactions)
            print(f"✓ 检测到 {total_new} 笔新交易")
        else:
            print("○ 暂无新交易")
    
    def run(self):
        """启动监控"""
        print("="*60)
        print("🚀 TRON 钱包监控程序启动")
        print("="*60)
        print(f"📍 监控地址: {WALLET_ADDRESS}")
        print(f"📧 通知邮箱: {RECEIVER_EMAIL}")
        print(f"⏱️  检查间隔: {CHECK_INTERVAL}秒 ({CHECK_INTERVAL/60:.1f}分钟)")
        print(f"⚠️  无API Key模式: 可能受到访问限流")
        print("="*60)
        
        # 首次运行，初始化缓存
        if not self.last_transactions.get('usdt') and not self.last_transactions.get('trx'):
            print("📥 首次运行，正在初始化交易记录...")
            self.last_transactions = {
                'usdt': self.get_usdt_transactions(),
                'trx': self.get_trx_transactions()
            }
            self.save_cache(self.last_transactions)
            print(f"✓ 初始化完成，已加载 {len(self.last_transactions['usdt'])} 笔USDT和 {len(self.last_transactions['trx'])} 笔TRX交易")
            print("🔍 开始监控...\n")
        
        while True:
            try:
                self.check_for_changes()
                time.sleep(CHECK_INTERVAL)
            except KeyboardInterrupt:
                print("\n⏹️  程序已停止")
                break
            except Exception as e:
                print(f"✗ 发生错误: {e}")
                print(f"⏱️  {CHECK_INTERVAL}秒后重试...")
                time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    print("""
    ╔══════════════════════════════════════════════════╗
    ║         TRON 钱包监控系统 v2.0                  ║
    ║     支持 TRC20-USDT 和 TRX 交易实时监控         ║
    ╚══════════════════════════════════════════════════╝
    
    ⚙️  配置说明:
    1. 修改脚本顶部的配置变量:
       - WALLET_ADDRESS: 要监控的钱包地址
       - SENDER_EMAIL: 发件邮箱
       - SENDER_PASSWORD: QQ邮箱授权码（非登录密码）
       - RECEIVER_EMAIL: 收件邮箱
       - CHECK_INTERVAL: 检查间隔（建议≥900秒）
    
    2. 获取QQ邮箱授权码:
       登录QQ邮箱 → 设置 → 账户 → POP3/SMTP服务 → 生成授权码
    
    ⚠️  注意: 
    - 本脚本未使用API Key，建议检查间隔≥15分钟避免限流
    - 如需频繁查询，请访问 https://www.trongrid.io 申请API Key
    - 首次运行会初始化最近20笔交易，不会发送通知
    """)
    
    # input("按回车键开始运行...")
    
    try:
        monitor = WalletMonitor()
        monitor.run()
    except Exception as e:
        print(f"\n❌ 启动失败: {e}")
        print("请检查配置是否正确")