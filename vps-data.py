import datetime
import smtplib
from email.mime.text import MIMEText
from email.header import Header
import base64

# define servers with their expiry dates
servers = {'斯巴达': '2024-05-15', 'ovh': '2024-06-6'}

def check_server_expiry(server_name, expiry_date):
    expiry_date = datetime.datetime.strptime(expiry_date, "%Y-%m-%d").date()
    current_date = datetime.date.today()

    if expiry_date < current_date:
        print(f"{server_name} 已过期")
    else:
        remaining_days = (expiry_date - current_date).days
        if remaining_days <= 5:
            send_expiry_reminder_email(server_name, remaining_days)

def send_expiry_reminder_email(server_name, remaining_days):
    sender_email = '发送邮箱'
    receiver_email = '接收邮箱'
    smtp_server = 'smtp.qq.com'
    smtp_port = 587
    smtp_username = '发送邮箱'
    smtp_password = '身份验证的密码(不是QQ密码)'
    
    subject = f'{server_name} 即将过期'
    body = f'您的 {server_name} 将在 {remaining_days} 天内过期，请尽快续费。'
    
    msg = MIMEText(body, 'plain', 'utf-8')
    msg['Subject'] = Header(subject, 'utf-8')
    sender_name_b64 = base64.b64encode("服务器到期提醒".encode('utf-8')).decode('ascii')
    msg['From'] = f'=?utf-8?B?{sender_name_b64}?= <{sender_email}>'
    msg['To'] = receiver_email
    
    try:
        with smtplib.SMTP(smtp_server, smtp_port) as server:
            server.ehlo()
            server.starttls()
            server.login(smtp_username, smtp_password)
            server.sendmail(sender_email, receiver_email, msg.as_string())
        print("邮件发送成功")
    except Exception as e:
        print(f"邮件发送失败: {str(e)}")

def main():
    for server_name, expiry_date in servers.items():
        check_server_expiry(server_name, expiry_date)

if __name__ == "__main__":
    main()