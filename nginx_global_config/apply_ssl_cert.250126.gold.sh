#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[INFO] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }

# 检查域名格式是否有效
check_domain_format() {
    local domain=$1
    # 域名格式规则：
    # 1. 只能包含字母、数字、连字符(-)和点(.)
    # 2. 每个部分必须以字母或数字开头和结尾
    # 3. 必须包含至少一个点(.)
    # 4. 顶级域名至少2个字符
    if ! echo "$domain" | grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
        error "无效的域名格式: $domain"
        log "域名格式要求："
        log "1. 只能包含字母、数字、连字符(-)和点(.)"
        log "2. 每个部分必须以字母或数字开头和结尾"
        log "3. 必须包含至少一个点(.)"
        log "4. 顶级域名至少2个字符"
        log "有效的域名示例："
        log "  - example.com"
        log "  - sub.example.com"
        log "  - my-website.com"
        log "  - kitty.saga4v.com"
        return 1
    fi
    return 0
}

# 检查并安装 Certbot
check_install_certbot() {
    log "检查 Certbot 安装状态..."
    
    if ! command -v certbot &> /dev/null; then
        warn "未检测到 Certbot，准备安装..."
        
        # 检测系统类型和版本
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                "debian"|"ubuntu")
                    log "检测到 Debian/Ubuntu 系统"
                    apt-get update
                    apt-get install -y certbot python3-certbot-nginx
                    ;;
                "centos"|"rhel"|"fedora"|"rocky"|"almalinux"|"amzn")
                    log "检测到 RHEL 系列系统: $ID"
                    if [ "$ID" = "centos" ] && [ "$VERSION_ID" = "7" ]; then
                        # CentOS 7 特殊处理
                        yum install -y epel-release
                        yum install -y certbot python-certbot-nginx
                    else
                        # CentOS 8+ 和其他 RHEL 系列
                        dnf install -y epel-release
                        dnf install -y certbot python3-certbot-nginx
                    fi
                    ;;
                *)
                    error "未能识别的系统类型: $ID"
                    error "支持的系统类型："
                    error "- Debian/Ubuntu"
                    error "- CentOS/RHEL"
                    error "- Rocky Linux"
                    error "- AlmaLinux"
                    error "- Amazon Linux"
                    error "- Fedora"
                    return 1
                    ;;
            esac
        else
            error "无法检测系统类型（/etc/os-release 文件不存在）"
            return 1
        fi
        
        # 验证安装结果
        if command -v certbot &> /dev/null; then
            log "Certbot 安装成功"
            # 显示版本信息
            certbot --version
        else
            error "Certbot 安装失败"
            error "请尝试手动安装 Certbot:"
            error "Debian/Ubuntu: apt-get install certbot python3-certbot-nginx"
            error "CentOS/RHEL: dnf install certbot python3-certbot-nginx"
            return 1
        fi
    else
        log "Certbot 已安装，版本信息："
        certbot --version
    fi
    
    return 0
}

# 检查域名DNS解析和可访问性
check_domain_accessibility() {
    local domain=$1
    log "检查域名 $domain 的可访问性..."
    
    # 检查DNS解析
    log "正在检查DNS解析..."
    if ! host "$domain" &>/dev/null; then
        error "域名 $domain 无法解析到IP地址"
        log "请确保："
        log "1. 域名已经正确配置DNS解析"
        log "2. DNS解析已经生效（可能需要等待几分钟到几小时）"
        return 1
    fi
    
    # 检查域名是否解析到当前服务器
    local domain_ip=$(host "$domain" | grep "has address" | head -1 | awk '{print $NF}')
    local server_ip=$(curl -s ifconfig.me)
    
    log "域名解析IP: $domain_ip"
    log "服务器IP: $server_ip"
    
    if [ "$domain_ip" != "$server_ip" ]; then
        error "域名 $domain 未指向当前服务器"
        log "当前情况："
        log "- 域名解析IP: $domain_ip"
        log "- 服务器IP: $server_ip"
        log "请确保域名解析到当前服务器IP"
        return 1
    fi
    
    # 检查Nginx配置
    log "正在检查Nginx配置..."
    local nginx_test_output=$(nginx -t 2>&1)
    if ! nginx -t &>/dev/null; then
        error "Nginx 配置检查失败"
        error "Nginx 配置错误详情："
        error "$nginx_test_output"
        log "请检查以下内容："
        log "1. Nginx 配置文件语法是否正确"
        log "2. SSL 证书文件路径是否存在"
        log "3. SSL 证书文件权限是否正确"
        log "4. 相关目录是否具有正确的权限"
        
        # 检查证书文件
        log "检查SSL证书文件..."
        for cert_file in "/etc/nginx/ssl/$domain/fullchain.pem" "/etc/nginx/ssl/$domain/privkey.pem"; do
            if [ -f "$cert_file" ]; then
                log "证书文件存在: $cert_file"
                log "文件权限: $(ls -l $cert_file)"
            else
                error "证书文件不存在: $cert_file"
            fi
        done
        
        # 检查nginx用户权限
        log "检查Nginx用户权限..."
        log "Nginx运行用户: $(ps aux | grep nginx | grep master | awk '{print $1}')"
        
        return 1
    fi
    
    # 检查80端口是否开放
    log "正在检查80端口访问..."
    local curl_output=$(curl -v -s -I "http://$domain" 2>&1)
    if ! curl -s -I "http://$domain" &>/dev/null; then
        error "无法通过 HTTP 访问域名 $domain"
        error "curl 详细输出："
        error "$curl_output"
        log "请检查："
        log "1. Nginx 是否正在运行: $(systemctl status nginx | grep Active)"
        log "2. 80 端口是否被占用: $(netstat -tlnp | grep :80)"
        log "3. 防火墙规则: $(iptables -L | grep 80)"
        return 1
    fi
    
    log "域名 $domain 检查通过"
    return 0
}

