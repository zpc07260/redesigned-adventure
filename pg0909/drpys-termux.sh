#!/data/data/com.termux/files/usr/bin/bash

# drpy-node ZeroTermux 安装脚本
# 适用于 Android 设备的 Termux 环境

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 参数处理
USE_PROXY=false
PROXY_HOST="127.0.0.1:7890"
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --use-proxy)
            USE_PROXY=true
            shift
            ;;
        --proxy-host)
            PROXY_HOST="$2"
            shift 2
            ;;
        --skip-confirm)
            SKIP_CONFIRM=true
            shift
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# -------------------------------------------------
# 0. 工具函数
# -------------------------------------------------
use_proxy_if_needed() {
    if [ "$USE_PROXY" = true ]; then
        local old_http="$HTTP_PROXY"
        local old_https="$HTTPS_PROXY"
        export HTTP_PROXY="http://$PROXY_HOST"
        export HTTPS_PROXY="http://$PROXY_HOST"
        "$@"
        local result=$?
        if [ -n "$old_http" ]; then
            export HTTP_PROXY="$old_http"
        else
            unset HTTP_PROXY
        fi
        if [ -n "$old_https" ]; then
            export HTTPS_PROXY="$old_https"
        else
            unset HTTPS_PROXY
        fi
        return $result
    else
        "$@"
    fi
}

test_cmd() {
    command -v "$1" >/dev/null 2>&1
}

curl_with_proxy() {
    if [ "$USE_PROXY" = true ]; then
        curl -x "http://$PROXY_HOST" "$@"
    else
        curl "$@"
    fi
}

git_with_proxy() {
    if [ "$USE_PROXY" = true ]; then
        git -c http.proxy="http://$PROXY_HOST" "$@"
    else
        git "$@"
    fi
}

# -------------------------------------------------
# 1. 基础环境检查
# -------------------------------------------------
echo -e "${CYAN}检查 Termux 环境...${NC}"

# 检查是否在 Termux 中运行
if [ ! -d "/data/data/com.termux/files/usr" ]; then
    echo -e "${RED}错误：请在 ZeroTermux 或 Termux 中运行此脚本${NC}"
    exit 1
fi

# 请求存储权限
if [ ! -w "/storage/emulated/0" ]; then
    echo -e "${YELLOW}请确保 Termux 有存储权限，运行：termux-setup-storage${NC}"
    termux-setup-storage
    sleep 2
fi

# -------------------------------------------------
# 2. 用户确认
# -------------------------------------------------
if [ "$SKIP_CONFIRM" = false ]; then
    echo -e "${YELLOW}"
    echo "警告：此脚本仅适用于 Android 上的 ZeroTermux/Termux"
    echo "需要稳定的网络连接"
    echo "如果下载失败可指定代理："
    echo "./drpys-termux.sh --use-proxy --proxy-host 192.168.1.21:7890"
    echo -e "${NC}"
    
    read -p "您是否理解并同意继续？(y/n) 默认(y): " confirm
    confirm=${confirm:-y}
    if [ "$confirm" = "n" ]; then
        exit 1
    fi
fi

# -------------------------------------------------
# 3. 更新包管理器并安装基础依赖
# -------------------------------------------------
echo -e "${GREEN}更新包管理器并安装基础依赖...${NC}"

pkg update -y
pkg install -y git nodejs python python-pip wget curl

# 安装 yarn 和 pm2
if ! test_cmd yarn; then
    npm install -g yarn
fi

if ! test_cmd pm2; then
    npm install -g pm2
fi

# -------------------------------------------------
# 4. 克隆项目
# -------------------------------------------------
echo -e "${GREEN}克隆项目...${NC}"

read -p "请输入项目存放目录（留空则使用 ~/drpy-node）: " repo_dir
repo_dir=${repo_dir:-"$HOME/drpy-node"}
project_path="$repo_dir"

remote_repo="https://git-proxy.playdreamer.cn/hjdhnx/drpy-node.git"

# 记录路径
path_file="$PWD/drpys-path.txt"
echo "$project_path" > "$path_file"

use_proxy_if_needed git_with_proxy clone "$remote_repo" "$project_path"

cd "$project_path"

# -------------------------------------------------
# 5. 配置环境
# -------------------------------------------------
echo -e "${GREEN}配置环境...${NC}"

# 创建配置目录
config_dir="$project_path/config"
config_json="$config_dir/env.json"

mkdir -p "$config_dir"

# 生成 env.json
if [ ! -f "$config_json" ]; then
    cat > "$config_json" << EOF
{
    "ali_token": "",
    "ali_refresh_token": "",
    "quark_cookie": "",
    "uc_cookie": "",
    "bili_cookie": "",
    "thread": "10",
    "enable_dr2": "1",
    "enable_py": "2"
}
EOF
fi

