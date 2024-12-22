#!/usr/bin/env python3
import os
import sys
import time
import logging
import subprocess
import configparser
from datetime import datetime
import tarfile
import shutil

def setup_logging(log_file):
    """配置日志"""
    # 自定义日志格式，简化时间戳
    log_format = '%(asctime)s [%(levelname)s] %(message)s'
    date_format = '%Y-%m-%d %H:%M:%S'
    
    logging.basicConfig(
        level=logging.INFO,
        format=log_format,
        datefmt=date_format,
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler()
        ]
    )

def read_config(config_file='backup_config.conf'):
    """读取配置文件"""
    if not os.path.exists(config_file):
        raise FileNotFoundError(f"配置文件不存在: {config_file}")
    
    config = configparser.ConfigParser()
    config.read(config_file)
    return config

def create_backup_archive(source_dir, backup_dir, exclude_patterns, config):
    """创建增量备份压缩文件，使用更高效的压缩方式"""
    if not os.path.exists(backup_dir):
        os.makedirs(backup_dir)

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    archive_name = f"backup_{timestamp}.tar.gz"
    archive_path = os.path.join(backup_dir, archive_name)

    logging.info(f"开始创建备份压缩文件: {archive_path}")
    
    try:
        # 构建 exclude 参数，正确处理目录和文件模式
        exclude_args = []
        for pattern in exclude_patterns:
            if pattern.startswith('*'):
                # 文件模式（如 *.log）
                exclude_args.extend(['--exclude', pattern])
            else:
                # 目录模式（移除前导斜杠，添加尾部星号）
                dir_pattern = pattern.lstrip('/')  # 移除前导斜杠
                if dir_pattern.endswith('/'):
                    dir_pattern = f"{dir_pattern}*"  # 添加星号匹配目录下所有内容
                exclude_args.extend(['--exclude', dir_pattern])
        
        # 获取配置值并确保它们是整数
        compression_threads = int(config['backup']['compression_threads'])
        nice_value = int(config['backup']['nice_value'])
        
        # 优化的 tar 命令选项，移除 -z 选项
        cmd = ['tar'] + exclude_args + [
            f'--use-compress-program=pigz -p {compression_threads}',
            '--warning=no-file-changed',
            '--ignore-failed-read',
            '-cf',  # 只使用 create file 选项，压缩由 pigz 处理
            archive_path,
            '-C', source_dir,
            '.'
        ]
        
        logging.info("开始创建备份文件...")
        
        # 使用配置的 nice 值
        nice_cmd = ['nice', '-n', str(nice_value)] + cmd
        result = subprocess.run(nice_cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            size = os.path.getsize(archive_path)
            size_str = convert_size(size)
            logging.info(f"备份完成: {os.path.basename(archive_path)} ({size_str})")
            return archive_path
        else:
            raise Exception(f"备份失败: {result.stderr}")
            
    except Exception as e:
        logging.error(f"创建备份压缩文件失败: {str(e)}")
        raise

def convert_size(size_bytes):
    """转换文件大小为人性化格式"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size_bytes < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0

def sync_to_r2(archive_path, config):
    """使用 rclone 同步到 R2"""
    remote_path = f"{config['rclone']['remote_name']}:{config['rclone']['remote_path']}"
    
    rclone_cmd = [
        'rclone', 'copy',
        archive_path,
        remote_path,
        '--progress',
        '--s3-no-check-bucket',
        '--s3-chunk-size', '128M',
        '--s3-upload-concurrency', '20',
        '--no-traverse',
        '--transfers', '1',
        '--buffer-size', '256M',
        '--retries', '3',
        '--use-server-modtime',
        '--stats', '5s',                    # 每5秒显示一次统计
        '--stats-one-line',
        '--stats-one-line-date',           # 在统计中显示日期
        '--stats-unit', 'bits',            # 使用比特单位显示
        '--quiet'                          # 减少冗余输出
    ]

    logging.info(f"开始同步到: {remote_path}")
    
    try:
        process = subprocess.Popen(
            rclone_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            bufsize=1
        )
        
        last_progress = ''
        while True:
            output = process.stdout.readline()
            error = process.stderr.readline()
            
            if output == '' and error == '' and process.poll() is not None:
                break
            
            # 只显示进度变化
            if output:
                output = output.strip()
                if output and output != last_progress and 'Transferred:' in output:
                    # 清理和格式化进度信息
                    progress = output.split('Transferred:')[-1].strip()
                    logging.info(f"传输进度: {progress}")
                    last_progress = output
            
            # 只显示错误信息
            if error and 'ERROR' in error:
                logging.error(error.strip())
        
        rc = process.poll()
        if rc == 0:
            # 获取最终大小和用时
            final_output = process.stdout.read()
            if 'Transferred:' in final_output:
                final_stats = final_output.split('Transferred:')[-1].strip()
                logging.info(f"同步完成: {final_stats}")
            return True
        else:
            error = process.stderr.read()
            if error:
                logging.error(f"同步失败: {error}")
            return False
            
    except Exception as e:
        logging.error(f"同步错误: {str(e)}")
        return False

def cleanup(archive_path):
    """清理本地备份文件"""
    try:
        filename = os.path.basename(archive_path)
        os.remove(archive_path)
        logging.info(f"已删除本地文件: {filename}")
    except Exception as e:
        logging.error(f"删除失败: {str(e)}")

def main():
    try:
        # 读取配置
        config = read_config()
        
        # 设置日志
        setup_logging(config['paths']['log_file'])
        
        # 获取排除目录列表
        exclude_patterns = [d.strip() for d in config['backup']['exclude_dirs'].strip().split('\n') if d.strip()]
        logging.info(f"排除的目录: {exclude_patterns}")

        # 创建备份
        archive_path = create_backup_archive(
            config['paths']['source_dir'],
            config['paths']['backup_dir'],
            exclude_patterns,
            config
        )

        # 同步到 R2
        if sync_to_r2(archive_path, config):
            # 清理本地文件
            cleanup(archive_path)
        else:
            logging.error("由于同步失败，保留本地备份文件")

    except Exception as e:
        logging.error(f"备份过程发生错误: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main() 