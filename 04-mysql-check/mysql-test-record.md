# MySQL数据库测试记录
> OpenCart 数据库表前缀默认 `oc_`
> 虚拟机终端：sudo mysql输入密码
> mysql> use opencart_db;

## 一、前台（用户端）数据库测试

### 测试场景1：用户注册
执行注册操作之后，执行 sql 查询 `oc_customer`，确认：
1. 用户信息完整入库
2. 密码为加密存储，不存储明文密码
3. status 状态字段为 1 代表正常启用

```sql
-- 查询全部注册用户（注意 password/salt 不可明文）
SELECT customer_id, email, telephone, status, password, salt FROM oc_customer;
-- 统计启用用户
SELECT count(*) AS user_count FROM oc_customer WHERE status = 1;
-- 指定邮箱查询
SELECT * FROM oc_customer WHERE email='test@demo.com';
-- 判定加密方式
SELECT customer_id, LENGTH(password) AS pwd_len, LEFT(password,4) AS pwd_prefix,
       LENGTH(salt) AS salt_len FROM oc_customer;
```
记录：确认成功，与预期相符。
![]\(../img/Pasted image 20260817185411.png\)

### 测试场景2：用户注册字段校验（关联 BUG-001~007）
注册/修改账户时输入非法字符或非法邮箱格式，确认数据库是否落入脏数据：
- 名字/姓氏/电话/密码含非法字符 → 预期应被拦截、不入库；实际（BUG-001~004、BUG-005、BUG-007）非法字符被接受入库
- 修改邮箱为非法格式（如 `abc123`）→ 预期拦截；实际（BUG-006）非法邮箱入库

```sql
-- 检查是否落入非法字符 / 非法邮箱格式的脏数据（oc_customer）
SELECT customer_id, firstname, lastname, telephone, email
FROM oc_customer
WHERE firstname REGEXP '[^一-龥a-zA-Z0-9 .-]'
   OR lastname  REGEXP '[^一-龥a-zA-Z0-9 .-]'
   OR telephone REGEXP '[^0-9+ -]'
   OR email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$';

-- ⚠️ 补充：地址簿是第二个入库入口，同样会落脏数据，必须一并检查
SELECT address_id, customer_id, firstname, lastname, company, address_1, city, postcode
FROM oc_address
WHERE firstname REGEXP '[^一-龥a-zA-Z0-9 .-]'
   OR lastname  REGEXP '[^一-龥a-zA-Z0-9 .-]'
   OR city      REGEXP '[^一-龥a-zA-Z0-9 .-]';
```
记录（关联缺陷）：BUG-001 / BUG-002 / BUG-003 / BUG-005 / BUG-006 / BUG-007（名字/姓氏/电话/邮箱 字段校验缺失，脏数据可入库）；另 BUG-008（生日自定义字段未校验未来日期）。注：原 BUG-004（密码非法字符）已撤销——OpenCart 密码仅校验长度 4–20，接受特殊字符属预期行为，非缺陷。
![]\(../img/Pasted image 20260821163608.png\)

### 测试场景3：用户登录校验
执行登录后核对：
1. 正确账号+密码可登录；错误密码返回失败（不暴露账号是否存在）
2. `status=0` 的禁用账号无法登录

```sql
SELECT customer_id, email, status, (LENGTH(password) > 0) AS has_hash FROM oc_customer WHERE email='test@demo.com';
-- 登录行为审计（配合 oc_customer_activity / oc_customer_login 交叉验证）
SELECT * FROM oc_customer_activity WHERE customer_id = 1 ORDER BY date_added DESC LIMIT 20;
SELECT * FROM oc_customer_login WHERE email = 'test@demo.com' ORDER BY date_added DESC LIMIT 10;
```
记录：
![]\(../img/Pasted image 20260821164056.png\)

### 测试场景4：修改账户信息
已登录用户修改姓名/电话/邮箱后，确认 `oc_customer` 对应字段更新，且密码修改只更新哈希不回写明文。
**同时必须核对 `oc_address`** —— 地址簿是独立表，修改资料会同步写入。

```sql
SELECT customer_id, firstname, lastname, telephone, email, password FROM oc_customer WHERE customer_id=1;
-- 地址簿同步核验
SELECT address_id, customer_id, firstname, lastname, address_1, city, date_added
FROM oc_address WHERE customer_id = 1;
```
记录：
修改前：
![]\(../img/Pasted image 20260821164350.png\)
修改后：
![]\(../img/Pasted image 20260821164527.png\)