# 生成 .env
env_file="$project_path/.env"
env_template="$project_path/.env.development"

if [ ! -f "$env_template" ]; then
    cat > "$env_template" << EOF
NODE_ENV=development
COOKIE_AUTH_CODE=drpys
API_AUTH_NAME=admin
API_AUTH_CODE=drpys
API_PWD=dzyyds
EOF
fi

if [ ! -f "$env_file" ]; then
    cp "$env_template" "$env_file"
    
    echo -e "${CYAN}配置环境变量：${NC}"
    read -p "网盘入库密码（默认 drpys）: " cookie_auth
    cookie_auth=${cookie_auth:-"drpys"}
    
    read -p "登录用户名（默认 admin）: " api_user
    api_user=${api_user:-"admin"}
    
    read -p "登录密码（默认 drpys）: " api_pass
    api_pass=${api_pass:-"drpys"}
    
    read -p "订阅PWD值（默认 dzyyds）: " api_pwd
    api_pwd=${api_pwd:-"dzyyds"}
    
    # 更新环境变量
    sed -i "s/COOKIE_AUTH_CODE=.*/COOKIE_AUTH_CODE=$cookie_auth/" "$env_file"
    sed -i "s/API_AUTH_NAME=.*/API_AUTH_NAME=$api_user/" "$env_file"
    sed -i "s/API_AUTH_CODE=.*/API_AUTH_CODE=$api_pass/" "$env_file"
    sed -i "s/API_PWD=.*/API_PWD=$api_pwd/" "$env_file"
fi

# -------------------------------------------------
# 6. 安装 Node.js 依赖
# -------------------------------------------------
echo -e "${GREEN}安装 Node.js 依赖...${NC}"

invoke_yarn_with_retry() {
    local max_retry=3
    local mirrors=(
        'https://registry.npmmirror.com/'
        'https://registry.yarnpkg.com'
        'https://registry.npmjs.org'
    )
    
    for ((attempt=1; attempt<=max_retry; attempt++)); do
        local mirror="${mirrors[attempt-1]}"
        echo -e "${CYAN}尝试使用镜像 $mirror 安装 Node 依赖（第 $attempt/$max_retry 次）...${NC}"
        
        yarn config set registry "$mirror"
        if yarn --frozen-lockfile; then
            return 0
        fi
    done
    
    echo -e "${RED}[ERROR] 所有镜像均失败，请手动执行 yarn${NC}"
    return 1
}

if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}首次安装 Node 依赖...${NC}"
    invoke_yarn_with_retry
else
    # 检查 yarn.lock 是否有变动
    if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "yarn.lock"; then
        echo -e "${YELLOW}检测到 yarn.lock 变动，更新 Node 依赖...${NC}"
        invoke_yarn_with_retry
    fi
fi

# -------------------------------------------------
# 7. 安装 Python 依赖
# -------------------------------------------------
echo -e "${GREEN}安装 Python 依赖...${NC}"

# 创建虚拟环境
if [ ! -d ".venv" ]; then
    echo -e "${YELLOW}创建 Python 虚拟环境...${NC}"
    python -m venv .venv
fi

# 激活虚拟环境
source ".venv/bin/activate"

pip install --upgrade pip -q

invoke_pip_with_retry() {
    local req_file="$1"
    local max_retry=3
    local mirrors=(
        'https://mirrors.cloud.tencent.com/pypi/simple'
        'https://pypi.tuna.tsinghua.edu.cn/simple'
        'https://pypi.org/simple'
    )
    
    for ((attempt=1; attempt<=max_retry; attempt++)); do
        local mirror="${mirrors[attempt-1]}"
        echo -e "${CYAN}尝试使用镜像 $mirror 安装 Python 依赖（第 $attempt/$max_retry 次）...${NC}"
        
        if pip install -r "$req_file" -i "$mirror" --no-warn-script-location -q; then
            echo -e "${GREEN}pip install 完成${NC}"
            return 0
        fi
    done
    
    echo -e "${RED}[ERROR] 所有镜像均失败，请手动执行 pip install${NC}"
    return 1
}

invoke_pip_with_retry "spider/py/base/requirements.txt"

# 检查 requirements.txt 是否有变动
if git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "spider/py/base/requirements.txt"; then
    echo -e "${YELLOW}检测到 requirements.txt 变动，更新 Python 依赖...${NC}"
    invoke_pip_with_retry "spider/py/base/requirements.txt"
fi

# -------------------------------------------------
# 8. 启动 PM2
# -------------------------------------------------
echo -e "${GREEN}配置 PM2...${NC}"

# 初始化 PM2
pm2 startup | tail -n 1 | bash

if ! pm2 list | grep -q "drpyS"; then
    echo -e "${YELLOW}首次启动 PM2 进程...${NC}"
    pm2 start index.js --name drpyS --update-env
    pm2 save
