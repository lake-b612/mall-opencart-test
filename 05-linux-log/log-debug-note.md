# Ubuntu虚拟机 OpenCart 服务器排查记录
环境：Ubuntu22.04 + Apache2 + MySQL

## 1. 查看Apache网页错误日志
# 查看访问日志
sudo tail -f /var/log/apache2/access.log
# 查看错误日志，网页500报错优先看这里
sudo tail -f /var/log/apache2/error.log
2. 查看端口进程
# 查看80端口（apache）是否监听
ss -tulnp | grep 80
# 查看mysql端口3306
ss -tulnp | grep 3306
3. 文件权限问题
网页图片、静态资源 403 禁止访问，修改网站目录权限
sudo chown -R www-data:www-data /var/www/html/opencart
sudo chmod -R 755 /var/www/html/opencart
4. 服务启停
# 重启apache
sudo systemctl restart apache2
# 重启mysql
sudo systemctl restart mysql
实操现象记录
页面报 500 错误：查看 error.log，发现是目录权限不足，执行 chown 修复后页面恢复。
网页访问打不开：检查 apache 服务状态，确认 80 端口正常监听。