### 测试场景5：商品收藏（oc_customer_wishlist）
前台点击「加入收藏」后，确认：
1. `oc_customer_wishlist` 出现该 customer-product 记录
2. 取消收藏后该记录被删除
3. 顶部收藏计数与表中该 customer 的记录数一致

```sql
SELECT * FROM oc_customer_wishlist WHERE customer_id=1;
SELECT count(*) AS wish_count FROM oc_customer_wishlist WHERE customer_id=1;
```
记录：
收藏前：
![]\(../img/Pasted image 20260821164951.png\)
![]\(../img/Pasted image 20260821164846.png\)
收藏后
![]\(../img/Pasted image 20260821165027.png\)
![]\(../img/Pasted image 20260821165047.png\)
取消一个收藏后：
![]\(../img/Pasted image 20260821165229.png\)
![]\(../img/Pasted image 20260821165208.png\)

### 测试场景6：购物车（oc_cart）

验证点：
1. 未登录加购后，`oc_cart` 出现 `customer_id = 0` + 当前 `session_id` 的记录
2. 登录后，上述记录的 `customer_id` 变为当前用户 ID（session_id 不变）
3. 修改数量、删除商品后 `oc_cart` 同步更新
4. 换 session 后残留的 `customer_id = 0` 孤儿记录（可作为脏数据缺陷提报）

```sql
-- 1) 未登录加购后：确认已落库
SELECT cart_id, api_id, customer_id, session_id, product_id, `option`, quantity, date_added
FROM oc_cart WHERE customer_id = 0;

-- 2) 登录后：确认记录挂到该用户
SELECT cart_id, customer_id, session_id, product_id, `option`, quantity
FROM oc_cart WHERE customer_id = 1;

-- 3) 单个商品数量
SELECT product_id, quantity FROM oc_cart WHERE customer_id = 1 AND product_id = 43;

-- 4) 孤儿数据（未登录购物车残留）
SELECT session_id, COUNT(*) AS items, MIN(date_added) AS first_added, MAX(date_added) AS last_added
FROM oc_cart WHERE customer_id = 0
GROUP BY session_id ORDER BY last_added DESC;
```

记录：
未登录
![]\(../img/Pasted image 20260831195835.png\)
登录后：
![]\(../img/Pasted image 20260831195957.png\)
单个商品数量：
![]\(../img/Pasted image 20260831200029.png\)
未登录购物车残留
![]\(../img/Pasted image 20260831200059.png\)

### 测试场景7：商品浏览 / 详情（oc_product 系列）
进入商品详情页后核对：
1. `oc_product` 中该商品 `status=1`、价格与库存正确
2. 规格项（颜色/尺寸）与详情页可选规格一致
3. 商品多图、特价、属性、分类归属

```sql
-- 基础信息（注意：需同时校验 oc_product_to_store，多店铺下未绑定店铺则前台不可见）
SELECT p.product_id, p.model, p.quantity, p.price, p.status, p.viewed,
       pd.language_id, pd.name
FROM oc_product p
LEFT JOIN oc_product_description pd ON p.product_id = pd.product_id AND pd.language_id = 1
WHERE p.product_id = 28;

-- ⚠️ oc_product_option 只有 option_id + value(JSON) + required，看不到"颜色/尺寸"名称
--    必须 JOIN 描述表才能验证「规格项与详情页一致」
SELECT po.product_option_id, od.name AS option_name, ovd.name AS value_name,
       pov.quantity, pov.price, pov.price_prefix, po.required
FROM oc_product_option po
LEFT JOIN oc_option_description od
       ON po.option_id = od.option_id AND od.language_id = 1
LEFT JOIN oc_product_option_value pov ON po.product_option_id = pov.product_option_id
LEFT JOIN oc_option_value_description ovd
       ON pov.option_value_id = ovd.option_value_id AND ovd.language_id = 1
WHERE po.product_id = 28;

-- 商品多图 / 特价 / 分类归属
SELECT * FROM oc_product_image WHERE product_id = 28 ORDER BY sort_order;
SELECT * FROM oc_product_special WHERE product_id = 28;
SELECT * FROM oc_product_to_category WHERE product_id = 28;
```
记录：
![]\(../img/Pasted image 20260821175501.png\)
![]\(../img/Pasted image 20260821175814.png\)