else
    echo -e "${GREEN}PM2 进程 drpyS 已在运行${NC}"
fi

# -------------------------------------------------
# 9. 配置定时任务（使用 crontab）
# -------------------------------------------------
echo -e "${GREEN}配置定时任务...${NC}"

conf_file="$PWD/drpys-update.conf"
path_file="$PWD/drpys-path.txt"

# 配置向导
if [ ! -f "$conf_file" ]; then
    echo -e "${CYAN}【定时更新配置向导】${NC}"
    
    read -p "是否启用检查更新？(y/n, 默认 y): " check_update
    check_update=${check_update:-"y"}
    
    read -p "是否自动同步源码？(y/n, 默认 y): " sync_code
    sync_code=${sync_code:-"y"}
    
    echo "代理策略："
    echo "1) 手动"
    echo "2) 自动检测(默认)"
    echo "3) 关闭"
    read -p "请选择(1/2/3): " proxy_choice
    proxy_choice=${proxy_choice:-"2"}
    
    case "$proxy_choice" in
        "1")
            read -p "请输入代理地址: " proxy
            proxy_mode="manual"
            ;;
        "3")
            proxy_mode="off"
            proxy=""
            ;;
        *)
            proxy_mode="auto"
            proxy=""
            ;;
    esac
    
    read -p "运行间隔（分钟，默认 360）: " interval_minutes
    interval_minutes=${interval_minutes:-"360"}
    
    # 保存配置
    cat > "$conf_file" << EOF
{
    "checkUpdate": $([ "$check_update" != "n" ] && echo "true" || echo "false"),
    "syncCode": $([ "$sync_code" != "n" ] && echo "true" || echo "false"),
    "proxyMode": "$proxy_mode",
    "proxy": "$proxy",
    "intervalMinutes": $interval_minutes
}
EOF
fi

# 读取配置
check_update=$(grep '"checkUpdate"' "$conf_file" | grep -o true || echo "false")
sync_code=$(grep '"syncCode"' "$conf_file" | grep -o true || echo "false")
proxy_mode=$(grep '"proxyMode"' "$conf_file" | cut -d'"' -f4)
proxy=$(grep '"proxy"' "$conf_file" | cut -d'"' -f4)
interval_minutes=$(grep '"intervalMinutes"' "$conf_file" | grep -o '[0-9]*')

# 创建更新脚本
update_script="$PWD/update-drpy.sh"

cat > "$update_script" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -e

cd "$(dirname "$0")"
source .venv/bin/activate

# 代理设置
case "$1" in
    "manual")
        export HTTP_PROXY="$2"
        export HTTPS_PROXY="$2"
        ;;
    "auto")
        if [ -n "$HTTP_PROXY" ]; then
            git config --global http.proxy "$HTTP_PROXY"
        else
            git config --global --unset http.proxy
        fi
        ;;
    *)
        git config --global --unset http.proxy
        ;;
esac

# 检查更新
if [ "$3" = "true" ]; then
    git fetch origin
    
    if [ "$4" = "true" ]; then
        local_commit=$(git rev-parse HEAD)
        remote_commit=$(git rev-parse '@{u}')
        
        if [ "$local_commit" != "$remote_commit" ]; then
            git reset --hard origin/main
            yarn install --registry https://registry.npmmirror.com/
            pip install -r spider/py/base/requirements.txt -i https://mirrors.cloud.tencent.com/pypi/simple
            pm2 restart drpyS
        fi
    fi
fi
EOF

chmod +x "$update_script"

# 添加 crontab 任务
cron_job="*/$interval_minutes * * * * $update_script $proxy_mode $proxy $check_update $sync_code"

# 检查是否已存在该任务
if ! crontab -l 2>/dev/null | grep -q "$update_script"; then
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    echo -e "${GREEN}已添加定时任务（每 ${interval_minutes} 分钟执行）${NC}"
else
    echo -e "${GREEN}定时任务已存在${NC}"
fi

# -------------------------------------------------
# 10. 完成提示
# -------------------------------------------------
echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}项目目录: $project_path${NC}"
echo -e "${GREEN}PM2 服务已启动${NC}"
echo -e "${GREEN}定时任务已设置（每 ${interval_minutes} 分钟检查更新）${NC}"
echo ""
echo -e "${CYAN}启动服务:${NC}"
echo "cd $project_path && pm2 start index.js --name drpyS"
echo ""
echo -e "${CYAN}查看日志:${NC}"
echo "pm2 logs drpyS"
echo ""
echo -e "${CYAN}访问地址:${NC}"
echo "http://localhost:5757"
echo "或使用 Termux 的端口转发功能"

# 停用虚拟环境
deactivate 2>/dev/null || true

echo -e "${GREEN}按任意键退出...${NC}"
read -n 1 -s