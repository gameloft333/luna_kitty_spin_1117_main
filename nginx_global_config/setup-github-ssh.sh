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

# 检查必要的命令
check_requirements() {
    log "检查必要的命令..."
    local required_commands=("git" "ssh-keygen" "ssh-agent")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error "未找到命令: $cmd"
            return 1
        fi
    done
    return 0
}

# 获取当前Git仓库信息
get_git_info() {
    log "获取Git仓库信息..."
    
    # 检查是否在git仓库中
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        error "当前目录不是Git仓库"
        return 1
    fi
    
    # 获取远程仓库URL
    REPO_URL=$(git config --get remote.origin.url)
    if [[ -z "$REPO_URL" ]]; then
        error "未找到远程仓库URL"
        return 1
    fi
    
    # 获取当前用户名
    GIT_USERNAME=$(git config --get user.name)
    # 获取当前邮箱
    GIT_EMAIL=$(git config --get user.email)
    
    log "当前仓库URL: $REPO_URL"
    log "当前Git用户名: $GIT_USERNAME"
    log "当前Git邮箱: $GIT_EMAIL"
    return 0
}

# 生成SSH密钥
generate_ssh_key() {
    log "开始生成SSH密钥..."
    
    # 确认邮箱地址
    local email
    if [[ -n "$GIT_EMAIL" ]]; then
        read -p "是否使用当前Git邮箱($GIT_EMAIL)? [Y/n] " use_current_email
        if [[ "$use_current_email" =~ ^[Nn]$ ]]; then
            read -p "请输入GitHub邮箱地址: " email
        else
            email="$GIT_EMAIL"
        fi
    else
        read -p "请输入GitHub邮箱地址: " email
    fi
    
    # 检查邮箱格式
    if ! echo "$email" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        error "无效的邮箱格式"
        return 1
    fi
    
    # 生成密钥
    log "生成SSH密钥..."
    if ! ssh-keygen -t ed25519 -C "$email" -f ~/.ssh/id_ed25519; then
        error "SSH密钥生成失败"
        return 1
    fi
    
    # 启动ssh-agent
    log "启动ssh-agent..."
    eval "$(ssh-agent -s)"
    
    # 添加私钥
    log "添加SSH私钥到ssh-agent..."
    if ! ssh-add ~/.ssh/id_ed25519; then
        error "添加SSH私钥失败"
        return 1
    fi
    
    return 0
}

# 显示公钥
show_public_key() {
    log "您的SSH公钥如下："
    echo "-------------------"
    cat ~/.ssh/id_ed25519.pub
    echo "-------------------"
    log "请将上述公钥添加到GitHub："
    log "1. 访问 https://github.com/settings/keys"
    log "2. 点击 'New SSH key'"
    log "3. 输入标题（如：AWS Server）"
    log "4. 粘贴上述公钥内容"
    log "5. 点击 'Add SSH key'"
}

