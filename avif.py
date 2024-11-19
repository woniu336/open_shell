import os
import subprocess
from concurrent.futures import ProcessPoolExecutor

def process_image(file_path):
    try:
        avif_file_path = os.path.splitext(file_path)[0] + '.avif'
        command = f'magick.exe -quality 80 -depth 8 -define avif:format=ycbcr420 "{file_path}" "{avif_file_path}"'
        result = subprocess.run(command, shell=True, check=True)
        
        # 确保转换成功后再删除原文件
        if result.returncode == 0:
            os.remove(file_path)
            print(f"Processed and deleted: {file_path}")
        else:
            print(f"Conversion failed: {file_path}")
    except subprocess.CalledProcessError as e:
        print(f"Error processing {file_path}: {e}")
    except Exception as e:
        print(f"Unexpected error: {e}")

def main():
    folder_path = r"C:\Users\Administrator\Desktop\11"
    supported_formats = ['.jpg', '.jpeg', '.png', '.bmp', '.gif', '.webp', '.heif', '.heic', '.dng']

    files_to_process = []
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            if any(file.lower().endswith(ext) for ext in supported_formats):
                files_to_process.append(os.path.join(root, file))

    with ProcessPoolExecutor(max_workers=5) as executor:
        for file_path in files_to_process:
            print(f"Starting processing: {file_path}")
            executor.submit(process_image, file_path)

    print("All conversions completed.")

if __name__ == '__main__':
    main()