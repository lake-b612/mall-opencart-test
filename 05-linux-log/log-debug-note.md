# Ubuntu虚拟机 OpenCart 服务器排查记录
环境：Ubuntu22.04 + Apache2 + MySQL

## 1. 查看Apache网页错误日志
```bash
# 查看访问日志
sudo tail -f /var/log/apache2/access.log
# 查看错误日志，网页500报错优先看这里
sudo tail -f /var/log/apache2/error.log
