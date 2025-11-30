#!/bin/bash

# OVH服务器监控 - 完整安装脚本（包含Node.js安装）


set -e

echo "=========================================="
echo "   OVH服务器监控 - 完整安装脚本"
echo "=========================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检测操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo -e "${RED}无法检测操作系统${NC}"
    exit 1
fi

echo -e "${BLUE}检测到操作系统: $OS $VERSION${NC}"
echo ""

# 检查Node.js
echo -e "${GREEN}[1/9]${NC} 检查Node.js环境..."
if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}  未检测到Node.js，开始安装...${NC}"
    
    case $OS in
        ubuntu|debian)
            echo "  安装依赖..."
            sudo apt-get update
            sudo apt-get install -y curl
            
            echo "  添加NodeSource仓库..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            
            echo "  安装Node.js..."
            sudo apt-get install -y nodejs
            ;;
            
        centos|rhel|fedora)
            echo "  安装依赖..."
            sudo yum install -y curl
            
            echo "  添加NodeSource仓库..."
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
            
            echo "  安装Node.js..."
            sudo yum install -y nodejs
            ;;
            
        *)
            echo -e "${RED}  不支持的操作系统，请手动安装Node.js${NC}"
            echo "  访问: https://nodejs.org/"
            exit 1
            ;;
    esac
    
    # 验证安装
    if ! command -v node &> /dev/null; then
        echo -e "${RED}  Node.js安装失败${NC}"
        exit 1
    fi
    
    echo -e "  ${GREEN}✓ Node.js安装成功${NC}"
fi

NODE_VERSION=$(node -v)
NPM_VERSION=$(npm -v)
echo -e "  ✓ Node.js版本: ${GREEN}${NODE_VERSION}${NC}"
echo -e "  ✓ npm版本: ${GREEN}${NPM_VERSION}${NC}"

# 检查PM2
echo -e "${GREEN}[2/9]${NC} 检查PM2..."
if ! command -v pm2 &> /dev/null; then
    echo -e "${YELLOW}  PM2未安装，正在安装...${NC}"
    sudo npm install -g pm2
    echo -e "  ${GREEN}✓ PM2安装完成${NC}"
else
    PM2_VERSION=$(pm2 -v)
    echo -e "  ✓ PM2已安装 (版本: ${PM2_VERSION})"
fi

# 创建项目目录
echo -e "${GREEN}[3/9]${NC} 创建项目目录..."
PROJECT_DIR="ovh-monitor-dingtalk"
if [ -d "$PROJECT_DIR" ]; then
    echo -e "${YELLOW}  目录 $PROJECT_DIR 已存在${NC}"
    read -p "  是否删除并重新创建? (y/n): " overwrite
    if [ "$overwrite" == "y" ]; then
        # 如果服务正在运行，先停止
        cd "$PROJECT_DIR" 2>/dev/null && pm2 delete ovh-monitor 2>/dev/null || true
        cd ..
        rm -rf "$PROJECT_DIR"
        echo -e "  ${GREEN}✓ 旧目录已删除${NC}"
    else
        echo -e "${YELLOW}  使用现有目录${NC}"
    fi
fi

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
echo -e "  ✓ 项目目录: ${BLUE}$(pwd)${NC}"

# 获取钉钉配置
echo -e "${GREEN}[4/9]${NC} 配置钉钉机器人..."
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}如何创建钉钉机器人:${NC}"
echo "1. 打开钉钉群聊"
echo "2. 群设置 → 智能群助手 → 添加机器人"
echo "3. 选择 '自定义' 机器人"
echo "4. 设置名称(如: OVH监控)"
echo "5. 安全设置选择 '加签' (推荐)"
echo "6. 复制 Webhook地址 和 加签密钥"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p "请输入钉钉Webhook地址: " DINGTALK_WEBHOOK
while [ -z "$DINGTALK_WEBHOOK" ]; do
    echo -e "${RED}错误: Webhook地址不能为空${NC}"
    read -p "请输入钉钉Webhook地址: " DINGTALK_WEBHOOK
done

read -p "请输入加签密钥(可选,直接回车跳过): " DINGTALK_SECRET

echo -e "  ${GREEN}✓ 配置已保存${NC}"