### 测试场景8：用户下单（oc_order 系列）
下单成功之后校验：
1. `oc_order` 生成一条新订单记录
2. `oc_order_product` 存在订单对应的商品记录
3. `oc_product` 表对应商品的 `quantity` 库存数值减少
4. **订单金额构成正确**（`oc_order_total`，核心校验项，原记录遗漏）
5. **订单商品规格快照正确**（`oc_order_option`）

```sql
-- 查询全部订单
SELECT order_id, customer_id, order_status_id, total, currency_code, currency_value, date_added
FROM oc_order ORDER BY order_id DESC LIMIT 50;
-- 根据订单号查询订单详情
SELECT * FROM oc_order WHERE order_id = 1;
-- 查询订单对应的商品明细
SELECT * FROM oc_order_product WHERE order_id = 1;
-- 订单商品规格快照
SELECT * FROM oc_order_option WHERE order_id = 1;
-- 查询商品库存
SELECT product_id, model, quantity FROM oc_product ORDER BY product_id LIMIT 50;

-- ⚠️ 补充：订单金额构成（code 区分 sub_total / shipping / coupon / tax / total）
-- 校验点：sub_total = Σ(order_product.total)，total = sub_total + shipping + tax - coupon
SELECT order_id, code, title, value, sort_order
FROM oc_order_total WHERE order_id = 1 ORDER BY sort_order;
```
记录：
![]\(../img/Pasted image 20260817185552.png\)
![]\(../img/Pasted image 20260817185932.png\)
![]\(../img/Pasted image 20260817190017.png\)

### 测试场景9：商品搜索（oc_product_description）
搜索关键词后核对：
1. 精准搜索、模糊搜索均能命中 `oc_product_description.name` / `oc_product.model` / `tag`
2. 无匹配时返回空，不报错
3. 已下架商品（`status=0`）不出现在搜索结果中

```sql
-- 模拟搜索命中范围（对比前台返回条数）
SELECT p.product_id, p.model, p.status, pd.name
FROM oc_product p
LEFT JOIN oc_product_description pd ON p.product_id = pd.product_id AND pd.language_id = 1
WHERE p.status = 1
  AND (pd.name LIKE '%关键词%' OR p.model LIKE '%关键词%' OR pd.tag LIKE '%关键词%');

-- 特殊字符容错：确认无脏数据写入
SELECT product_id, model FROM oc_product WHERE model REGEXP '[<>]';
```
记录：
![]\(../img/Pasted image 20260831164415.png\)
### 测试场景10：退换货申请（oc_return 系列）
前台提交退换货申请，确认：
1. `oc_return` 新增记录，关联 `order_id`/`product_id`
2. 后台审核通过/拒绝后 `oc_return.return_status_id` 更新
3. **审核流水 `oc_return_history` 每改一次状态插入一条**

> ⚠️ 预期修正：OpenCart 审核退换货**不会自动回退 `oc_product.quantity`，也不产生退款金额记录**，
> 库存/金额回退需后台人工处理。不要把"未回退"当作缺陷提报。

```sql
SELECT r.return_id, r.order_id, r.product_id, r.quantity,
       r.return_reason_id, r.return_action_id, r.return_status_id,
       rs.name AS status_name, r.date_added, r.date_modified
FROM oc_return r
LEFT JOIN oc_return_status rs
       ON r.return_status_id = rs.return_status_id AND rs.language_id = 1
WHERE r.order_id = 1;

-- 审核流水
SELECT rh.return_status_id, rh.notify, rh.comment, rh.date_added
FROM oc_return_history rh WHERE rh.return_id = 1 ORDER BY rh.date_added;

-- 状态 / 原因 / 处理动作字典
SELECT * FROM oc_return_status WHERE language_id = 1;
SELECT * FROM oc_return_reason WHERE language_id = 1;
SELECT * FROM oc_return_action  WHERE language_id = 1;
```
记录：
新增一条记录：
![]\(../img/Pasted image 20260822164909.png\)
 后台审核通过：
 ![]\(../img/Pasted image 20260822165024.png\)
 退还订单完成：
![]\(../img/Pasted image 20260822165056.png\)

### 测试场景11：首页推荐商品与品牌轮播
核对首页推荐位与品牌轮播的数据来源：
1. 推荐商品（Featured 模块）配置落在 `oc_module`（`code='featured'`，`setting` 为 JSON）
2. 合作品牌轮播来自 `oc_manufacturer`，多店铺需绑定 `oc_manufacturer_to_store`
3. 推荐商品价格/库存与 `oc_product` 一致