# 申请证书
apply_cert() {
    local domain=$1
    local email=$2
    
    # 停止所有相关容器
    docker stop saga4v-nginx temp-nginx 2>/dev/null || true
    docker rm saga4v-nginx temp-nginx 2>/dev/null || true
    
    # 创建必要的目录
    mkdir -p /var/www/html/.well-known/acme-challenge
    chmod -R 755 /var/www/html
    
    # 创建简化的临时 Nginx 配置
    cat > "temp_nginx.conf" <<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    # 仅配置 HTTP 验证服务器
    server {
        listen 80;
        server_name $domain;
        
        # 禁用所有缓存
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires 0;
        
        location /.well-known/acme-challenge/ {
            root /var/www/html;
            try_files \$uri =404;
            
            # 调试信息
            add_header X-Debug-Path \$document_root;
            add_header X-Debug-URI \$uri;
        }
        
        # 其他所有请求返回 444
        location / {
            return 444;
        }
    }
}
EOF

    # 启动临时 Nginx 容器
    docker run -d \
        --name temp-nginx \
        -p 80:80 \
        -v $(pwd)/temp_nginx.conf:/etc/nginx/nginx.conf:ro \
        -v /var/www/html:/var/www/html \
        nginx:latest

    # 等待 Nginx 启动
    log "等待 Nginx 启动..."
    local max_retries=10
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if docker exec temp-nginx nginx -t &>/dev/null; then
            log "Nginx 配置检查通过"
            # 验证 acme-challenge 目录是否可访问
            if curl -s -I "http://localhost/.well-known/acme-challenge/test" 2>&1 | grep -q "404"; then
                log "验证服务器配置正确"
                break
            fi
        fi
        retry=$((retry + 1))
        log "等待 Nginx 启动 (${retry}/${max_retries})..."
        sleep 2
    done

    if [ $retry -eq $max_retries ]; then
        error "Nginx 验证服务器启动失败"
        docker logs temp-nginx
        docker stop temp-nginx
        docker rm temp-nginx
        rm -f temp_nginx.conf
        return 1
    fi
    
    # 申请证书
    certbot certonly --webroot \
        --webroot-path /var/www/html \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" \
        --preferred-challenges http-01
        
    local cert_result=$?
    
    # 清理
    docker stop temp-nginx
    docker rm temp-nginx
    rm -f temp_nginx.conf
    
    if [ $cert_result -eq 0 ]; then
        # 创建证书目录
        mkdir -p /etc/nginx/ssl/$domain
        
        # 创建证书软链接
        ln -sf /etc/letsencrypt/live/$domain/fullchain.pem /etc/nginx/ssl/$domain/fullchain.pem
        ln -sf /etc/letsencrypt/live/$domain/privkey.pem /etc/nginx/ssl/$domain/privkey.pem
        
        log "✓ $domain 证书申请成功"
        log "证书位置: /etc/nginx/ssl/$domain/"
        return 0
    else
        error "× $domain 证书申请失败"
        error "详细错误日志: /var/log/letsencrypt/letsencrypt.log"
        return 1
    fi
}

# 主函数
main() {
    # 首先检查 Certbot
    if ! check_install_certbot; then
        error "Certbot 环境检查失败，无法继续"
        exit 1
    fi
    
    clear
    log "=== SSL 证书申请工具 ==="
    log "本工具将帮助您为域名申请 Let's Encrypt SSL 证书"
    echo
    
    # 检查是否以root权限运行
    if [ "$EUID" -ne 0 ]; then
        error "请使用 root 权限运行此脚本"
        exit 1
    fi
    
    # 显示域名格式说明
    log "域名格式说明："
    log "1. 只能包含字母、数字、连字符(-)和点(.)"
    log "2. 每个部分必须以字母或数字开头和结尾"
    log "3. 必须包含至少一个点(.)"
    log "4. 顶级域名至少2个字符"
    log "示例: example.com, www.example.com, my-site.com"
    echo
    
    # 获取用户输入
    read -p "请输入需要申请证书的域名（如 example.com）: " domain
    
    # 验证域名格式
    if ! check_domain_format "$domain"; then
        exit 1
    fi
    
    # 获取邮箱地址
    read -p "请输入您的邮箱地址（用于证书到期提醒）: " email
    
    # 显示确认信息
    echo
    log "请确认以下信息："
    echo "域名: $domain"
    echo "邮箱: $email"
    echo
    read -p "确认申请证书？(y/n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log "用户取消操作"
        exit 0
    fi
    
    # 申请证书
    apply_cert "$domain" "$email"
    
    # 显示使用说明
    if [ $? -eq 0 ]; then
        echo
        log "=== 使用说明 ==="
        log "1. 证书有效期为90天"
        log "2. Certbot 会自动续期证书"
        log "3. 您可以在 Nginx 配置中使用以下路径："
        echo "   ssl_certificate     /etc/letsencrypt/live/$domain/fullchain.pem;"
        echo "   ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;"
    fi
}

# 执行主函数
main
exit $?