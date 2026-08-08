-- 查询全部订单
SELECT * FROM oc_order;

-- 根据订单号查询订单详情
SELECT * FROM oc_order WHERE order_id = 1;

-- 查询订单对应的商品明细
SELECT * FROM oc_order_product WHERE order_id = 1;

-- 查询商品库存
SELECT product_id, model, quantity FROM oc_product;