```sql
-- 推荐模块配置
SELECT module_id, name, code, setting FROM oc_module WHERE code = 'featured';

-- 品牌列表 + 店铺绑定
SELECT m.manufacturer_id, m.name, m.sort_order, m2s.store_id
FROM oc_manufacturer m
LEFT JOIN oc_manufacturer_to_store m2s ON m.manufacturer_id = m2s.manufacturer_id
ORDER BY m.sort_order;

-- 首页 Banner 与布局绑定
SELECT * FROM oc_layout_route WHERE route = 'common/home';
```
记录：
![]\(../img/Pasted image 20260831164514.png\)

![]\(../img/Pasted image 20260831164530.png\)

![]\(../img/Pasted image 20260831164543.png\)
### 测试场景12：优惠券 / 礼品券 
1. 使用优惠券 → `oc_coupon_history` 记录使用流水；**`oc_coupon` 本身没有 `used` 字段**
2. `oc_coupon.uses_total` / `uses_customer` 是**配置上限，不会自增**；已用次数需 `COUNT(oc_coupon_history)`
3. 购买/使用礼品券 → `oc_voucher` 生成/核销记录，流水在 `oc_voucher_history`

```sql
-- 优惠券配置 + 已用次数
SELECT c.coupon_id, c.name, c.code, c.type, c.discount, c.total,
       c.date_start, c.date_end, c.uses_total, c.uses_customer, c.status,
       (c.date_end >= CURDATE()) AS not_expired,
       COUNT(ch.coupon_history_id) AS used_count
FROM oc_coupon c
LEFT JOIN oc_coupon_history ch ON c.coupon_id = ch.coupon_id
WHERE c.code IN ('1111','2222','3333')
GROUP BY c.coupon_id;

-- 使用流水（谁、哪笔订单、抵了多少）
SELECT ch.*, o.order_status_id
FROM oc_coupon_history ch
LEFT JOIN oc_order o ON ch.order_id = o.order_id
WHERE ch.coupon_id IN (SELECT coupon_id FROM oc_coupon WHERE code IN ('1111','2222'));

-- 优惠券适用范围（限定商品 / 分类）
SELECT * FROM oc_coupon_product  WHERE coupon_id IN (SELECT coupon_id FROM oc_coupon WHERE code IN ('1111','2222'));
SELECT * FROM oc_coupon_category WHERE coupon_id IN (SELECT coupon_id FROM oc_coupon WHERE code IN ('1111','2222'));

-- 礼品券：主表 + 主题 + 核销流水 + 订单关联
SELECT v.voucher_id, v.order_id, v.code, v.to_name, v.to_email, v.amount, v.status,
       vt.description AS theme
FROM oc_voucher v
LEFT JOIN oc_voucher_theme vt ON v.voucher_theme_id = vt.voucher_theme_id
WHERE v.code = '666';
SELECT * FROM oc_voucher_history WHERE voucher_id = 1;
SELECT * FROM oc_order_voucher WHERE order_id = 1;
```
记录：
![]\(../img/Pasted image 20260822170025.png\)

![]\(../img/Pasted image 20260822170040.png\)

### 测试场景13：商品评价（oc_review）
提交评价后确认：
1. `oc_review` 新增记录，初始 `status=0`（待审核）。**注意表名是 `oc_review`，不是 `oc_product_review`**
2. 后台审核通过 `status=1` 后前台才展示
3. 评价数统计与 `oc_review` 审核通过的条数一致

```sql
SELECT review_id, product_id, customer_id, author, rating, status, date_added
FROM oc_review WHERE product_id = 47 ORDER BY review_id DESC;
SELECT count(*) AS approved FROM oc_review WHERE product_id = 47 AND status = 1;
-- 待审核 / 已通过分组统计
SELECT status, COUNT(*) AS cnt FROM oc_review GROUP BY status;
```
记录：
![]\(../img/Pasted image 20260831164630.png\)

![]\(../img/Pasted image 20260831164645.png\)
### 测试场景14：货币切换（oc_currency）
切换货币后，确认 `oc_currency` 中目标货币 `value`（汇率）生效，前台价格按汇率换算展示。
同时需确认 `oc_setting` 的 `config_currency` 与当前选择一致。

