
## 一、文档目的

本文档详细记录**OpenCart电商系统测试环境**完整搭建流程，包含虚拟机网络配置、LAMP环境部署、源码安装、数据库配置、权限修复及安全收尾操作。所有步骤附带可直接执行的Linux命令、问题解决方案，保障测试环境可复现、可追溯，适用于电商功能测试、数据库测试、日志排查等软件测试实训场景。

本文档用于记录本次Web注册功能测试项目的**测试环境搭建流程、软硬件环境、工具版本、部署操作命令**，保证测试环境可复现、可追溯，满足软件测试项目交付规范。

## 二、测试环境总体说明

本次搭建基于 **VMware + Ubuntu 镜像 + LAMP架构**，部署OpenCart 3.0.3.9开源电商系统，搭建完整可商用的后端测试环境。环境支持电商前台功能测试、后台管理测试、数据库数据校验、服务器日志排查，是软件测试项目标准实训环境。

本次项目为前端注册页面功能测试，采用**本地静态部署 + 浏览器测试**方式，无需后端服务器，环境轻量化、搭建快速，适合功能测试、用例设计、缺陷测试。

## 三、软硬件环境配置

|   |   |
|---|---|
|设备/软件项|配置参数/版本|
|宿主操作系统|Windows 10 / Windows 11|
|虚拟化软件|VMware Station Pro|
|虚拟机系统|Ubuntu 清华镜像|
|Web服务|Apache2|
|数据库|MySQL Server|
|运行环境|PHP 配套扩展|
|被测系统|OpenCart 3.0.3.9|

## 四、虚拟机与网络环境配置

### 4.1 虚拟化环境准备

1. 电脑应用商店下载安装 **VMware Station Pro**；

2. 导入 **清华镜像 Ubuntu** 系统，完成虚拟机初始化；

3. 打开虚拟机「Edit（虚拟网络编辑器）」，初始仅存在VMnet0，点击左下角「恢复默认设置」，自动生成VMnet0、VMnet1、VMnet8（NAT模式）网卡。

### 4.2 启用系统网络服务

1. 宿主电脑按下 `Win+R`，输入 `services.msc` 打开系统服务管理器；

2. 找到 **VMware NAT Service**、**VMware DHCP Service**，将服务状态从禁用改为**自动启动**并开启服务；

3. 确保DHCP、DNS服务正常启用，保障虚拟机自动获取IP、解析外网。

### 4.3 虚拟机网卡启动与IP获取

进入Ubuntu终端，依次执行以下命令，启用网卡并获取内网IP：

1. 启用ens33网卡

```bash
sudo ip link set ens33 up
```

2. 手动触发DHCP服务获取内网IP

```bash
sudo dhclient ens33
```

3. 查看网卡IP配置

```bash
ip a
```

**验证标准**：输出结果中出现 `inet 192.168.x.x` 内网IP，代表网络配置正常。

|软件名称|版本用途|
|---|---|
|Google Chrome|最新版，功能测试、页面渲染测试|
|VS Code|最新版，代码查看、本地运行|
|Live Server 插件|本地启动Web测试服务|
|Notepad++/记事本|文档编写、用例记录|

## 五、OpenCart电商系统搭建（LAMP环境）

### 5.1 外网连通性测试

执行ping命令测试虚拟机外网访问能力，确保网络无DNS解析故障：

```bash
ping www.baidu.com -c 4
```

**验证标准**：收到百度数据包回复，代表外网连通正常。

### 5.2 更新系统软件源

切换阿里云软件源并更新系统依赖，解决DNS解析错误、下载失败问题：

```bash
sudo apt update
```

### 5.3 安装LAMP全套依赖环境

一键安装Apache网页服务、MySQL数据库、PHP运行环境及OpenCart所需扩展：

```bash
sudo apt install apache2 mysql-server php php-mysql libapache2-mod-php php-curl php-gd php-mbstring php-xml php-zip unzip wget -y
```

### 5.4 验证核心服务状态

检查Apache、MySQL服务是否正常运行：

```bash
sudo systemctl status apache2
sudo systemctl status mysql
```

**验证标准**：两个服务均显示 `active (running)`，按下 `q` 退出状态查看页面。

### 5.5 下载并部署OpenCart源码

切换系统临时目录、下载源码、解压并部署到网页根目录，逐条执行以下命令：

```bash
# 切换至系统临时目录（重启自动清空，适合临时文件操作）
cd /tmp

# 从官方地址下载OpenCart3.0.3.9源码压缩包
wget https://github.com/opencart/opencart/releases/download/3.0.3.9/opencart-3.0.3.9.zip

# 解压源码压缩包
unzip opencart-3.0.3.9.zip

# 清空Apache默认网页旧文件
sudo rm -rf /var/www/html/*

# 将解压后的完整源码部署到网页运行根目录
sudo cp -r /tmp/upload/* /var/www/html/
```

