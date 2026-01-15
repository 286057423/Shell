#!/bin/bash
# ================ SysCheck 2.0 服务器运维巡检脚本 ================
# 更新日志：SysCheck 2.0 - 修复 Rocky Linux/CentOS 7 执行报错，适配字段格式
# ===============================================================

# --- 基础配置 ---
# 自动检测终端颜色
if [ -t 1 ]; then
    RED="\033[91m"
    GREEN="\033[92m"
    YELLOW="\033[93m"
    BLUE="\033[94m"
    BOLD="\033[1m"
    NC="\033[0m"
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; NC=""
fi

print_title() {
    echo -e "\n${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                  $1${NC}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
}

print_status() {
    case "$1" in
        ok) echo -e "${GREEN} [OK] $2${NC}" ;;
        warn) echo -e "${YELLOW} [WARN] $2${NC}" ;;
        error) echo -e "${RED} [ERROR] $2${NC}" ;;
        info) echo -e "${BLUE} [INFO] $2${NC}" ;;
    esac
}

# --- 1. 系统基础信息 ---
clear
print_title "Linux 服务器深度巡检 (SysCheck 2.0)"
echo -e "巡检时间：$(date '+%Y-%m-%d %H:%M:%S')"

[ -f /etc/os-release ] && . /etc/os-release
print_status info "系统版本 : ${PRETTY_NAME:-未知}"
print_status info "主机名称 : $(hostname)"
print_status info "内核版本 : $(uname -r)"
print_status info "平均负载 : $(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')"

# --- 2. 资源使用情况 ---
print_title "资源使用情况"

# 内存
mem_total=$(free -h | awk '/Mem/{print $2}')
mem_used=$(free -h | awk '/Mem/{print $3}')
mem_free=$(free -h | awk '/Mem/{print $4}')
print_status info "内存总量: $mem_total | 已用: $mem_used | 剩余: $mem_free"

# 磁盘 (排除 tmpfs, cdrom, loop, overlay)
# 修复：适配CentOS 7 df -hT输出格式，用awk固定提取使用率和挂载点，避免字段错位
df -hT | grep -vE 'tmpfs|cdrom|loop|overlay|Filesystem' | awk '{print $1, $2, $3, $4, $5, $6, $7}' | while read fs type size used avail use mount; do
    # 过滤空值，确保use变量有效
    if [ -z "$use" ] || [ "$use" = "Use%" ]; then
        continue
    fi
    # 提取纯数字使用率
    usage_num=$(echo "$use" | tr -d '%' | grep -E '^[0-9]+$')
    # 容错：如果提取失败，默认0
    if [ -z "$usage_num" ]; then
        usage_num=0
    fi
    # 判断磁盘使用率
    if [ "$usage_num" -ge 90 ]; then
        print_status error "磁盘告警: $mount ($use) - 空间严重不足！"
    elif [ "$usage_num" -ge 80 ]; then
        print_status warn "磁盘预警: $mount ($use) - 空间较少"
    else
        print_status ok "磁盘正常: $mount ($use)"
    fi
done

# --- 3. 安全补丁检查 (修复增强版) ---
print_title "安全补丁与漏洞检查"

if command -v apt >/dev/null 2>&1; then
    # Debian/Ubuntu 逻辑
    if updates=$(apt list --upgradable 2>/dev/null | grep -v "Listing..."); then
        cnt=$(echo "$updates" | wc -l)
        if [ "$cnt" -gt 0 ]; then
            print_status warn "发现 $cnt 个可升级包"
        else
            print_status ok "系统软件包已是最新"
        fi
    fi
elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    # RHEL/CentOS/Rocky 逻辑 (适配CentOS 7输出)
    PKG_MGR=$(command -v dnf || command -v yum)
    
    # 核心修复：过滤yum输出的无关日志，只保留安全补丁行
    sec_info=$($PKG_MGR updateinfo list security 2>/dev/null | grep -E '^[0-9]+:' | grep -i security)
    # 计算安全补丁数量（纯数字）
    sec_count=$(echo "$sec_info" | wc -l | tr -d ' ')
    # 容错：确保sec_count是数字
    if ! [[ "$sec_count" =~ ^[0-9]+$ ]]; then
        sec_count=0
    fi
    
    if [ "$sec_count" -gt 0 ]; then
        print_status warn "发现 $sec_count 个安全补丁待安装！"
        echo "$sec_info" | head -n 5
    else
        print_status ok "未发现严重安全补丁"
    fi
else
    print_status info "未知包管理器，跳过补丁检查"
fi

# --- 4. 异常检测 ---
print_title "异常进程检测 (Top 3)"

# 高负载进程
echo -e "${BOLD}CPU 占用前三:${NC}"
ps -eo pid,user,%cpu,cmd --sort=-%cpu | head -n 4 | tail -n 3 | awk '{printf "  %-6s %-10s %-6s %s\n", $1, $2, $3, $4}'

echo -e "\n${BOLD}内存 占用前三:${NC}"
ps -eo pid,user,%mem,cmd --sort=-%mem | head -n 4 | tail -n 3 | awk '{printf "  %-6s %-10s %-6s %s\n", $1, $2, $3, $4}'

# 僵尸进程
zombies=$(ps -A -o stat,ppid,pid,cmd | grep -e '^[Zz]' | wc -l | tr -d ' ')
if ! [[ "$zombies" =~ ^[0-9]+$ ]]; then
    zombies=0
fi
if [ "$zombies" -gt 0 ]; then
    print_status error "发现 $zombies 个僵尸进程！"
else
    print_status ok "无僵尸进程"
fi

# --- 5. 结束 ---
print_title "巡检完成"
echo -e "建议：定期清理 /var/log，关注磁盘使用率。\n"

echo -e "出现[WARN] 发现 1 个安全补丁待安装！为不知名BUG，没搞懂"