# 更新远程仓库URL
update_remote_url() {
    log "更新远程仓库URL为SSH格式..."
    
    # 获取当前远程仓库URL
    local current_url=$(git remote get-url origin)
    log "当前远程仓库URL: $current_url"
    
    # 提取用户名和仓库名（处理 HTTPS 和 SSH 格式）
    local github_user
    local repo_name
    
    if [[ "$current_url" =~ ^https://github\.com/([^/]+)/([^/.]+)(\.git)?$ ]]; then
        # HTTPS 格式
        github_user="${BASH_REMATCH[1]}"
        repo_name="${BASH_REMATCH[2]}"
    elif [[ "$current_url" =~ ^git@github\.com:([^/]+)/([^/.]+)(\.git)?$ ]]; then
        # SSH 格式
        github_user="${BASH_REMATCH[1]}"
        repo_name="${BASH_REMATCH[2]}"
    elif [[ "$current_url" =~ ^http://github\.com/([^/]+)/([^/.]+)(\.git)?$ ]]; then
        # HTTP 格式
        github_user="${BASH_REMATCH[1]}"
        repo_name="${BASH_REMATCH[2]}"
    else
        error "无法解析仓库URL格式: $current_url"
        error "请确保URL格式正确，例如："
        error "HTTPS格式: https://github.com/username/repo.git"
        error "SSH格式: git@github.com:username/repo.git"
        return 1
    fi
    
    # 构建新的SSH URL
    local new_url="git@github.com:$github_user/$repo_name.git"
    
    log "解析结果:"
    log "用户名: $github_user"
    log "仓库名: $repo_name"
    log "原始URL: $current_url"
    log "新的URL: $new_url"
    
    read -p "是否更新远程仓库URL? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 备份原有的远程仓库配置
        local old_url="$current_url"
        log "备份原有URL: $old_url"
        
        # 更新远程仓库URL
        if ! git remote set-url origin "$new_url"; then
            error "更新远程仓库URL失败"
            git remote set-url origin "$old_url"
            return 1
        fi
        
        # 验证更新
        local updated_url=$(git remote get-url origin)
        if [[ "$updated_url" == "$new_url" ]]; then
            log "远程仓库URL已成功更新为: $new_url"
            
            # 测试新的连接
            if ! git ls-remote &>/dev/null; then
                error "无法连接到新的远程仓库，正在恢复原有配置..."
                git remote set-url origin "$old_url"
                return 1
            fi
            
            log "连接测试成功！"
        else
            error "URL更新验证失败"
            git remote set-url origin "$old_url"
            return 1
        fi
    else
        log "保持原有URL不变"
    fi
    
    return 0
}

# 测试SSH连接
test_connection() {
    log "测试SSH连接..."
    # 执行SSH测试并捕获输出
    local output
    output=$(ssh -T git@github.com 2>&1)
    
    # 检查输出中是否包含成功认证的信息
    if echo "$output" | grep -q "successfully authenticated"; then
        log "SSH连接测试成功！"
        return 0
    else
        error "SSH连接测试失败"
        error "错误信息: $output"
        return 1
    fi
}

# 创建SSH配置文件
create_ssh_config() {
    log "创建SSH配置文件..."
    
    local config_file=~/.ssh/config
    if [[ ! -f "$config_file" ]]; then
        cat > "$config_file" << EOF
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
EOF
        log "SSH配置文件已创建"
    else
        warn "SSH配置文件已存在，跳过创建"
    fi
    
    # 设置正确的权限
    chmod 600 "$config_file"
    return 0
}

# 检查并配置 SSH Agent
check_and_setup_ssh_agent() {
    log "检查 SSH 密钥状态..."
    
    # 检查密钥是否存在
    if [[ ! -f ~/.ssh/id_ed25519 ]]; then
        error "未找到 SSH 密钥文件"
        return 1
    fi
    
    # 检查密钥是否有密码保护
    # 尝试不输入密码读取私钥
    if ssh-keygen -y -f ~/.ssh/id_ed25519 </dev/null &>/dev/null; then
        log "检测到无密码的 SSH 密钥，无需额外配置"
        return 0
    else
        log "检测到您的 SSH 密钥设置了密码保护"
        log "为了避免每次使用 Git 时都需要输入密码，建议将密钥添加到 ssh-agent"
        
        read -p "是否要将密钥添加到 ssh-agent？[Y/n] " setup_agent
        if [[ ! "$setup_agent" =~ ^[Nn]$ ]]; then
            log "正在启动 ssh-agent..."
            eval "$(ssh-agent -s)"
            
            log "正在添加密钥到 ssh-agent..."
            log "注意：这将是本次会话中最后一次需要输入密钥密码"
            if ssh-add ~/.ssh/id_ed25519; then
                log "密钥已成功添加到 ssh-agent"
                log "在当前会话中，您不需要再次输入密码"
                log "提示：每次重新登录服务器后，您可能需要重新运行这个命令："
                log "eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_ed25519"
                
                # 询问是否要添加到启动配置
                read -p "是否将 ssh-agent 配置添加到登录脚本中？[y/N] " add_to_profile
                if [[ "$add_to_profile" =~ ^[Yy]$ ]]; then
                    local profile_file="$HOME/.bashrc"
                    if [[ -f "$HOME/.bash_profile" ]]; then
                        profile_file="$HOME/.bash_profile"
                    fi
                    
                    echo -e "\n# SSH Agent 配置" >> "$profile_file"
                    echo 'eval "$(ssh-agent -s)" > /dev/null' >> "$profile_file"
                    echo 'ssh-add ~/.ssh/id_ed25519 2>/dev/null' >> "$profile_file"
                    
                    log "配置已添加到 $profile_file"
                    log "下次登录时将自动启动 ssh-agent 并添加密钥"
                fi
                
                return 0
            else
                error "添加密钥到 ssh-agent 失败"
                return 1
            fi
        else
            warn "已跳过 ssh-agent 配置，您每次使用 Git 时可能需要输入密码"
            return 0
        fi
    fi
}

# 主函数
main() {
    log "=== GitHub SSH 配置助手 v1.1.8 ==="
    
    # 检查必要的命令
    if ! check_requirements; then
        error "缺少必要的命令，请先安装"
        exit 1
    fi
    
    # 获取Git信息
    if ! get_git_info; then
        error "获取Git信息失败"
        exit 1
    fi
    
    # 生成SSH密钥
    if ! generate_ssh_key; then
        error "SSH密钥生成失败"
        exit 1
    fi
    
    # 创建SSH配置
    if ! create_ssh_config; then
        error "创建SSH配置失败"
        exit 1
    fi
    
    # 显示公钥
    show_public_key
    
    # 等待用户在GitHub上添加密钥
    read -p "按Enter键继续（请确保已将公钥添加到GitHub）..."
    
    # 在测试连接之前添加 ssh-agent 检查
    if ! check_and_setup_ssh_agent; then
        error "SSH Agent 配置失败"
        exit 1
    fi
    
    # 测试连接
    if ! test_connection; then
        error "SSH连接测试失败，请检查是否正确添加了公钥"
        exit 1
    fi
    
    # 更新远程URL
    if ! update_remote_url; then
        error "更新远程仓库URL失败"
        exit 1
    fi
    
    log "GitHub SSH 配置完成！"
    log "现在您可以使用git pull和git push而无需输入密码"
    return 0
}

# 执行主函数
main
exit $?