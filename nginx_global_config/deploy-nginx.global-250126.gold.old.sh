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
    
    # 检查并停止 Nginx 相关的 docker-proxy 进程
    local nginx_proxies=$(ps aux | grep docker-proxy | grep -E ':80|:443' | awk '{print $2}')
    if [ -n "$nginx_proxies" ]; then
        log "发现 Nginx 相关的 docker-proxy 进程："
        for pid in $nginx_proxies; do
            # 获取对应的容器 ID
            local container_id=$(docker ps -q --filter "publish=80-80" --filter "publish=443-443")
            if [ -n "$container_id" ]; then
                local container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/\///')
                # 只停止 saga4v-nginx 容器
                if [[ "$container_name" == "saga4v-nginx" ]]; then
                    log "停止容器: $container_name"
                    docker stop "$container_id" || true
                    docker rm "$container_id" || true
                else
                    log "跳过非 Nginx 容器: $container_name"
                fi
            fi
        done
    fi
    
    # 等待端口释放
    local timeout=30
    local counter=0
    while [ $counter -lt $timeout ]; do
        if ! docker ps -q --filter "name=saga4v-nginx" | grep -q .; then
            log "✓ Nginx 容器已停止"
            return 0
        fi
        counter=$((counter + 1))
        sleep 1
    done
    
    if [ $counter -eq $timeout ]; then
        error "Nginx 容器停止超时"
        docker ps | grep saga4v-nginx
        return 1
    fi
}

# 添加新的检查函数
check_dependencies() {
    log "检查依赖服务..."
    
    # 从 nginx.conf 解析 SSL 证书配置和对应的服务
    local NGINX_CONF="nginx.global.250122.conf"
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
    local nginx_conf="nginx.global.250122.conf"
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
    log "[STEP 5/6] 健康检查..."
    local max_retries=10  # 增加重试次数
    local retry=0
    local wait_time=5
    
    while [ $retry -lt $max_retries ]; do
        # 检查容器状态
        container_status=$(docker inspect -f '{{.State.Status}}' saga4v-nginx 2>/dev/null)
        
        case "$container_status" in
            "running")
                # 容器正在运行，检查 Nginx
                if docker exec saga4v-nginx nginx -t &>/dev/null; then
                    log "✓ 健康检查通过"
                    return 0
                fi
                ;;
            "restarting")
                # 立即收集错误信息并退出
                error "容器重启循环，收集错误信息..."
                log "1. 容器状态："
                docker ps -a | grep saga4v-nginx
                log "2. 容器日志："
                docker logs --tail 50 saga4v-nginx
                log "3. Nginx 配置检查："
                docker exec saga4v-nginx nginx -T || true
                return 1
                ;;
            *)
                if [ $retry -eq $((max_retries - 1)) ]; then
                    # 最后一次重试时收集完整诊断信息
                    error "健康检查失败，收集诊断信息..."
                    log "1. 容器状态："
                    docker ps -a | grep saga4v-nginx
                    log "2. 容器日志："
                    docker logs --tail 20 saga4v-nginx
                    log "3. Nginx 错误日志："
                    docker exec saga4v-nginx cat /var/log/nginx/error.log 2>/dev/null || true
                    error "健康检查超时，状态: $container_status"
                    return 1
                fi
                log "等待容器启动... ($retry/$max_retries) [状态: $container_status]"
                ;;
        esac
        
        log "等待服务就绪... ($retry/$max_retries)"
        sleep $wait_time
        retry=$((retry + 1))
    done
    
    return 1
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

# Main function
main() {
    log "开始部署全局 Nginx..."
    
    backup_configs
    create_network
    stop_existing
    deploy_container
    check_nginx_logs
    health_check
    verify_deployment
    
    log "部署完成!"
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

check_certificates() {
    log "检查 SSL 证书..."
    local domains="love.saga4v.com play.saga4v.com payment.saga4v.com"
    
    for domain in $domains; do
        if [ ! -f "/etc/letsencrypt/live/$domain/fullchain.pem" ] || \
           [ ! -f "/etc/letsencrypt/live/$domain/privkey.pem" ]; then
            error "缺少 $domain 的证书文件"
            return 1
        fi
    done
    
    log "✓ SSL 证书检查通过"
    return 0
}

verify_cert() {
    local domain="payment.saga4v.com"
    openssl x509 -in /etc/letsencrypt/live/$domain/fullchain.pem -text -noout | grep "Subject:"
}

verify_config() {
    log "验证 Nginx 配置..."
    
    # 检查证书文件权限
    for domain in love.saga4v.com play.saga4v.com payment.saga4v.com; do
        if [ ! -r "/etc/nginx/ssl/$domain/fullchain.pem" ] || \
           [ ! -r "/etc/nginx/ssl/$domain/privkey.pem" ]; then
            error "证书文件权限错误: $domain"
            return 1
        fi
    done
    
    # 验证 Nginx 配置
    if ! docker exec saga4v-nginx nginx -t; then
        error "Nginx 配置验证失败"
        return 1
    fi
    
    return 0
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