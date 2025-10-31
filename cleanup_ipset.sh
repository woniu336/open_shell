#!/bin/bash
# ==========================================
# 一键清除 ipset/iptables 规则 + systemd + 定时任务 + 修复80/443
# ==========================================
set -e

echo "=========================================="
echo " 🔥 开始清理 IPSet、防火墙规则、恢复80/443访问..."
echo "=========================================="

# ---------- 1. 清理 IPSet ----------
for setname in china china6; do
    if ipset list -n 2>/dev/null | grep -qw "$setname"; then
        echo " - 清理并删除集合:$setname"
        ipset flush "$setname" 2>/dev/null || true
        ipset destroy "$setname" 2>/dev/null || true
    else
        echo " - 集合 $setname 不存在,跳过"
    fi
done

# ---------- 2. 清理 iptables 中的 match-set 规则 ----------
clean_chain_rules() {
    local chain=$1
    local cmd=$2
    echo " - 检查并清理 $cmd 链:$chain 中的 match-set 规则"
    
    # 获取所有包含 match-set 的规则行号(倒序删除)
    $cmd -L "$chain" -n --line-numbers 2>/dev/null | grep "match-set" | awk '{print $1}' | sort -rn | while read num; do
        if [ -n "$num" ]; then
            echo "   删除 match-set 规则编号 $num"
            $cmd -D "$chain" "$num" 2>/dev/null || true
        fi
    done
}

clean_chain_rules "ufw-user-input" "iptables"
clean_chain_rules "ufw6-user-input" "ip6tables"

# ---------- 3. 强制删除所有 80/443 的 DROP 规则 ----------
remove_all_drop_rules() {
    local chain=$1
    local cmd=$2
    
    echo " - 强制清理 $cmd $chain 中所有 80/443 DROP 规则"
    
    # 循环直到没有 DROP 规则为止
    local max_iterations=50
    local iteration=0
    
    while [ $iteration -lt $max_iterations ]; do
        local found=0
        
        # 检查 80 端口
        if $cmd -L "$chain" -n --line-numbers 2>/dev/null | grep -E "DROP.*tcp.*dpt:80" | head -1 | awk '{print $1}' | grep -q "[0-9]"; then
            local line=$($cmd -L "$chain" -n --line-numbers 2>/dev/null | grep -E "DROP.*tcp.*dpt:80" | head -1 | awk '{print $1}')
            echo "   删除 DROP tcp dpt:80 规则 #$line"
            $cmd -D "$chain" "$line" 2>/dev/null || true
            found=1
        fi
        
        # 检查 443 端口
        if $cmd -L "$chain" -n --line-numbers 2>/dev/null | grep -E "DROP.*tcp.*dpt:443" | head -1 | awk '{print $1}' | grep -q "[0-9]"; then
            local line=$($cmd -L "$chain" -n --line-numbers 2>/dev/null | grep -E "DROP.*tcp.*dpt:443" | head -1 | awk '{print $1}')
            echo "   删除 DROP tcp dpt:443 规则 #$line"
            $cmd -D "$chain" "$line" 2>/dev/null || true
            found=1
        fi
        
        # 如果没找到任何规则,退出循环
        if [ $found -eq 0 ]; then
            break
        fi
        
        iteration=$((iteration + 1))
    done
}

remove_all_drop_rules "ufw-user-input" "iptables"
remove_all_drop_rules "ufw6-user-input" "ip6tables"

# ---------- 4. 删除所有现有的 80/443 ACCEPT 规则(避免重复) ----------
remove_accept_rules() {
    local chain=$1
    local cmd=$2
    
    echo " - 清理 $cmd $chain 中现有的 80/443 ACCEPT 规则"
    
    while true; do
        local found=0
        
        if $cmd -L "$chain" -n --line-numbers 2>/dev/null | grep -E "ACCEPT.*tcp.*dpt:(80|443)" | head -1 | awk '{print $1}' | grep -q "[0-9]"; then
            local line=$($cmd -L "$chain" -n --line-numbers 2>/dev/null | grep -E "ACCEPT.*tcp.*dpt:(80|443)" | head -1 | awk '{print $1}')
            echo "   删除旧 ACCEPT 规则 #$line"
            $cmd -D "$chain" "$line" 2>/dev/null || true
            found=1
        else
            break
        fi
    done
}

remove_accept_rules "ufw-user-input" "iptables"
remove_accept_rules "ufw6-user-input" "ip6tables"

# ---------- 5. 重新添加 ACCEPT 规则到链首 ----------
echo " - 在链首添加 ACCEPT 80/443 规则"

iptables -I ufw-user-input 1 -p tcp --dport 80 -j ACCEPT
iptables -I ufw-user-input 1 -p tcp --dport 443 -j ACCEPT
ip6tables -I ufw6-user-input 1 -p tcp --dport 80 -j ACCEPT
ip6tables -I ufw6-user-input 1 -p tcp --dport 443 -j ACCEPT

echo "   ✓ IPv4 ACCEPT 规则已添加"
echo "   ✓ IPv6 ACCEPT 规则已添加"

# ---------- 6. 清理 systemd 服务 ----------
if systemctl list-unit-files 2>/dev/null | grep -q "ipset-restore.service"; then
    echo " - 停止并删除 systemd 服务:ipset-restore.service"
    systemctl stop ipset-restore.service 2>/dev/null || true
    systemctl disable ipset-restore.service 2>/dev/null || true
    rm -f /etc/systemd/system/ipset-restore.service
    systemctl daemon-reload
else
    echo " - 未发现 ipset-restore.service,跳过"
fi

# ---------- 7. 删除保存文件 ----------
if [ -f /etc/iptables/ipset.rules ]; then
    echo " - 删除保存的 ipset 规则文件"
    rm -f /etc/iptables/ipset.rules
fi

# ---------- 8. 清理定时任务 ----------
echo " - 检查并清理相关定时任务..."
if crontab -l 2>/dev/null | grep -q "update_china_ipset.sh"; then
    crontab -l 2>/dev/null | grep -v "update_china_ipset.sh" | crontab - || true
    echo "   已清理定时任务"
else
    echo "   无定时任务需要清理"
fi

# ---------- 9. 保存规则(如果使用 iptables-persistent) ----------
if command -v netfilter-persistent >/dev/null 2>&1; then
    echo " - 保存 iptables 规则..."
    netfilter-persistent save 2>/dev/null || true
elif command -v iptables-save >/dev/null 2>&1; then
    echo " - 保存 iptables 规则..."
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
fi

# ---------- 10. 展示最终结果 ----------
echo ""
echo "=========================================="
echo " ✅ 清理完成!最终状态:"
echo "=========================================="
echo ""
echo "--- IPv4 80/443 规则状态 ---"
iptables -L ufw-user-input -n -v --line-numbers 2>/dev/null | head -20 | grep -E "ACCEPT|DROP" | grep -E "80|443" || echo "✓ 无相关规则"
echo ""
echo "--- IPv6 80/443 规则状态 ---"
ip6tables -L ufw6-user-input -n -v --line-numbers 2>/dev/null | head -20 | grep -E "ACCEPT|DROP" | grep -E "80|443" || echo "✓ 无相关规则"
echo ""
echo "=========================================="
echo " ✅ 所有 DROP 规则已彻底删除"
echo " ✅ ACCEPT 规则已添加到链首"
echo " ✅ 80/443 端口现已完全开放"
echo "=========================================="
echo ""
echo "=========================================="
