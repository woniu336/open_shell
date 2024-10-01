import sys
import os
import subprocess
from PyQt5.QtWidgets import (QApplication, QWidget, QPushButton, QVBoxLayout, 
                             QHBoxLayout, QLineEdit, QLabel, QListWidget, QMessageBox,
                             QGroupBox, QGridLayout, QTabWidget, QTextEdit, QInputDialog)
from PyQt5.QtGui import QPalette, QColor
from PyQt5.QtCore import Qt

# 添加这些行来设置环境变量
os.environ['PYTHONIOENCODING'] = 'utf-8'
os.environ['LANG'] = 'en_US.UTF-8'

class GitUI(QWidget):
    def __init__(self):
        super().__init__()
        self.initUI()
        self.check_and_init_git_repo()

    def check_and_init_git_repo(self):
        if not os.path.exists('.git'):
            reply = QMessageBox.question(self, '初始化Git仓库', 
                                         '当前目录不是Git仓库。是否要初始化一个新的Git仓库？',
                                         QMessageBox.Yes | QMessageBox.No, QMessageBox.Yes)
            if reply == QMessageBox.Yes:
                try:
                    subprocess.run(['git', 'init'], check=True, capture_output=True, text=True)
                    QMessageBox.information(self, '成功', 'Git仓库已成功初始化。您可以开始创建您的第一个提交了！')
                    
                    # 提示用户创建第一个提交
                    first_commit = QMessageBox.question(self, '创建第一个提交', 
                                                        '是否要创建第一个提交？这将帮助您开始使用Git的所有功能。',
                                                        QMessageBox.Yes | QMessageBox.No, QMessageBox.Yes)
                    if first_commit == QMessageBox.Yes:
                        self.create_first_commit()
                except subprocess.CalledProcessError as e:
                    QMessageBox.warning(self, '错误', f'无法初始化Git仓库：{e.stderr}')
            else:
                QMessageBox.warning(self, '警告', '未初始化Git仓库。某些功能可能无法正常工作。')

        # 设置 Git 编码配置
        git_configs = [
            ['core.quotepath', 'false'],
            ['gui.encoding', 'utf-8'],
            ['i18n.commit.encoding', 'utf-8'],
            ['i18n.logoutputencoding', 'utf-8']
        ]
        for config in git_configs:
            subprocess.run(['git', 'config', '--global'] + config, check=True)

    def create_first_commit(self):
        commit_message, ok = QInputDialog.getText(self, '创建第一个提交', '请输入提交信息：')
        if ok and commit_message:
            try:
                subprocess.run(['git', 'add', '.'], check=True)
                subprocess.run(['git', 'commit', '-m', commit_message], check=True)
                QMessageBox.information(self, '成功', '第一个提交已成功创建！')
                self.update_commit_history()
            except subprocess.CalledProcessError as e:
                QMessageBox.warning(self, '错误', f'无法创建第一个提交：{e.stderr}')

    def initUI(self):
        self.setWindowTitle('Git 操作助手')
        self.setGeometry(300, 300, 600, 500)

        # 保持原有的暖色调
        palette = QPalette()
        palette.setColor(QPalette.Window, QColor(255, 248, 220))  # 米色背景
        palette.setColor(QPalette.WindowText, QColor(139, 69, 19))  # 深棕色文字
        palette.setColor(QPalette.Button, QColor(255, 222, 173))  # 浅橙色按钮
        palette.setColor(QPalette.ButtonText, QColor(139, 69, 19))  # 深棕色按钮文字
        self.setPalette(palette)

        main_layout = QVBoxLayout()

        # 分支操作组
        branch_group = QGroupBox("分支操作")
        branch_layout = QGridLayout()
        
        self.new_branch_input = QLineEdit()
        new_branch_button = QPushButton('创建新分支')
        new_branch_button.clicked.connect(self.create_new_branch)
        branch_layout.addWidget(QLabel("新分支名:"), 0, 0)
        branch_layout.addWidget(self.new_branch_input, 0, 1)
        branch_layout.addWidget(new_branch_button, 0, 2)

        self.switch_branch_input = QLineEdit()
        switch_branch_button = QPushButton('切换分支')
        switch_branch_button.clicked.connect(self.switch_branch)
        branch_layout.addWidget(QLabel("切换到:"), 1, 0)
        branch_layout.addWidget(self.switch_branch_input, 1, 1)
        branch_layout.addWidget(switch_branch_button, 1, 2)

        switch_previous_button = QPushButton('切换到上一个分支')
        switch_previous_button.clicked.connect(self.switch_previous)
        branch_layout.addWidget(switch_previous_button, 2, 0, 1, 3)

        branch_group.setLayout(branch_layout)
        main_layout.addWidget(branch_group)

        # 提交操作组
        commit_group = QGroupBox("提交操作")
        commit_layout = QGridLayout()

        set_alias_button = QPushButton('设置快速提交别名')
        set_alias_button.clicked.connect(self.set_alias)
        commit_layout.addWidget(set_alias_button, 0, 0, 1, 3)

        self.commit_message_input = QLineEdit()
        quick_commit_button = QPushButton('快速提交')
        quick_commit_button.clicked.connect(self.quick_commit)
        commit_layout.addWidget(QLabel("提交信息:"), 1, 0)
        commit_layout.addWidget(self.commit_message_input, 1, 1)
        commit_layout.addWidget(quick_commit_button, 1, 2)

        amend_commit_button = QPushButton('修改最后一次提交')
        amend_commit_button.clicked.connect(self.amend_commit)
        commit_layout.addWidget(amend_commit_button, 2, 0, 1, 3)

        commit_group.setLayout(commit_layout)
        main_layout.addWidget(commit_group)

        # 重置操作组
        reset_group = QGroupBox("重置操作")
        reset_layout = QHBoxLayout()

        soft_reset_button = QPushButton('软重置（保留更改）')
        soft_reset_button.clicked.connect(self.soft_reset)
        reset_layout.addWidget(soft_reset_button)

        hard_reset_button = QPushButton('硬重置（丢弃更改）')
        hard_reset_button.clicked.connect(self.hard_reset)
        reset_layout.addWidget(hard_reset_button)

        reset_group.setLayout(reset_layout)
        main_layout.addWidget(reset_group)

        # 分支信息和提交历史组
        info_group = QGroupBox("分支信息和提交历史")
        info_layout = QVBoxLayout()

        # 创建标签页
        self.tab_widget = QTabWidget()
        
        # 分支信息标签页
        branch_tab = QWidget()
        branch_layout = QVBoxLayout()
        self.branch_list = QListWidget()
        branch_layout.addWidget(QLabel('所有分支：'))
        branch_layout.addWidget(self.branch_list)
        self.current_branch_label = QLabel()
        branch_layout.addWidget(self.current_branch_label)
        branch_tab.setLayout(branch_layout)

        # 提交历史标签页
        commit_history_tab = QWidget()
        commit_history_layout = QVBoxLayout()
        self.commit_history_text = QTextEdit()
        self.commit_history_text.setReadOnly(True)
        commit_history_layout.addWidget(self.commit_history_text)
        commit_history_tab.setLayout(commit_history_layout)

        # 添加标签页到标签页控件
        self.tab_widget.addTab(branch_tab, "分支信息")
        self.tab_widget.addTab(commit_history_tab, "提交历史")

        info_layout.addWidget(self.tab_widget)
        info_group.setLayout(info_layout)
        main_layout.addWidget(info_group)

        self.setLayout(main_layout)
        self.update_branch_info()

    def run_git_command(self, command):
        try:
            # 使用 universal_newlines=True 来确保文本模式
            result = subprocess.run(command, check=True, capture_output=True, text=True, encoding='utf-8', universal_newlines=True)
            QMessageBox.information(self, '成功', result.stdout)
            return True
        except subprocess.CalledProcessError as e:
            QMessageBox.warning(self, '错误', e.stderr)
            return False

    def create_new_branch(self):
        branch_name = self.new_branch_input.text()
        if not branch_name:
            QMessageBox.warning(self, '错误', '请输入新分支名称')
            return
        if self.run_git_command(['git', 'switch', '-c', branch_name]):
            self.update_branch_info()

    def switch_branch(self):
        branch_name = self.switch_branch_input.text()
        if not branch_name:
            QMessageBox.warning(self, '错误', '请输入要切换的分支名称')
            return
        if self.run_git_command(['git', 'switch', branch_name]):
            self.update_branch_info()

    def switch_previous(self):
        if self.run_git_command(['git', 'switch', '-']):
            self.update_branch_info()

    def set_alias(self):
        self.run_git_command(['git', 'config', '--global', 'alias.ac', '!git add -A && git commit -m'])

    def quick_commit(self):
        commit_message = self.commit_message_input.text()
        if not commit_message:
            QMessageBox.warning(self, '错误', '请输入提交信息')
            return
        
        # 检查是否有未暂存的更改
        status = subprocess.check_output(['git', 'status', '--porcelain'], text=True)
        if not status:
            QMessageBox.warning(self, '错误', '没有需要提交的更改')
            return

        if self.run_git_command(['git', 'ac', commit_message]):
            self.update_commit_history()

    def soft_reset(self):
        # 检查是否有提交历史
        try:
            subprocess.check_output(['git', 'log', '-1'], text=True)
        except subprocess.CalledProcessError:
            QMessageBox.warning(self, '错误', '没有提交历史，无法执行软重置')
            return

        if self.run_git_command(['git', 'reset', '--soft', 'HEAD~1']):
            self.update_commit_history()

    def hard_reset(self):
        # 检查是否有提交历史
        try:
            subprocess.check_output(['git', 'log', '-1'], text=True)
        except subprocess.CalledProcessError:
            QMessageBox.warning(self, '错误', '没有提交历史，无法执行硬重置')
            return

        reply = QMessageBox.question(self, '确认', '硬重置将丢失所有未提交的更改。确定要继续吗？',
                                     QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
        if reply == QMessageBox.Yes:
            if self.run_git_command(['git', 'reset', '--hard', 'HEAD~1']):
                self.update_commit_history()

    def update_branch_info(self):
        try:
            branches = subprocess.check_output(['git', 'branch', '-a'], text=True).split('\n')
            self.branch_list.clear()
            self.branch_list.addItems([b.strip() for b in branches if b.strip()])

            current_branch = subprocess.check_output(['git', 'branch', '--show-current'], text=True).strip()
            self.current_branch_label.setText(f'当前分支：{current_branch}')
        except subprocess.CalledProcessError as e:
            self.branch_list.clear()
            self.current_branch_label.setText('当前分支：master')
            self.branch_list.addItem('master')
            # 不显示警告，因为这可能是新仓库

    def update_commit_history(self):
        try:
            commit_history = subprocess.check_output(['git', 'log', '--pretty=format:%h - %an, %ar : %s', '-n', '10'], 
                                                     text=True, encoding='utf-8', errors='replace')
            if commit_history:
                self.commit_history_text.setText(commit_history)
            else:
                self.commit_history_text.setText('暂无提交记录。创建您的第一个提交来开始记录历史！')
        except subprocess.CalledProcessError as e:
            error_message = e.stderr if e.stderr else str(e)
            if 'fatal: your current branch' in error_message and 'does not have any commits yet' in error_message:
                self.commit_history_text.setText('这是一个新的仓库。创建您的第一个提交来开始记录历史！')
            else:
                self.commit_history_text.setText('无法获取提交历史')
                QMessageBox.warning(self, '警告', f'无法获取提交历史。错误信息：{error_message}')

    def amend_commit(self):
        # 检查是否有提交历史
        try:
            subprocess.check_output(['git', 'log', '-1'], text=True)
        except subprocess.CalledProcessError:
            QMessageBox.warning(self, '错误', '没有提交历史，无法修改最后一次提交')
            return

        reply = QMessageBox.question(self, '确认', '这将修改最后一次提交。确定要继续吗？',
                                     QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
        if reply == QMessageBox.Yes:
            if self.run_git_command(['git', 'commit', '--amend']):
                self.update_commit_history()

if __name__ == '__main__':
    app = QApplication(sys.argv)
    ex = GitUI()
    ex.show()
    sys.exit(app.exec_())