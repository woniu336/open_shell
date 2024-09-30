import json

# 读取现有的JSON配置文件
def read_json_config(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        return json.load(f)

# 写入更新后的JSON配置文件
def write_json_config(file_path, data):
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

# 从txt文件读取影片信息
def read_movie_info(file_path):
    encodings = ['utf-8', 'gbk', 'gb18030']
    movie_info = []
    
    for encoding in encodings:
        try:
            with open(file_path, 'r', encoding=encoding) as f:
                for line in f:
                    parts = line.strip().split('=')
                    if len(parts) >= 3:
                        info = {
                            'taskname': parts[0],
                            'shareurl': parts[1],
                            'savepath': parts[2],
                            'update_subdir': parts[3] if len(parts) > 3 else None
                        }
                        movie_info.append(info)
            return movie_info  # 如果成功读取，直接返回结果
        except UnicodeDecodeError:
            continue  # 如果当前编码失败，尝试下一个编码
    
    raise ValueError("无法使用支持的编码读取文件。请检查/root/quark/movie_list.txt 文件是否有乱码")

# 更新JSON配置文件
def update_json_config(config, new_movies):
    for movie in new_movies:
        task = {
            'taskname': movie['taskname'],
            'shareurl': movie['shareurl'],
            'savepath': movie['savepath'],
            'pattern': '',
            'replace': '',
            'enddate': '',
            'emby_id': '',
            'ignore_extension': False,
            'runweek': [1, 2, 3, 4, 5, 6, 7]
        }
        if movie['update_subdir']:
            task['update_subdir'] = movie['update_subdir']
        
        # 检查是否已存在相同的taskname
        existing_task = next((t for t in config['tasklist'] if t['taskname'] == movie['taskname']), None)
        if existing_task:
            # 更新现有任务
            existing_task.update(task)
        else:
            # 添加新任务
            config['tasklist'].append(task)

# 主函数
def main():
    json_file_path = '/root/quark/quark_config.json'
    txt_file_path = '/root/quark/movie_list.txt'

    try:
        # 读取现有的JSON配置
        config = read_json_config(json_file_path)

        # 读取txt文件中的影片信息
        new_movies = read_movie_info(txt_file_path)

        # 更新JSON配置
        update_json_config(config, new_movies)

        # 写入更新后的JSON配置
        write_json_config(json_file_path, config)

        print("配置文件已成功更新。")
    except Exception as e:
        print(f"发生错误：{str(e)}")

if __name__ == "__main__":
    main()