```sql
SELECT currency_id, title, code, symbol_left, symbol_right, decimal_place, value, status
FROM oc_currency;

-- 生效依赖：当前默认货币
SELECT `key`, `value` FROM oc_setting
WHERE store_id = 0 AND code = 'config' AND `key` IN ('config_currency','config_currency_auto');

-- 换算边界：特价与客户组折扣是否同步换算
SELECT product_id, customer_group_id, price FROM oc_product_special  WHERE product_id = 47;
SELECT product_id, customer_group_id, price FROM oc_product_discount WHERE product_id = 47;
```
记录：
![]\(../img/Pasted image 20260822171421.png\)
![]\(../img/Pasted image 20260822171446.png\)![]\(../img/Pasted image 20260822171505.png\)

### 测试场景15：资讯信息（oc_information）
后台新增/编辑资讯文章后，确认 `oc_information` 写入/更新，`status` 控制前台可见性；底部 Information 链接可访问。
**标题与正文在 `oc_information_description`**；**`bottom=1` 才会在底部导航显示**。

```sql
SELECT i.information_id, i.bottom, i.sort_order, i.status,
       id.language_id, id.title, LEFT(id.description, 120) AS desc_head
FROM oc_information i
LEFT JOIN oc_information_description id ON i.information_id = id.information_id
ORDER BY i.sort_order;

-- 底部链接位校验
SELECT information_id, bottom, sort_order, status FROM oc_information WHERE bottom = 1;
```
记录：
![]\(../img/Pasted image 20260831164738.png\)

![]\(../img/Pasted image 20260831164752.png\)
### 测试场景16：首页 Banner / SEO（oc_banner、oc_seo_url）
1. 后台配置轮播 → `oc_banner` 写开关与名称，**图片/链接/标题在 `oc_banner_image`**
2. 开启 SEO 伪静态 → `oc_seo_url` 生成关键词路由

```sql
SELECT b.banner_id, b.name, b.status,
       bi.language_id, bi.title, bi.link, bi.image, bi.sort_order
FROM oc_banner b
LEFT JOIN oc_banner_image bi ON b.banner_id = bi.banner_id
ORDER BY b.banner_id, bi.sort_order;

-- SEO 路由（多语言多店铺需限定）
SELECT seo_url_id, store_id, language_id, query, keyword
FROM oc_seo_url WHERE query LIKE 'product_id=%';
```
记录：
![]\(../img/Pasted image 20260831164935.png\)

![]\(../img/Pasted image 20260831164946.png\)
### 测试场景17：商品分类 / 品牌（oc_category 系列、oc_manufacturer）
前台分类导航与品牌页，确认：
1. 分类名在 `oc_category_description`，**顶部导航靠 `top=1`**
2. 多级归属靠 **`oc_category_path`**（`level` 字段），只查 `parent_id` 验证不了二级分类
3. 商品挂靠靠 `oc_product_to_category`
4. 分类需绑定店铺 `oc_category_to_store`

```sql
SELECT c.category_id, c.parent_id, c.top, c.column, c.sort_order, c.status,
       cd.language_id, cd.name
FROM oc_category c
LEFT JOIN oc_category_description cd ON c.category_id = cd.category_id AND cd.language_id = 1
ORDER BY c.parent_id, c.sort_order;

-- 层级关系
SELECT * FROM oc_category_path ORDER BY category_id, level;
-- 分类下的商品数量（对比前台列表条数）
SELECT p2c.category_id, COUNT(*) AS product_cnt
FROM oc_product_to_category p2c
JOIN oc_product p ON p2c.product_id = p.product_id AND p.status = 1
GROUP BY p2c.category_id;

SELECT manufacturer_id, name, sort_order FROM oc_manufacturer ORDER BY sort_order;
```
记录：
![]\(../img/Pasted image 20260831173728.png\)

![]\(../img/Pasted image 20260831173748.png\)

![]\(../img/Pasted image 20260831173803.png\)

![]\(../img/Pasted image 20260831173814.png\)
---

## 二、后台管理端（后端）数据库测试

### 测试场景18：客户管理 / 分组 / 自定义字段 / 注册审核
（oc_customer、oc_customer_group、oc_custom_field）
1. 后台新增客户 → `oc_customer` 写入，可指定 `customer_group_id`
2. 新增客户分组 → `oc_customer_group` 写入，折扣规则生效
3. 自定义注册字段填写 → **定义查 `oc_custom_field`，填报值序列化存在 `oc_customer.custom_field`（JSON）**
4. 注册审核 → `oc_customer_approval`（`type='register'`），审核通过后记录删除

