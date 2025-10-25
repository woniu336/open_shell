/**
 * 图床后端服务 - 带文件去重和短文件名
 */

const express = require('express');
const multer = require('multer');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 3000;

// 文件名生成策略配置（可根据需要选择）
const FILENAME_STRATEGY = process.env.FILENAME_STRATEGY || 'short'; // 'short', 'base62', 'hash', 'counter'

// 确保上传目录存在
const UPLOAD_DIR = path.join(__dirname, 'uploads');
if (!fs.existsSync(UPLOAD_DIR)) {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

// 文件 hash 映射表
const FILE_HASH_MAP_PATH = path.join(__dirname, 'file-hash-map.json');
let fileHashMap = {};

// 加载已存在的 hash 映射
if (fs.existsSync(FILE_HASH_MAP_PATH)) {
  try {
    fileHashMap = JSON.parse(fs.readFileSync(FILE_HASH_MAP_PATH, 'utf8'));
  } catch (err) {
    console.error('加载 hash 映射失败:', err);
    fileHashMap = {};
  }
}

// 保存 hash 映射
function saveHashMap() {
  fs.writeFileSync(FILE_HASH_MAP_PATH, JSON.stringify(fileHashMap, null, 2));
}

// 计算文件 hash
function calculateFileHash(buffer) {
  return crypto.createHash('md5').update(buffer).digest('hex');
}

// Base62 编码（用于更短的时间戳）
function base62Encode(num) {
  const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  let result = '';
  while (num > 0) {
    result = chars[num % 62] + result;
    num = Math.floor(num / 62);
  }
  return result || '0';
}

// 生成短文件名的不同策略
function generateShortFilename(originalName, strategy = 'short') {
  const ext = path.extname(originalName);
  
  switch (strategy) {
    case 'short':
      // 方案1: 时间戳后6位 + 3位随机 (9位 + 扩展名)
      // 例如: 950414abc.png
      const timestamp = Date.now().toString().slice(-6);
      const random = Math.random().toString(36).substring(2, 5);
      return `${timestamp}${random}${ext}`;
      
    case 'base62':
      // 方案2: Base62编码时间戳 + 2位随机 (约9-10位 + 扩展名)
      // 例如: 2aB9xY1ab.png
      const b62Time = base62Encode(Date.now());
      const b62Random = Math.random().toString(36).substring(2, 4);
      return `${b62Time}${b62Random}${ext}`;
      
    case 'hash':
      // 方案3: 时间戳hash的前8位 (8位 + 扩展名)
      // 例如: a3b9c2d1.png
      const hashShort = crypto.createHash('md5')
        .update(Date.now().toString() + Math.random().toString())
        .digest('hex')
        .substring(0, 8);
      return `${hashShort}${ext}`;
      
    case 'counter':
      // 方案4: 纯时间戳 (13位 + 扩展名)
      // 例如: 1761369950414.png
      return `${Date.now()}${ext}`;
      
    default:
      return generateShortFilename(originalName, 'short');
  }
}

// CORS配置
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'DELETE'],
}));

app.use(express.json());

// 配置文件存储
const storage = multer.memoryStorage();

// 文件过滤器
const fileFilter = (req, file, cb) => {
  const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml'];
  if (allowedTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('只允许上传图片文件 (JPEG, PNG, GIF, WebP, SVG)'), false);
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: {
    fileSize: 10 * 1024 * 1024
  }
});

// 静态文件服务
app.use('/images', express.static(UPLOAD_DIR));