# 创建package.json
echo -e "${GREEN}[5/9]${NC} 创建package.json..."
cat > package.json << 'EOF'
{
  "name": "ovh-monitor-dingtalk",
  "version": "1.0.0",
  "type": "module",
  "description": "OVH Server Availability Monitor with DingTalk Notification",
  "main": "monitor.js",
  "scripts": {
    "start": "pm2 start ecosystem.config.cjs",
    "stop": "pm2 stop ovh-monitor",
    "restart": "pm2 restart ovh-monitor",
    "logs": "pm2 logs ovh-monitor",
    "monit": "pm2 monit",
    "status": "pm2 list"
  },
  "dependencies": {
    "node-fetch": "^3.3.2"
  }
}
EOF
echo -e "  ${GREEN}✓ package.json创建完成${NC}"

# 创建monitor.js
echo -e "${GREEN}[6/9]${NC} 创建监控脚本..."
cat > monitor.js << 'EOMONITOR'
import fetch from 'node-fetch';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import crypto from 'crypto';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const AVAILABILITY_API_URL = 'https://eu.api.ovh.com/v1/dedicated/server/datacenter/availabilities';
const CATALOG_API_URL = 'https://eu.api.ovh.com/v1/order/catalog/public/eco?ovhSubsidiary=IE';
const DINGTALK_WEBHOOK = process.env.DINGTALK_WEBHOOK || '';
const DINGTALK_SECRET = process.env.DINGTALK_SECRET || '';
const CHECK_INTERVAL = 1000 * 60;
const TARGET_PREFIXES = ['25sk', '24sk', '25rise'];

const DATA_DIR = path.join(__dirname, 'data');
const LAST_DATA_FILE = path.join(DATA_DIR, 'last_data.json');
const LAST_CHECK_FILE = path.join(DATA_DIR, 'last_check.json');

async function ensureDataDir() {
  try {
    await fs.mkdir(DATA_DIR, { recursive: true });
  } catch (error) {
    if (error.code !== 'EEXIST') {
      console.error('创建数据目录失败:', error.message);
    }
  }
}

function generateDingTalkSign() {
  if (!DINGTALK_SECRET) return '';
  
  const timestamp = Date.now();
  const stringToSign = `${timestamp}\n${DINGTALK_SECRET}`;
  const hmac = crypto.createHmac('sha256', DINGTALK_SECRET);
  hmac.update(stringToSign);
  const sign = encodeURIComponent(hmac.digest('base64'));
  
  return { timestamp, sign };
}

async function getServerAvailability() {
  try {
    const response = await fetch(AVAILABILITY_API_URL);
    if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
    return await response.json();
  } catch (error) {
    console.error('获取可用性API数据失败:', error.message);
    return null;
  }
}

async function getCatalogData() {
  try {
    const response = await fetch(CATALOG_API_URL);
    if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
    return await response.json();
  } catch (error) {
    console.error('获取目录API数据失败:', error.message);
    return null;
  }
}

function getInvoiceName(catalogData, planCode) {
  if (!catalogData || !Array.isArray(catalogData.plans)) return '未知产品';
  const plan = catalogData.plans.find(p => p.planCode === planCode);
  return plan?.invoiceName || '未知产品';
}

function filterAndSimplifyData(data) {
  if (!Array.isArray(data)) return [];
  return data
    .filter(item => item.server && TARGET_PREFIXES.some(prefix => item.server.startsWith(prefix)))
    .map(item => ({
      fqn: item.fqn,
      server: item.server,
      planCode: item.planCode,
      datacenters: item.datacenters.map(dc => ({
        datacenter: dc.datacenter,
        availability: dc.availability
      }))
    }));
}

async function readLastData() {
  try {
    const data = await fs.readFile(LAST_DATA_FILE, 'utf-8');
    return JSON.parse(data);
  } catch (error) {
    return [];
  }
}

async function readLastCheck() {
  try {
    const data = await fs.readFile(LAST_CHECK_FILE, 'utf-8');
    return JSON.parse(data).timestamp || 0;
  } catch (error) {
    return 0;
  }
}

async function saveCurrentData(data) {
  const simplifiedData = filterAndSimplifyData(data);
  await fs.writeFile(LAST_DATA_FILE, JSON.stringify(simplifiedData, null, 2));
  await fs.writeFile(LAST_CHECK_FILE, JSON.stringify({ timestamp: Date.now() }, null, 2));
}

function isTargetServer(server) {
  return server?.server && TARGET_PREFIXES.some(prefix => server.server.startsWith(prefix));
}