### 5.6 设置网站目录权限（核心必做）

修改网站目录归属和权限，解决网页读写、缓存、文件上传报错：

```bash
# 将网站文件归属权交给Apache运行用户www-data
sudo chown -R www-data:www-data /var/www/html

# 设置网站目录标准安全权限755
sudo chmod -R 755 /var/www/html
```

### 5.7 生成系统配置文件

复制官方配置模板，生成系统正式生效的配置文件：

```bash
sudo cp /var/www/html/config-dist.php /var/www/html/config.php
sudo cp /var/www/html/admin/config-dist.php /var/www/html/admin/config.php
```

### 5.8 创建OpenCart专属数据库

登录MySQL数据库，创建专属数据库、用户并授权：

```bash
# 管理员身份登录MySQL
sudo mysql
```

依次执行以下SQL语句：

```sql
# 创建opencart数据库，设置中文兼容字符集
create database opencart_db default character set utf8mb4 collate utf8mb4_unicode_ci;

# 创建数据库专属用户及密码
create user 'opencart'@'localhost' identified by '123456';

# 授予用户数据库全部操作权限
grant all privileges on opencart_db.* to 'opencart'@'localhost';

# 刷新权限，立即生效
flush privileges;

# 退出MySQL命令行
exit;
```

### 步骤1：安装 VS Code

1. 官网下载 VS Code：https://code.visualstudio.com/

2. 默认路径安装，无需额外配置

3. 安装完成后启动软件

### 步骤2：安装 Live Server 运行插件

1. 左侧扩展商店搜索：**Live Server**

2. 安装 Ritwick Dey 官方插件

作用：开启本地Web服务，支持网页实时刷新、本地访问，模拟线上测试环境

### 步骤3：导入项目源码

1. 新建项目文件夹 `register-test-project`

2. 将注册页面 html、css、js 文件放入目录

3. VS Code 通过「打开文件夹」载入项目

### 步骤4：启动本地测试服务（核心操作）

方式一：图形化操作（常用）

右键项目内的 index.html → **Open with Live Server**

页面自动默认打开地址：`http://127.0.0.1:5500/index.html`

方式二：终端启动

打开 VS Code 终端，输入：

```Plain
# 安装全局live-server（首次需要）
npm install -g live-server

# 在项目目录启动测试服务
live-server
```

执行成功后自动弹出浏览器测试页面，环境搭建完成。

## 六、安装报错修复（配置文件不可写问题）

访问虚拟机页面时，出现 **config.php、admin/config.php Unwritable（不可写）** 报错，导致无法安装系统，解决方案如下：

单独为两个核心配置文件开放读写权限，仅针对文件授权，不改动目录全局权限：

```bash
sudo chmod 666 /var/www/html/config.php
sudo chmod 666 /var/www/html/admin/config.php
```

执行完成后，浏览器刷新安装页面，状态变为绿色 **Writable**，即可点击 `CONTINUE` 进入数据库配置页面。

**数据库配置参数**（固定填写）：

- 数据库主机：localhost
    
- 数据库名：opencart_db
    
- 数据库用户：opencart
    
- 数据库密码：123456
    

环境搭建成功需满足以下条件：

- 本地服务正常启动，无报错
    
- 注册页面完整渲染，所有输入框、按钮、单选框、复选框正常显示
    
- 页面可正常输入、点击、交互无卡顿
    
- 可正常开展正向/逆向功能测试
    

## 七、环境安全收尾（必做操作）

系统安装完成后，需执行安全加固操作，防止漏洞风险：

1. 删除安装向导文件夹（高危漏洞文件）

```bash
sudo rm -rf /var/www/html/install
```

2. 恢复配置文件安全权限（关闭全局读写权限）

```bash
sudo chmod 644 /var/www/html/config.php
sudo chmod 644 /var/www/html/admin/config.php
```

## 八、测试环境访问地址

环境部署完成后，可通过以下地址访问被测电商系统，开展功能测试：

- 前台商城首页：`http://192.168.119.128/`
    
- 后台管理页面：`http://192.168.119.128/admin`
    

## 九、环境启停命令汇总

1. 启动Web服务

```bash
sudo systemctl start apache2
```

2. 启动数据库服务

```bash
sudo systemctl start mysql
```

3. 重启Web服务

```bash
sudo systemctl restart apache2
```

4. 重启数据库服务

```bash
sudo systemctl restart mysql
```

## 十、测试环境适用场景

本OpenCart测试环境为**完整可运行的电商后台测试环境**，可支撑以下所有软件测试实训工作：

- 电商前台注册、登录、商品浏览、下单、支付流程功能测试
    
- 后台商品管理、订单管理、用户管理、权限管理功能测试
    
- MySQL数据库数据查询、校验、新增修改删除测试
    
- Apache服务器访问日志、错误日志排查与分析
    
- 环境兼容性、权限异常、配置异常缺陷测试