-- user-register-check.sql
-- OpenCart 3.0.3.9 注册 / 登录 校验脚本
-- 用途：核对注册落库、密码加密存储、以及非法数据是否绕过校验入库（关联 BUG-001~007）
-- 运行：mysql -u root -p opencart_db < user-register-check.sql

USE opencart_db;

-- 1) 注册用户清单与状态（status=1 为正常启用）
SELECT customer_id, firstname, lastname, email, telephone, status
FROM oc_customer
ORDER BY customer_id DESC
LIMIT 10;

-- 2) 密码与 salt 存储校验（不应为明文）
SELECT customer_id,
       LENGTH(password) AS pwd_len,
       LENGTH(salt)     AS salt_len,
       LEFT(password, 4) AS pwd_prefix
FROM oc_customer
LIMIT 10;
-- 预期：pwd_len = 40（SHA1 十六进制），salt 有效长度（默认 9），且无明文密码

-- 3) 脏数据校验（关联 BUG-001~007）
--    名字/姓氏/电话含非法字符，或邮箱为非法格式 → 应被拦截不入库；若查到即说明缺陷存在
SELECT customer_id, firstname, lastname, telephone, email
FROM oc_customer
WHERE firstname REGEXP '[^一-龥a-zA-Z0-9 .-]'
   OR lastname  REGEXP '[^一-龥a-zA-Z0-9 .-]'
   OR telephone REGEXP '[^0-9+ -]'
   OR email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';
-- 返回行数 > 0 ⇒ 存在非法数据入库，对应 BUG-001~007

-- 4) 启用用户统计
SELECT COUNT(*) AS active_users
FROM oc_customer
WHERE status = 1;