async function findNewServers(oldData, newData, catalogData) {
  if (!Array.isArray(newData)) return [];
  if (!Array.isArray(oldData)) return filterAndSimplifyData(newData);

  const newServers = [];
  
  newData.forEach(newItem => {
    if (!isTargetServer(newItem)) return;
    const oldItem = oldData.find(item => item.fqn === newItem.fqn);
    
    if (!oldItem) {
      newItem.datacenters.forEach(dc => {
        if (dc.availability !== 'unavailable') {
          newServers.push({
            ...newItem,
            datacenter: dc.datacenter,
            availability: dc.availability,
            invoiceName: getInvoiceName(catalogData, newItem.planCode)
          });
        }
      });
      return;
    }

    newItem.datacenters.forEach(newDc => {
      const oldDc = oldItem.datacenters.find(od => od.datacenter === newDc.datacenter);
      const wasUnavailable = !oldDc || oldDc.availability === 'unavailable';
      const isAvailable = newDc.availability !== 'unavailable';
      if (wasUnavailable && isAvailable) {
        newServers.push({
          ...newItem,
          datacenter: newDc.datacenter,
          availability: newDc.availability,
          invoiceName: getInvoiceName(catalogData, newItem.planCode)
        });
      }
    });
  });

  return newServers;
}

async function sendDingTalkMessage(servers) {
  if (!servers?.length || !DINGTALK_WEBHOOK) return;

  const { timestamp, sign } = generateDingTalkSign();
  let webhookUrl = DINGTALK_WEBHOOK;
  
  if (sign) {
    webhookUrl += `&timestamp=${timestamp}&sign=${sign}`;
  }

  let markdownText = '## 🎉 发现新的可用服务器！\n\n';
  
  servers.forEach((server, index) => {
    markdownText += `### ${index + 1}. ${server.invoiceName}\n\n`;
    markdownText += `- **FQN**: ${server.fqn}\n`;
    markdownText += `- **服务器**: ${server.server}\n`;
    markdownText += `- **数据中心**: ${server.datacenter}\n`;
    markdownText += `- **可用性**: ${server.availability}\n\n`;
    markdownText += '---\n\n';
  });

  const payload = {
    msgtype: 'markdown',
    markdown: {
      title: '🎉 OVH服务器上新提醒',
      text: markdownText
    }
  };

  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload)
    });

    const result = await response.json();
    if (result.errcode !== 0) {
      console.error('发送钉钉消息失败:', result.errmsg);
    } else {
      console.log('✓ 钉钉消息发送成功');
    }
  } catch (error) {
    console.error('发送钉钉消息异常:', error.message);
  }
}

