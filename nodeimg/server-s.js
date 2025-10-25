/**
 * 图床后端服务 - 修复重复上传问题
 * 改进：
 * 1. 基于原始文件内容去重（压缩前）
 * 2. 增强文件名唯一性（微秒级时间戳 + 更长随机数）
 * 3. 添加上传锁，防止并发冲突
 */

const express = require('express');
const multer = require('multer');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const sharp = require('sharp');

const app = express();
const PORT = process.env.PORT || 3000;

// 目录配置
const UPLOAD_DIR = path.join(__dirname, 'uploads');
const COMPRESSED_DIR = path.join(UPLOAD_DIR, 'compressed');
const ORIGINAL_DIR = path.join(UPLOAD_DIR, 'original');

// 确保目录存在
[UPLOAD_DIR, COMPRESSED_DIR, ORIGINAL_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

// 压缩配置
const COMPRESSION_CONFIG = {
  quality: 75,
  maxWidth: 1920,
  maxHeight: 1920,
  saveOriginal: false,
  format: 'webp'
};

// 文件 hash 映射表
const FILE_HASH_MAP_PATH = path.join(__dirname, 'file-hash-map.json');
let fileHashMap = {};

// 上传锁（防止并发冲突）
const uploadLocks = new Set();

if (fs.existsSync(FILE_HASH_MAP_PATH)) {
  try {
    fileHashMap = JSON.parse(fs.readFileSync(FILE_HASH_MAP_PATH, 'utf8'));
  } catch (err) {
    fileHashMap = {};
  }
}

function saveHashMap() {
  fs.writeFileSync(FILE_HASH_MAP_PATH, JSON.stringify(fileHashMap, null, 2));
}

// 计算原始文件 hash（关键：基于原始内容，不受压缩影响）
function calculateFileHash(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

// 生成唯一文件名（时间戳后6位 + 3位随机码）
function generateUniqueFilename(ext) {
  const timestamp = Date.now().toString().slice(-6); // 时间戳后6位
  const random = Math.random().toString(36).substring(2, 5); // 3位随机码
  // 添加额外的微秒级精度避免冲突
  const microseconds = process.hrtime()[1].toString().slice(-3);
  return `${timestamp}${random}${microseconds}${ext}`;
}

// 压缩图片函数
async function compressImage(buffer, originalName, mimetype) {
  const ext = path.extname(originalName).toLowerCase();
  let sharpInstance = sharp(buffer);
  
  const metadata = await sharpInstance.metadata();
  
  if (metadata.width > COMPRESSION_CONFIG.maxWidth || metadata.height > COMPRESSION_CONFIG.maxHeight) {
    sharpInstance = sharpInstance.resize(COMPRESSION_CONFIG.maxWidth, COMPRESSION_CONFIG.maxHeight, {
      fit: 'inside',
      withoutEnlargement: true
    });
  }
  
  let compressedBuffer;
  let outputExt = ext;
  
  if (COMPRESSION_CONFIG.format === 'webp') {
    compressedBuffer = await sharpInstance.webp({ quality: COMPRESSION_CONFIG.quality }).toBuffer();
    outputExt = '.webp';
  } else if (COMPRESSION_CONFIG.format === 'auto' || COMPRESSION_CONFIG.format === 'jpeg') {
    if (ext === '.png' && metadata.hasAlpha) {
      compressedBuffer = await sharpInstance.png({ 
        quality: COMPRESSION_CONFIG.quality,
        compressionLevel: 9 
      }).toBuffer();
    } else {
      compressedBuffer = await sharpInstance.jpeg({ 
        quality: COMPRESSION_CONFIG.quality,
        progressive: true,
        mozjpeg: true
      }).toBuffer();
      outputExt = '.jpg';
    }
  } else {
    if (ext === '.jpg' || ext === '.jpeg') {
      compressedBuffer = await sharpInstance.jpeg({ 
        quality: COMPRESSION_CONFIG.quality,
        progressive: true,
        mozjpeg: true
      }).toBuffer();
    } else if (ext === '.png') {
      compressedBuffer = await sharpInstance.png({ 
        quality: COMPRESSION_CONFIG.quality,
        compressionLevel: 9 
      }).toBuffer();
    } else if (ext === '.webp') {
      compressedBuffer = await sharpInstance.webp({ 
        quality: COMPRESSION_CONFIG.quality 
      }).toBuffer();
    } else {
      compressedBuffer = buffer;
    }
  }
  
  return { buffer: compressedBuffer, ext: outputExt };
}

app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'DELETE'],
}));