```sql
SELECT customer_id, customer_group_id, status, ip, date_added FROM oc_customer;

-- 分组与折扣（风险点4）
SELECT cg.customer_group_id, cgd.name, cg.sort_order
FROM oc_customer_group cg
LEFT JOIN oc_customer_group_description cgd
       ON cg.customer_group_id = cgd.customer_group_id AND cgd.language_id = 1;

-- ⚠️ 原表名 oc_customer_field 不存在，正确为 oc_custom_field
SELECT cf.custom_field_id, cfd.name, cf.type, cf.location, cf.status, cf.sort_order
FROM oc_custom_field cf
LEFT JOIN oc_custom_field_description cfd
       ON cf.custom_field_id = cfd.custom_field_id AND cfd.language_id = 1;

-- 自定义字段可选项
SELECT cfv.custom_field_id, cfvd.name, cfv.sort_order
FROM oc_custom_field_value cfv
LEFT JOIN oc_custom_field_value_description cfvd
       ON cfv.custom_field_value_id = cfvd.custom_field_value_id AND cfvd.language_id = 1;

-- 填报内容落在 oc_customer.custom_field（JSON）
SELECT customer_id, custom_field FROM oc_customer
WHERE custom_field IS NOT NULL AND custom_field <> '' AND custom_field <> '[]';

-- 注册审核（需求核心功能，原记录遗漏）
SELECT * FROM oc_customer_approval;
SELECT customer_id, email, status FROM oc_customer WHERE status = 0;
```
记录：
![]\(../img/Pasted image 20260831204540.png\)
![]\(../img/Pasted image 20260831204602.png\)
![]\(../img/Pasted image 20260831204626.png\)
![]\(../img/Pasted image 20260831204648.png\)
![]\(../img/Pasted image 20260831204649.png\)
### 测试场景19：商品目录管理
（oc_product、oc_category、oc_product_option、oc_attribute、oc_filter、oc_download）
1. 后台新增/编辑商品 → `oc_product` 写入；上下架切换 `status`
2. 新增分类 → `oc_category` 写入，`parent_id` 正确
3. 配置规格 → `oc_product_option` / `oc_product_option_value` 写入
4. 属性、筛选分组、虚拟附件（原记录完全未覆盖）

```sql
SELECT p.product_id, p.model, p.quantity, p.price, p.status, pd.name
FROM oc_product p
LEFT JOIN oc_product_description pd ON p.product_id = pd.product_id AND pd.language_id = 1
ORDER BY p.product_id LIMIT 50;

SELECT c.category_id, c.parent_id, cd.name FROM oc_category c
LEFT JOIN oc_category_description cd ON c.category_id = cd.category_id AND cd.language_id = 1
WHERE c.parent_id = 0;

-- 规格（含名称与加价）
SELECT po.product_option_id, od.name AS option_name, ovd.name AS value_name,
       pov.quantity, pov.price, pov.price_prefix, po.required
FROM oc_product_option po
LEFT JOIN oc_option_description od ON po.option_id = od.option_id AND od.language_id = 1
LEFT JOIN oc_product_option_value pov ON po.product_option_id = pov.product_option_id
LEFT JOIN oc_option_value_description ovd
       ON pov.option_value_id = ovd.option_value_id AND ovd.language_id = 1
WHERE po.product_id = 47;

-- 属性组 / 属性
SELECT ag.attribute_group_id, agd.name AS group_name, a.attribute_id, ad.name AS attr_name
FROM oc_attribute a
LEFT JOIN oc_attribute_description ad ON a.attribute_id = ad.attribute_id AND ad.language_id = 1
LEFT JOIN oc_attribute_group ag ON a.attribute_group_id = ag.attribute_group_id
LEFT JOIN oc_attribute_group_description agd
       ON ag.attribute_group_id = agd.attribute_group_id AND agd.language_id = 1;

-- 筛选分组 / 筛选项 / 商品绑定
SELECT fg.filter_group_id, fgd.name AS group_name, f.filter_id, fd.name AS filter_name
FROM oc_filter f
LEFT JOIN oc_filter_description fd ON f.filter_id = fd.filter_id AND fd.language_id = 1
LEFT JOIN oc_filter_group fg ON f.filter_group_id = fg.filter_group_id
LEFT JOIN oc_filter_group_description fgd
       ON fg.filter_group_id = fgd.filter_group_id AND fgd.language_id = 1;

-- 虚拟商品附件
SELECT d.download_id, dd.name, d.filename, d.mask
FROM oc_download d
LEFT JOIN oc_download_description dd ON d.download_id = dd.download_id AND dd.language_id = 1;
SELECT * FROM oc_product_to_download;
```
记录：
![]\(../img/Pasted image 20260831204959.png\)
![]\(../img/Pasted image 20260831205029.png\)
![]\(../img/Pasted image 20260831205045.png\)
![]\(../img/Pasted image 20260831205112.png\)


