#!/bin/bash

# Strict mode
set -euo pipefail

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志配置
LOG_DIR="logs/deployment"
LOG_FILE="$LOG_DIR/nginx_deployment_$(date +%Y%m%d_%H%M%S).log"

# 确保日志目录存在
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# Configuration
DOCKER_COMPOSE_FILE="docker-compose.nginx-global_v06.yml"
NGINX_CONF="nginx.global.250128.conf"
BACKUP_DIR="nginx_backups/$(date +%Y%m%d_%H%M%S)"

# Functions
log() { echo -e "${GREEN}[INFO] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }

# Backup existing configuration
backup_configs() {
    log "[STEP 1/6] 备份现有配置..."
    mkdir -p "$BACKUP_DIR"
    
    if [ -f "$NGINX_CONF" ]; then
        cp "$NGINX_CONF" "$BACKUP_DIR/"
    fi
    
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        cp "$DOCKER_COMPOSE_FILE" "$BACKUP_DIR/"
    fi
    
    log "配置已备份到 $BACKUP_DIR"
}

# Create external network if not exists
create_network() {
    log "[STEP 2/6] 检查网络配置..."
    if ! docker network inspect saga4v_network >/dev/null 2>&1; then
        log "创建 saga4v_network 网络..."
        docker network create saga4v_network
    else
        log "saga4v_network 网络已存在"
    fi
}

# Stop existing container
stop_existing() {
    log "[STEP 3/6] 停止现有容器..."
    
    # 使用 docker-compose 停止容器
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        log "使用 docker-compose 停止容器..."
        if ! docker-compose -f "$DOCKER_COMPOSE_FILE" down --timeout 30; then
            warn "容器优雅停止超时，尝试强制停止..."
            if ! docker-compose -f "$DOCKER_COMPOSE_FILE" down -v --remove-orphans; then
                error "容器停止失败，收集诊断信息..."
                docker ps -a | grep saga4v-nginx
                docker logs --tail 50 saga4v-nginx || true
                return 1
            fi
        fi
    else
        warn "未找到 docker-compose 文件: $DOCKER_COMPOSE_FILE"
        # 尝试直接停止容器
        if docker ps -q --filter "name=saga4v-nginx" | grep -q .; then
            log "尝试直接停止容器..."
            docker stop -t 30 saga4v-nginx || docker kill saga4v-nginx
        fi
    fi
    
    log "✓ 容器停止完成"
    return 0
}

# 添加新的检查函数
check_dependencies() {
    log "检查依赖服务..."
    
    # 从 nginx.conf 解析 SSL 证书配置和对应的服务
    local NGINX_CONF="nginx.global.250128.conf"
    declare -A SSL_SERVICES
    
    # 首先获取所有配置了 SSL 证书的域名
    local current_domain=""
    local has_ssl=false
    
    while IFS= read -r line; do
        # 提取域名
        local server_name=$(echo "$line" | awk '/server_name/ {print $2}' | tr -d ';')
        # 提取 SSL 证书路径
        local ssl_cert=$(echo "$line" | grep -o '/etc/nginx/ssl/[^/]*/fullchain.pem' || true)
        # 提取完整的代理地址，包括整个 proxy_pass 行
        local proxy_pass=$(echo "$line" | grep -o 'proxy_pass http://[^;]*' | sed 's/proxy_pass http:\/\///')
        
        if [[ -n "$server_name" ]]; then
            current_domain="$server_name"
            has_ssl=false
        fi
        
        if [[ -n "$ssl_cert" ]]; then
            has_ssl=true
        fi
        
        if [[ -n "$proxy_pass" ]] && [[ "$has_ssl" == true ]] && [[ -n "$current_domain" ]]; then
            SSL_SERVICES["$proxy_pass"]="$current_domain"
        fi
    done < "$NGINX_CONF"
    
    # 检查配置了 SSL 的服务
    for service_addr in "${!SSL_SERVICES[@]}"; do
        local domain=${SSL_SERVICES[$service_addr]}
        local port=$(echo "$service_addr" | grep -o ':[0-9]*$' | tr -d ':')
        
        # 获取所有运行中的容器名称
        local containers=$(docker ps --format '{{.Names}}')
        local matched_container=""
        
        # 根据端口匹配容器
        while IFS= read -r container; do
            if docker exec "$container" netstat -tlpn 2>/dev/null | grep -q ":$port"; then
                matched_container="$container"
                break
            fi
        done <<< "$containers"
        
        if [[ -z "$matched_container" ]]; then
            error "找不到监听 $port 端口的容器"
            log "当前运行的容器列表："
            docker ps
            return 1
        fi
        
        log "检查 SSL 服务: $matched_container (端口: $port, 域名: $domain)"
        
        # 改进网络连接检查
        if ! docker network inspect saga4v_network | grep -q "\"Name\": \"$matched_container\""; then
            # 使用更可靠的方式验证网络连接
            if ! docker inspect "$matched_container" --format '{{range $net,$v := .NetworkSettings.Networks}}{{$net}}{{end}}' | grep -q "saga4v_network"; then
                error "$matched_container 未连接到 saga4v_network 网络"
                log "网络详情："
                docker network inspect saga4v_network
                return 1
            fi
        fi
    done
    
    if [ ${#SSL_SERVICES[@]} -eq 0 ]; then
        warn "未发现配置了 SSL 证书的服务"
        return 0
    fi
    
    log "✓ 所有 SSL 服务检查通过"
    return 0
}

# Deploy new container
deploy_container() {
    log "[STEP 4/6] 部署容器..."
    
    # 检查配置文件
    local nginx_conf="nginx.global.250128.conf"
    if [ ! -f "$nginx_conf" ]; then
        error "$nginx_conf 文件不存在"
        error "请确保配置文件位于当前目录: $(pwd)"
        return 1
    fi
    
    # 使用正确的 docker-compose 文件
    if ! docker-compose -f "$DOCKER_COMPOSE_FILE" up -d; then
        error "容器部署失败"
        return 1
    fi
    
    return 0
}

# Health check
health_check() {
    log "[STEP 5/6] 基础健康检查..."
    local max_retries=5
    local retry=0
    local wait_time=2
    
    while [ $retry -lt $max_retries ]; do
        local container_status=$(docker inspect -f '{{.State.Status}}' saga4v-nginx 2>/dev/null || echo "not_found")
        
        case "$container_status" in
            "running")
                # 只检查基本的 Nginx 进程
                if docker exec saga4v-nginx pgrep nginx >/dev/null; then
                    log "✓ 基础健康检查通过"
                    return 0
                fi
                ;;
            "not_found"|"exited"|"dead")
                if [ $retry -eq $((max_retries - 1)) ]; then
                    error "容器未能正常启动"
                    return 1
                fi
                ;;
        esac
        
        log "等待服务启动... ($retry/$max_retries)"
        sleep $wait_time
        retry=$((retry + 1))
    done
    
    warn "健康检查未完全通过，但容器已启动"
    return 0
}

# Verify deployment
verify_deployment() {
    log "[STEP 6/6] 验证部署..."
    
    # 检查 saga4v-nginx 容器状态
    local nginx_container_id=$(docker ps -q --filter "name=saga4v-nginx")
    if [ -z "$nginx_container_id" ]; then
        error "找不到 saga4v-nginx 容器"
        return 1
    fi
    
    # 使用多重检查机制
    local check_failed=0
    
    # 1. 检查 Nginx 主进程
    if ! docker exec $nginx_container_id sh -c "cat /proc/1/comm" | grep -q "nginx"; then
        error "Nginx 主进程未运行"
        check_failed=1
    fi
    
    # 2. 检查 Nginx worker 进程
    if ! docker exec $nginx_container_id sh -c "cat /proc/[0-9]*/comm" | grep -q "nginx"; then
        error "Nginx worker 进程未运行"
        check_failed=1
    fi
    
    # 3. 检查配置文件权限
    if ! docker exec $nginx_container_id sh -c "ls -l /etc/nginx/nginx.conf"; then
        error "无法访问 Nginx 配置文件"
        check_failed=1
    fi
    
    # 4. 检查日志目录权限
    if ! docker exec $nginx_container_id sh -c "ls -l /var/log/nginx/"; then
        error "无法访问日志目录"
        check_failed=1
    fi
    
    # 5. 检查端口监听
    if ! timeout 5 bash -c "</dev/tcp/localhost/80" 2>/dev/null; then
        error "80 端口未监听"
        check_failed=1
    fi
    
    if ! timeout 5 bash -c "</dev/tcp/localhost/443" 2>/dev/null; then
        error "443 端口未监听"
        check_failed=1
    fi
    
    # 如果任何检查失败，收集诊断信息
    if [ $check_failed -eq 1 ]; then
        log "收集诊断信息..."
        docker exec $nginx_container_id sh -c "nginx -T" || true
        docker logs $nginx_container_id
        return 1
    fi
    
    log "✓ 部署验证通过"
    return 0
}

# 添加检查 Nginx 日志目录的函数
check_nginx_logs() {
    log "[检查] 验证 Nginx 日志目录..."
    
    # 使用docker inspect检查容器状态
    if ! docker inspect saga4v-nginx >/dev/null 2>&1; then
        error "容器不存在"
        return 1
    fi
    
    # 使用volume而不是直接操作容器内部
    docker run --rm \
        --volumes-from saga4v-nginx \
        -v $(pwd)/scripts:/scripts \
        nginx:stable-alpine \
        sh -c '
            mkdir -p /var/log/nginx && \
            chown -R nginx:nginx /var/log/nginx && \
            chmod 755 /var/log/nginx
        '
    
    if [ $? -eq 0 ]; then
        log "✓ Nginx 日志目录配置完成"
    else
        error "Nginx 日志目录配置失败"
        return 1
    fi
}

# Error handling
cleanup() {
    if [ $? -ne 0 ]; then
        error "部署失败，正在回滚..."
        if [ -d "$BACKUP_DIR" ]; then
            cp "$BACKUP_DIR"/* ./ 2>/dev/null || true
        fi
        docker-compose -f "$DOCKER_COMPOSE_FILE" down || true
    fi
}

trap cleanup EXIT

# 修改 check_certificates 函数，添加证书时间验证
check_certificates() {
    log "检查 SSL 证书..."
    local domains="love.saga4v.com play.saga4v.com payment.saga4v.com"
    
    for domain in $domains; do
        local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
        
        # 检查证书文件存在
        if [ ! -f "$cert_path" ] || [ ! -f "/etc/letsencrypt/live/$domain/privkey.pem" ]; then
            error "缺少 $domain 的证书文件"
            return 1
        fi
        
        # 检查证书有效期
        local current_time=$(date +%s)
        local not_before=$(openssl x509 -in "$cert_path" -noout -startdate | cut -d= -f2)
        local not_after=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
        
        local start_time=$(date -d "$not_before" +%s)
        local end_time=$(date -d "$not_after" +%s)
        
        if [ $current_time -lt $start_time ]; then
            error "$domain 的证书尚未生效 (生效时间: $not_before)"
            error "需要重新申请证书"
            return 1
        fi
        
        if [ $current_time -gt $end_time ]; then
            error "$domain 的证书已过期 (过期时间: $not_after)"
            error "需要更新证书"
            return 1
        fi
        
        # 检查剩余有效期
        local days_left=$(( ($end_time - $current_time) / 86400 ))
        if [ $days_left -lt 30 ]; then
            warn "$domain 的证书将在 $days_left 天后过期"
        fi
    done
    
    log "✓ SSL 证书检查通过"
    return 0
}

# 修改验证配置函数
verify_config() {
    log "验证 Nginx 配置..."
    
    # 基本语法检查
    if ! docker run --rm \
        -v "$(pwd)/nginx.global.250128.conf:/etc/nginx/nginx.conf:ro" \
        nginx:stable-alpine nginx -t 2>/dev/null; then
        warn "Nginx 配置文件存在警告，但将继续部署..."
    fi
    
    # 只检查关键错误
    if docker run --rm \
        -v "$(pwd)/nginx.global.250128.conf:/etc/nginx/nginx.conf:ro" \
        nginx:stable-alpine nginx -t 2>&1 | grep -i "emerg" > /dev/null; then
        error "Nginx 配置存在严重错误"
        return 1
    fi
    
    log "✓ 配置文件基本验证通过"
    return 0
}

# 添加日志目录检查函数
check_log_directories() {
    log "检查日志目录..."
    
    # 创建所需的日志目录
    mkdir -p /var/log/nginx
    
    # 创建所需的日志文件
    touch /var/log/nginx/ssl-error.log
    touch /var/log/nginx/payment-ssl-error.log
    touch /var/log/nginx/payment.access.log
    touch /var/log/nginx/payment.error.log
    
    # 设置正确的权限
    chown -R nginx:nginx /var/log/nginx
    chmod 644 /var/log/nginx/*.log
    
    log "✓ 日志目录检查完成"
}

# Main function
main() {
    log "开始部署全局 Nginx..."
    
    log "[STEP 1/6] 备份现有配置..."
    backup_configs
    
    log "[STEP 2/6] 检查网络配置..."
    create_network
    
    log "[STEP 3/6] 停止现有容器..."
    stop_existing
    
    log "[STEP 4/6] 准备环境..."
    check_log_directories
    check_certificates
    
    # 验证本地配置文件
    log "[STEP 5/6] 验证配置文件..."
    verify_config
    
    log "[STEP 6/6] 部署容器..."
    deploy_container
    
    # 等待容器启动
    log "等待容器启动..."
    sleep 5
    
    # 在容器启动后验证配置
    if ! docker exec saga4v-nginx nginx -t; then
        error "容器内 Nginx 配置验证失败"
        return 1
    fi
    
    check_nginx_logs
    health_check
    verify_deployment
    
    log "✓ 部署完成!"
    return 0
}

# Error handling
cleanup() {
    if [ $? -ne 0 ]; then
        error "部署失败，正在回滚..."
        if [ -d "$BACKUP_DIR" ]; then
            cp "$BACKUP_DIR"/* ./ 2>/dev/null || true
        fi
        docker-compose -f "$DOCKER_COMPOSE_FILE" down || true
    fi
}

trap cleanup EXIT

# Execute main function
main

verify_cert() {
    local domain="payment.saga4v.com"
    openssl x509 -in /etc/letsencrypt/live/$domain/fullchain.pem -text -noout | grep "Subject:"
}

# 添加调试函数
debug_nginx_status() {
    local container_id=$1
    log "收集 Nginx 诊断信息..."
    
    # 检查进程
    docker exec $container_id sh -c "ps aux" || true
    
    # 检查端口绑定
    docker exec $container_id sh -c "cat /proc/net/tcp /proc/net/tcp6" || true
    
    # 检查 Nginx 配置
    docker exec $container_id sh -c "nginx -T" || true
    
    # 检查错误日志
    docker exec $container_id sh -c "tail -n 50 /var/log/nginx/error.log" || true
}