// 上传接口（带去重和短文件名）
app.post('/api/upload', upload.array('images', 10), (req, res) => {
  try {
    if (!req.files || req.files.length === 0) {
      return res.status(400).json({ error: '没有上传文件' });
    }

    const uploadedFiles = [];
    const duplicateFiles = [];

    for (const file of req.files) {
      // 计算文件 hash
      const fileHash = calculateFileHash(file.buffer);
      
      // 检查是否已存在
      if (fileHashMap[fileHash]) {
        const existingFile = fileHashMap[fileHash];
        const existingPath = path.join(UPLOAD_DIR, existingFile);
        
        if (fs.existsSync(existingPath)) {
          console.log(`文件已存在，跳过: ${existingFile}`);
          duplicateFiles.push({
            name: file.originalname,
            url: `/images/${existingFile}`,
            fullUrl: `${req.protocol}://${req.get('host')}/images/${existingFile}`,
            size: file.size,
            mimetype: file.mimetype,
            isDuplicate: true,
            message: '文件已存在，返回已有文件'
          });
          continue;
        } else {
          delete fileHashMap[fileHash];
        }
      }
      
      // 生成短文件名
      const uniqueName = generateShortFilename(file.originalname, FILENAME_STRATEGY);
      const filePath = path.join(UPLOAD_DIR, uniqueName);
      
      // 如果文件名冲突，添加随机后缀
      let finalName = uniqueName;
      let counter = 1;
      while (fs.existsSync(path.join(UPLOAD_DIR, finalName))) {
        const ext = path.extname(uniqueName);
        const base = path.basename(uniqueName, ext);
        finalName = `${base}_${counter}${ext}`;
        counter++;
      }
      
      // 保存文件
      fs.writeFileSync(path.join(UPLOAD_DIR, finalName), file.buffer);
      
      // 更新 hash 映射
      fileHashMap[fileHash] = finalName;
      
      uploadedFiles.push({
        name: file.originalname,
        url: `/images/${finalName}`,
        fullUrl: `${req.protocol}://${req.get('host')}/images/${finalName}`,
        size: file.size,
        mimetype: file.mimetype,
        isDuplicate: false
      });
    }
    
    // 保存 hash 映射
    saveHashMap();

    res.json({
      success: true,
      files: [...uploadedFiles, ...duplicateFiles],
      stats: {
        uploaded: uploadedFiles.length,
        duplicates: duplicateFiles.length,
        total: req.files.length
      }
    });
  } catch (error) {
    console.error('上传错误:', error);
    res.status(500).json({ error: '上传失败' });
  }
});

// 删除图片接口
app.delete('/api/images/:filename', (req, res) => {
  try {
    const filename = req.params.filename;
    const filePath = path.join(UPLOAD_DIR, filename);

    if (fs.existsSync(filePath)) {
      // 从 hash 映射中删除
      for (const [hash, name] of Object.entries(fileHashMap)) {
        if (name === filename) {
          delete fileHashMap[hash];
          break;
        }
      }
      saveHashMap();
      
      fs.unlinkSync(filePath);
      res.json({ success: true, message: '删除成功' });
    } else {
      res.status(404).json({ error: '文件不存在' });
    }
  } catch (error) {
    console.error('删除错误:', error);
    res.status(500).json({ error: '删除失败' });
  }
});

// 获取图片列表接口
app.get('/api/images', (req, res) => {
  try {
    const files = fs.readdirSync(UPLOAD_DIR);
    const imageFiles = files.map(filename => {
      const filePath = path.join(UPLOAD_DIR, filename);
      const stats = fs.statSync(filePath);
      return {
        name: filename,
        url: `/images/${filename}`,
        fullUrl: `${req.protocol}://${req.get('host')}/images/${filename}`,
        size: stats.size,
        uploadTime: stats.mtime
      };
    });

    res.json({
      success: true,
      files: imageFiles,
      totalFiles: imageFiles.length,
      totalHashEntries: Object.keys(fileHashMap).length
    });
  } catch (error) {
    console.error('获取列表错误:', error);
    res.status(500).json({ error: '获取列表失败' });
  }
});

// 清理无效的 hash 映射
app.post('/api/cleanup-hash-map', (req, res) => {
  try {
    const files = fs.readdirSync(UPLOAD_DIR);
    const validHashes = {};
    
    for (const [hash, filename] of Object.entries(fileHashMap)) {
      if (files.includes(filename)) {
        validHashes[hash] = filename;
      }
    }
    
    const removedCount = Object.keys(fileHashMap).length - Object.keys(validHashes).length;
    fileHashMap = validHashes;
    saveHashMap();
    
    res.json({
      success: true,
      message: `清理完成，移除了 ${removedCount} 个无效映射`,
      currentEntries: Object.keys(fileHashMap).length
    });
  } catch (error) {
    console.error('清理错误:', error);
    res.status(500).json({ error: '清理失败' });
  }
});

// 健康检查接口
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    message: '图床服务运行正常',
    filenameStrategy: FILENAME_STRATEGY,
    deduplication: 'enabled',
    hashEntries: Object.keys(fileHashMap).length
  });
});

// 错误处理
app.use((error, req, res, next) => {
  console.error('服务器错误:', error);
  res.status(500).json({ error: error.message || '服务器错误' });
});

app.listen(PORT, () => {
  console.log(`图床服务器运行在端口 ${PORT}`);
  console.log(`上传目录: ${UPLOAD_DIR}`);
  console.log(`文件名策略: ${FILENAME_STRATEGY}`);
  console.log(`文件去重: 已启用`);
  console.log(`Hash 映射: ${Object.keys(fileHashMap).length} 条记录`);
});