async function monitorServers() {
  const lastCheck = await readLastCheck();
  const now = Date.now();
  
  if (now - lastCheck < CHECK_INTERVAL) {
    return false;
  }

  console.log('✓ 检查服务器可用性...', new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' }));
  
  const currentData = await getServerAvailability();
  const catalogData = await getCatalogData();
  if (!currentData || !catalogData) return false;

  const lastData = await readLastData();
  const newServers = await findNewServers(lastData, currentData, catalogData);

  if (newServers.length > 0) {
    console.log(`✓ 发现 ${newServers.length} 个新可用服务器`);
    await sendDingTalkMessage(newServers);
  } else {
    console.log('✓ 未发现新的可用服务器');
  }

  await saveCurrentData(currentData);
  return true;
}

async function startMonitoring() {
  let isRunning = false;

  const runCheck = async () => {
    if (isRunning) {
      console.log('⚠ 上一次检查仍在运行，跳过本次循环');
      return;
    }

    try {
      isRunning = true;
      await monitorServers();
    } catch (error) {
      console.error('✗ 检查循环出错:', error.message);
    } finally {
      isRunning = false;
    }

    setTimeout(runCheck, CHECK_INTERVAL);
  };

  console.log('🚀 启动服务器监控...');
  console.log(`📋 监控型号: ${TARGET_PREFIXES.join(', ')}`);
  console.log(`⏱️  检查间隔: ${CHECK_INTERVAL / 1000 / 60} 分钟`);
  runCheck();
}

(async () => {
  try {
    await ensureDataDir();
    await startMonitoring();
  } catch (error) {
    console.error('✗ 初始化失败:', error.message);
    process.exit(1);
  }
})();

process.on('SIGINT', async () => {
  console.log('\n👋 正在关闭监控服务...');
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log('\n👋 正在关闭监控服务...');
  process.exit(0);
});
EOMONITOR
echo -e "  ${GREEN}✓ monitor.js创建完成${NC}"

# 创建ecosystem.config.cjs
echo -e "${GREEN}[7/9]${NC} 创建PM2配置文件..."
cat > ecosystem.config.cjs << EOF
const path = require('path');
const fs = require('fs');

const logsDir = path.join(__dirname, 'logs');
if (!fs.existsSync(logsDir)) {
  fs.mkdirSync(logsDir, { recursive: true });
}

module.exports = {
  apps: [{
    name: 'ovh-monitor',
    script: './monitor.js',
    instances: 1,
    exec_mode: 'fork',
    autorestart: true,
    watch: false,
    max_memory_restart: '300M',
    env: {
      NODE_ENV: 'production',
      DINGTALK_WEBHOOK: '${DINGTALK_WEBHOOK}',
      DINGTALK_SECRET: '${DINGTALK_SECRET}',
      NODE_NO_WARNINGS: '1'
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    min_uptime: '10s',
    max_restarts: 10,
    restart_delay: 4000,
    node_args: '--no-deprecation'
  }]
};
EOF
echo -e "  ${GREEN}✓ ecosystem.config.cjs创建完成${NC}"

# 安装依赖
echo -e "${GREEN}[8/9]${NC} 安装依赖..."
npm install
echo -e "  ${GREEN}✓ 依赖安装完成${NC}"

# 创建README
echo -e "${GREEN}[9/9]${NC} 创建说明文档..."
cat > README.md << 'EOFREADME'
# OVH服务器监控 - 钉钉版

自动监控OVH服务器上新情况，通过钉钉群机器人推送通知。

## 监控型号
- 25sk系列
- 24sk系列  
- 25rise系列

## 常用命令

```bash
# 启动监控
npm run start

# 停止监控
npm run stop

# 重启监控
npm run restart

# 查看日志
npm run logs

# 查看监控状态
npm run monit

# 查看进程列表
npm run status
```

## 修改配置

编辑 `ecosystem.config.cjs` 文件中的环境变量：
- `DINGTALK_WEBHOOK`: 钉钉机器人Webhook地址
- `DINGTALK_SECRET`: 钉钉机器人加签密钥(可选)

修改后重启服务:
```bash
npm run restart
```

## 修改检查间隔

编辑 `monitor.js` 文件中的 `CHECK_INTERVAL` 变量（单位：毫秒）：
```javascript
const CHECK_INTERVAL = 1000 * 60; // 1分钟
```

## 设置开机自启

```bash
pm2 startup
pm2 save
```

## 监控数据

程序会在 `data` 目录下存储：
- `last_data.json`: 上次检查的服务器数据
- `last_check.json`: 上次检查的时间戳

## 日志文件

日志存储在 `logs` 目录：
- `out.log`: 标准输出日志
- `err.log`: 错误日志

## 故障排查

### 查看日志
```bash
npm run logs
```

### 检查进程状态
```bash
pm2 list
```

### 重启服务
```bash
npm run restart
```

### 完全重置
```bash
pm2 delete ovh-monitor
rm -rf data logs
npm run start
```
EOFREADME
echo -e "  ${GREEN}✓ README.md创建完成${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}          🎉 安装完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}项目目录:${NC} $(pwd)"
echo ""
echo -e "${GREEN}现在启动监控服务? (y/n)${NC}"
read -p "> " start_now

if [ "$start_now" == "y" ]; then
    npm run start
    echo ""
    echo -e "${GREEN}✓ 监控服务已启动！${NC}"
    echo ""
    echo -e "${YELLOW}常用命令（可在任何目录运行）:${NC}"
    echo -e "  - 查看实时日志: ${BLUE}pm2 logs ovh-monitor${NC}"
    echo -e "  - 查看进程状态: ${BLUE}pm2 list${NC}"
    echo -e "  - 停止服务: ${BLUE}pm2 stop ovh-monitor${NC}"
    echo -e "  - 重启服务: ${BLUE}pm2 restart ovh-monitor${NC}"
    echo "  - 按 Ctrl+C 退出日志查看（服务会继续运行）"
    echo ""
    sleep 3
    pm2 logs ovh-monitor
else
    echo ""
    echo -e "${YELLOW}稍后手动启动:${NC}"
    echo -e "  ${BLUE}cd $PROJECT_DIR${NC}"
    echo -e "  ${BLUE}pm2 start ecosystem.config.cjs${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}祝使用愉快！有问题随时查看 README.md${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