### 测试场景20：系统设置 / 后台用户 / API 账号
（oc_setting、oc_user、oc_api）
1. 修改商城设置（店名/邮箱/汇率等）→ `oc_setting` 更新。**需限定 `store_id` 与 `code`，否则多店铺下会重复**
2. 后台用户管理 → `oc_user` 增删改，密码哈希存储；权限在 `oc_user_group`
3. API 账号 → `oc_api` / `oc_api_ip` / `oc_api_session`

```sql
-- ⚠️ 需限定 store_id 与 code；serialized=1 时 value 为序列化串
SELECT store_id, code, `key`, `value`, serialized FROM oc_setting
WHERE store_id = 0 AND code = 'config'
  AND `key` IN ('config_name','config_email','config_currency','config_language','config_review_status');

-- 管理员与权限
SELECT u.user_id, u.username, u.user_group_id, ug.name AS group_name, u.status, u.date_added
FROM oc_user u LEFT JOIN oc_user_group ug ON u.user_group_id = ug.user_group_id;

-- API 账号（接口鉴权前置，06-api-test 依赖）
SELECT api_id, username, status, date_added FROM oc_api;
SELECT api_id, ip FROM oc_api_ip;
SELECT api_session_id, api_id, session_id, ip, date_added
FROM oc_api_session ORDER BY date_added DESC LIMIT 10;
```
记录：
![]\(../img/Pasted image 20260831205459.png\)
![]\(../img/Pasted image 20260831205511.png\)
![]\(../img/Pasted image 20260831205532.png\)
![]\(../img/Pasted image 20260831205610.png\)
### 测试场景21：统计报表 
产生订单、浏览商品后，确认：
1. `oc_statistics` 统计值随业务更新（**注意复数 s，不是 `oc_statistic`**）
2. `oc_customer_online` 记录在线访客，需 JOIN `oc_customer` 才看得到是谁
3. 报表页数据与此两张表统计结果一致（页面 ↔ 数据库双向核对）
4. **商品浏览量记在 `oc_product.viewed`，不在 `oc_statistics`**

```sql
SELECT * FROM oc_statistics;

SELECT co.customer_id, c.firstname, c.lastname, co.ip, co.url, co.referer, co.date_added
FROM oc_customer_online co
LEFT JOIN oc_customer c ON co.customer_id = c.customer_id
ORDER BY co.date_added DESC LIMIT 20;

-- 商品浏览量
SELECT product_id, model, viewed FROM oc_product ORDER BY viewed DESC LIMIT 10;

-- 页面与数据库双向核对：订单数与销售额
SELECT COUNT(*) AS order_cnt, SUM(total) AS sale_total FROM oc_order;
SELECT COUNT(*) AS customer_cnt FROM oc_customer;
```
记录：
![]\(../img/Pasted image 20260831205702.png\)
### 测试场景22：数据库备份
系统维护执行备份，确认：
1. 备份文件正常生成
2. 还原后表结构与业务数据一致（可用 `CHECKSUM TABLE` 抽检）

```sql
CHECKSUM TABLE oc_customer, oc_order, oc_product, oc_order_product, oc_review;
```
记录：
![]\(../img/Pasted image 20260831205730.png\)

### 测试场景23：页面布局 / 主题 / 语言编辑器
（oc_layout*、oc_theme、oc_language、oc_translation）
1. 布局调整 → `oc_layout` / `oc_layout_module` / `oc_layout_route`
2. 主题切换 → `oc_theme`
3. 修改文案 → `oc_translation`（语言编辑器改的文案存在这里）