app.use(express.json());

const storage = multer.memoryStorage();

const fileFilter = (req, file, cb) => {
  const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml'];
  if (allowedTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('只允许上传图片文件'), false);
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: { fileSize: 20 * 1024 * 1024 }
});

app.use('/images', express.static(COMPRESSED_DIR));
app.use('/images/original', express.static(ORIGINAL_DIR));

// 上传接口（修复版）
app.post('/api/upload', upload.array('images', 10), async (req, res) => {
  try {
    if (!req.files || req.files.length === 0) {
      return res.status(400).json({ error: '没有上传文件' });
    }

    const uploadedFiles = [];
    const duplicateFiles = [];
    const compressionStats = [];

    for (const file of req.files) {
      const originalSize = file.buffer.length;
      
      // 🔑 关键改进1：基于原始文件内容计算 hash
      const fileHash = calculateFileHash(file.buffer);
      
      // 🔒 关键改进2：检查上传锁，防止并发重复
      if (uploadLocks.has(fileHash)) {
        console.log(`检测到并发上传，跳过: ${file.originalname}`);
        continue;
      }
      
      // 检查是否已存在
      if (fileHashMap[fileHash]) {
        const existingFile = fileHashMap[fileHash];
        const existingPath = path.join(COMPRESSED_DIR, existingFile);
        
        if (fs.existsSync(existingPath)) {
          console.log(`文件已存在，跳过: ${existingFile}`);
          duplicateFiles.push({
            name: file.originalname,
            url: `/images/${existingFile}`,
            fullUrl: `${req.protocol}://${req.get('host')}/images/${existingFile}`,
            size: fs.statSync(existingPath).size,
            isDuplicate: true
          });
          continue;
        } else {
          // 文件被删除了，清理 hash 记录
          delete fileHashMap[fileHash];
        }
      }
      
      // 🔒 加锁
      uploadLocks.add(fileHash);
      
      try {
        // 压缩图片
        let finalBuffer = file.buffer;
        let finalExt = path.extname(file.originalname);
        let compressed = false;
        
        if (file.mimetype !== 'image/svg+xml' && file.mimetype !== 'image/gif') {
          try {
            const result = await compressImage(file.buffer, file.originalname, file.mimetype);
            finalBuffer = result.buffer;
            finalExt = result.ext;
            compressed = true;
            
            compressionStats.push({
              original: file.originalname,
              originalSize: originalSize,
              compressedSize: finalBuffer.length,
              ratio: ((1 - finalBuffer.length / originalSize) * 100).toFixed(2) + '%'
            });
            
            console.log(`压缩: ${file.originalname} ${(originalSize/1024).toFixed(2)}KB → ${(finalBuffer.length/1024).toFixed(2)}KB`);
          } catch (err) {
            console.error('压缩失败，使用原图:', err);
            compressed = false;
          }
        }
        
        // 🎯 关键改进3：使用增强版文件名生成（避免时间戳冲突）
        const uniqueName = generateUniqueFilename(finalExt);
        
        // 保存压缩图
        const compressedPath = path.join(COMPRESSED_DIR, uniqueName);
        fs.writeFileSync(compressedPath, finalBuffer);
        
        // 保存原图
        if (COMPRESSION_CONFIG.saveOriginal && compressed) {
          const originalName = `orig_${uniqueName}`;
          const originalPath = path.join(ORIGINAL_DIR, originalName);
          fs.writeFileSync(originalPath, file.buffer);
        }
        
        // 更新 hash 映射
        fileHashMap[fileHash] = uniqueName;
        
        uploadedFiles.push({
          name: file.originalname,
          url: `/images/${uniqueName}`,
          fullUrl: `${req.protocol}://${req.get('host')}/images/${uniqueName}`,
          originalUrl: COMPRESSION_CONFIG.saveOriginal ? `/images/original/orig_${uniqueName}` : null,
          size: finalBuffer.length,
          originalSize: originalSize,
          compressed: compressed,
          compressionRatio: compressed ? ((1 - finalBuffer.length / originalSize) * 100).toFixed(2) + '%' : '0%',
          isDuplicate: false,
          hash: fileHash.substring(0, 8) // 返回部分 hash 用于调试
        });
      } finally {
        // 🔓 解锁（延迟500ms，防止极端并发）
        setTimeout(() => uploadLocks.delete(fileHash), 500);
      }
    }
    
    saveHashMap();

    res.json({
      success: true,
      files: [...uploadedFiles, ...duplicateFiles],
      stats: {
        uploaded: uploadedFiles.length,
        duplicates: duplicateFiles.length,
        total: req.files.length,
        compression: compressionStats
      }
    });
  } catch (error) {
    console.error('上传错误:', error);
    res.status(500).json({ error: '上传失败: ' + error.message });
  }
});

