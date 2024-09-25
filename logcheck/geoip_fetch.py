import os
import requests
import gzip
import shutil

# 替换为您的 MaxMind 许可密钥
LICENSE_KEY = "xxxxx"

# 下载 URL
DOWNLOAD_URL = f"https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key={LICENSE_KEY}&suffix=tar.gz"

# 本地保存路径
SAVE_PATH = "/root/data/GeoLite2-City.mmdb"

def download_geoip_database():
    response = requests.get(DOWNLOAD_URL)
    if response.status_code == 200:
        with open("GeoLite2-City.tar.gz", "wb") as f:
            f.write(response.content)
        
        # 解压文件
        os.system("tar -xzf GeoLite2-City.tar.gz")
        
        # 移动 .mmdb 文件到指定位置
        extracted_dir = [d for d in os.listdir() if d.startswith("GeoLite2-City_")][0]
        shutil.move(f"{extracted_dir}/GeoLite2-City.mmdb", SAVE_PATH)
        
        # 清理临时文件
        os.remove("GeoLite2-City.tar.gz")
        shutil.rmtree(extracted_dir)
        
        print(f"GeoLite2-City 数据库已下载并保存到 {SAVE_PATH}")
    else:
        print("下载失败，请检查您的许可密钥和网络连接")

if __name__ == "__main__":
    download_geoip_database()