```sql
SELECT * FROM oc_layout;
SELECT lm.layout_id, lm.code, lm.position, lm.sort_order
FROM oc_layout_module lm ORDER BY lm.layout_id, lm.position;
SELECT * FROM oc_layout_route;

SELECT theme_id, store_id, theme, route, code FROM oc_theme;
SELECT language_id, name, code, sort_order, status FROM oc_language;

-- 语言编辑器改过的文案（key 为原语言文件路径，value 为改写后的内容）
SELECT translation_id, store_id, language_id, route, `key`, `value`
FROM oc_translation LIMIT 50;
```
记录：
![]\(../img/Pasted image 20260831210217.png\)
### 测试场景24：销售 — 订单状态流转与发货
（oc_order_history、oc_order_status）
1. 后台修改订单状态 → `oc_order_history` 插入一条流水
2. 前台客户订单状态同步（`oc_order.order_status_id` 与最新一条 history 一致）
3. 状态字典在 `oc_order_status`（带 `language_id`）

```sql
SELECT oh.order_history_id, oh.order_status_id, os.name AS status_name,
       oh.notify, oh.comment, oh.date_added
FROM oc_order_history oh
LEFT JOIN oc_order_status os
       ON oh.order_status_id = os.order_status_id AND os.language_id = 1
WHERE oh.order_id = 1 ORDER BY oh.date_added;

-- 一致性核对：oc_order.order_status_id 应等于最新一条 history
SELECT o.order_id, o.order_status_id AS current_status,
       (SELECT order_status_id FROM oc_order_history h
         WHERE h.order_id = o.order_id ORDER BY date_added DESC LIMIT 1) AS latest_history_status
FROM oc_order o;

SELECT order_status_id, language_id, name FROM oc_order_status ORDER BY order_status_id, language_id;
```
记录：
![]\(../img/Pasted image 20260831210259.png\)

### 测试场景25：Dashboard 仪表盘数据一致性 
页面统计数字与数据库聚合结果双向核对。

```sql
SELECT COUNT(*) AS total_orders FROM oc_order;                              -- 总订单数
SELECT SUM(total) AS total_sales FROM oc_order;                             -- 总销售额
SELECT COUNT(*) AS total_customers FROM oc_customer;                        -- 客户总数
SELECT COUNT(*) AS online_count FROM oc_customer_online;                     -- 在线人数
-- 订单状态占比
SELECT os.name AS status_name, COUNT(*) AS cnt,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM oc_order), 2) AS pct
FROM oc_order o
LEFT JOIN oc_order_status os
       ON o.order_status_id = os.order_status_id AND os.language_id = 1
GROUP BY o.order_status_id;
-- 按时间维度（销售图表）
SELECT DATE(date_added) AS d, COUNT(*) AS order_cnt, SUM(total) AS amount
FROM oc_order GROUP BY DATE(date_added) ORDER BY d DESC LIMIT 30;
```
记录：
![]\(../img/Pasted image 20260831210558.png\)
---

## 三、异常 / 缺陷关联校验

| 校验项 | 预期 | 关联缺陷 | 记录 |
| --- | --- | --- | --- |
| 提交非法格式邮箱，观察 `oc_customer` 是否写入脏数据 | 拦截、不入库 | BUG-002（注册邮箱）、BUG-006（修改邮箱） | 实际非法邮箱入库 ✗ |
| 用户模块字段（名字/姓氏/电话/密码）输入非法字符 | 拦截、不入库 | BUG-001/002/003/005/007 | 实际非法字符入库 ✗ |
| 地址簿入口（`oc_address`）脏数据检查 | 拦截、不入库 | 同上（补充检查点） | 待执行，见场景2 |
| 重复下单，核对 `oc_product.quantity` 扣减逻辑（超卖） | 每次下单 -1，库存为 0 禁止下单 | 原 BUG-003（超卖） | 本次用例集无对应失败，需补充负数/并发用例复测 |
| 购物车输入负数数量并保存 | 拦截负数、提示合法数字 | 原 BUG-001（购物车负数） | 当前用例集无失败记录，需补充用例复测 |
| 未登录购物车换 session 后残留 `oc_cart` 孤儿数据 | 应清理或合并 | 新增检查点（见场景6-4） | 待执行 |
| 退换货审核通过后库存/金额未回退 | OpenCart 设计为人工处理，**非缺陷** | 预期已修正，勿误报 | 见场景10 说明 |
| 修改账户信息地址为空提交 | 提示地址不能为空、拦截 | 用例设计修正（FE-USR-083/084/096/098）非缺陷 | 系统行为正确，修正用例即可 |

