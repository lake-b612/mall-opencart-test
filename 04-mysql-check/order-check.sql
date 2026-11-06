-- order-check.sql
-- OpenCart 3.0.3.9 订单 / 支付 / 库存 校验脚本
-- 用途：下单后核对订单主表、明细、状态流转与库存扣减是否一致
-- 运行：mysql -u root -p opencart_db < order-check.sql

USE opencart_db;

-- 1) 最近订单主表
SELECT order_id, customer_id, total, order_status_id, date_added
FROM oc_order
ORDER BY order_id DESC
LIMIT 5;

-- 2) 订单明细
SELECT order_id, product_id, name, model, quantity, price, total
FROM oc_order_product
ORDER BY order_id DESC
LIMIT 10;

-- 3) 库存扣减校验：下单后 oc_product.quantity 应减少（此处以 product_id=42 为例）
SELECT product_id, model, quantity AS stock_now
FROM oc_product
WHERE product_id = 42;

-- 4) 订单状态流转（关联 oc_order_history）
SELECT oh.order_id, oh.order_status_id, oh.comment, oh.date_added
FROM oc_order_history oh
ORDER BY oh.order_id DESC
LIMIT 10;

-- 5) 订单-客户一致性
SELECT o.order_id, c.email, c.status
FROM oc_order o
JOIN oc_customer c ON o.customer_id = c.customer_id
ORDER BY o.order_id DESC
LIMIT 5;

-- 6) 期望断言（人工/自动化比对要点）
--    a) SUM(oc_order_product.total) 应与 oc_order 中对应商品金额一致（注意 total 含税费/运费，勿与纯商品求和直接划等号）
--    b) 下单后 oc_product.quantity 较下单前减少量 = SUM(oc_order_product.quantity)
--    c) oc_order.order_status_id 与 oc_order_history 最新一条状态一致
