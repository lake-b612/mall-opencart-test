-- 查询全部注册用户
SELECT customer_id, email, telephone, status FROM oc_customer;

-- 统计注册用户数量
SELECT count(*) AS user_count FROM oc_customer WHERE status = 1;

-- 查询指定邮箱用户
SELECT * FROM oc_customer WHERE email='test@demo.com';