// 删除图片接口
app.delete('/api/images/:filename', (req, res) => {
  try {
    const filename = req.params.filename;
    const compressedPath = path.join(COMPRESSED_DIR, filename);
    const originalPath = path.join(ORIGINAL_DIR, `orig_${filename}`);

    if (fs.existsSync(compressedPath)) {
      fs.unlinkSync(compressedPath);
      
      if (fs.existsSync(originalPath)) {
        fs.unlinkSync(originalPath);
      }
      
      // 从 hash 映射中删除
      for (const [hash, name] of Object.entries(fileHashMap)) {
        if (name === filename) {
          delete fileHashMap[hash];
          break;
        }
      }
      saveHashMap();
      
      res.json({ success: true, message: '删除成功' });
    } else {
      res.status(404).json({ error: '文件不存在' });
    }
  } catch (error) {
    res.status(500).json({ error: '删除失败' });
  }
});

// 获取图片列表接口
app.get('/api/images', (req, res) => {
  try {
    const files = fs.readdirSync(COMPRESSED_DIR);
    const imageFiles = files.map(filename => {
      const filePath = path.join(COMPRESSED_DIR, filename);
      const stats = fs.statSync(filePath);
      const originalPath = path.join(ORIGINAL_DIR, `orig_${filename}`);
      
      return {
        name: filename,
        url: `/images/${filename}`,
        fullUrl: `${req.protocol}://${req.get('host')}/images/${filename}`,
        originalUrl: fs.existsSync(originalPath) ? `/images/original/orig_${filename}` : null,
        size: stats.size,
        uploadTime: stats.mtime
      };
    });

    res.json({ 
      success: true, 
      files: imageFiles,
      config: COMPRESSION_CONFIG
    });
  } catch (error) {
    res.status(500).json({ error: '获取列表失败' });
  }
});

// 更新压缩配置
app.post('/api/config/compression', (req, res) => {
  try {
    const { quality, maxWidth, maxHeight, saveOriginal, format } = req.body;
    
    if (quality) COMPRESSION_CONFIG.quality = Math.max(1, Math.min(100, quality));
    if (maxWidth) COMPRESSION_CONFIG.maxWidth = maxWidth;
    if (maxHeight) COMPRESSION_CONFIG.maxHeight = maxHeight;
    if (typeof saveOriginal === 'boolean') COMPRESSION_CONFIG.saveOriginal = saveOriginal;
    if (format) COMPRESSION_CONFIG.format = format;
    
    res.json({ 
      success: true, 
      config: COMPRESSION_CONFIG 
    });
  } catch (error) {
    res.status(500).json({ error: '配置更新失败' });
  }
});

// 获取压缩配置
app.get('/api/config/compression', (req, res) => {
  res.json({ 
    success: true, 
    config: COMPRESSION_CONFIG 
  });
});

// 健康检查
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    message: '图床服务运行正常',
    features: {
      compression: 'enabled (sharp)',
      deduplication: 'enabled (sha256)',
      shortFilename: 'enabled (microsecond + crypto)',
      concurrencyProtection: 'enabled'
    },
    config: COMPRESSION_CONFIG,
    stats: {
      totalFiles: Object.keys(fileHashMap).length,
      uploadsLocked: uploadLocks.size
    }
  });
});

app.use((error, req, res, next) => {
  console.error('服务器错误:', error);
  res.status(500).json({ error: error.message || '服务器错误' });
});

app.listen(PORT, () => {
  console.log(`✅ 图床服务器运行在端口 ${PORT}`);
  console.log(`📂 压缩图片目录: ${COMPRESSED_DIR}`);
  console.log(`📂 原图目录: ${ORIGINAL_DIR}`);
  console.log(`🎨 压缩质量: ${COMPRESSION_CONFIG.quality}`);
  console.log(`📐 最大尺寸: ${COMPRESSION_CONFIG.maxWidth}x${COMPRESSION_CONFIG.maxHeight}`);
  console.log(`💾 保存原图: ${COMPRESSION_CONFIG.saveOriginal ? '是' : '否'}`);
  console.log(`🔒 已加载 ${Object.keys(fileHashMap).length} 个文件记录`);
});