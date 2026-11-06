-- schema-check.sql
-- OpenCart 3.0.3.9 数据库预检脚本
-- 用途：核对表名是否存在、统计各表行数、识别空表、验证 P0 表名订正
-- 运行：mysql -u root -p opencart_db < schema-check.sql

USE opencart_db;

-- 1) 全部 oc_ 表及近似行数（InnoDB 下 TABLE_ROWS 为估算值，仅作概览）
SELECT table_name, table_rows
FROM information_schema.tables
WHERE table_schema = 'opencart_db' AND table_name LIKE 'oc_%'
ORDER BY table_name;

-- 2) P0 校验：被需求/用例误写的表名在库中必须不存在（应返回 0 行）
SELECT 'oc_product_review'  AS wrong_name, COUNT(*) AS exist FROM oc_product_review;
SELECT 'oc_statistic'      AS wrong_name, COUNT(*) AS exist FROM oc_statistic;
SELECT 'oc_customer_field' AS wrong_name, COUNT(*) AS exist FROM oc_customer_field;

-- 3) P0 校验：正确表名必须存在（应各返回 1 行）
SELECT 'oc_review'       AS correct_name, COUNT(*) AS exist FROM oc_review;
SELECT 'oc_statistics'   AS correct_name, COUNT(*) AS exist FROM oc_statistics;
SELECT 'oc_custom_field' AS correct_name, COUNT(*) AS exist FROM oc_custom_field;

-- 4) 精确逐表行数（存储过程一次性输出真实 COUNT，并以临时表汇总空表数）
DROP PROCEDURE IF EXISTS opencart_rowcount;
DELIMITER $$
CREATE PROCEDURE opencart_rowcount()
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE t VARCHAR(64);
  DECLARE cur CURSOR FOR
    SELECT table_name FROM information_schema.tables
    WHERE table_schema='opencart_db' AND table_name LIKE 'oc_%';
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
  DROP TEMPORARY TABLE IF EXISTS _rc;
  CREATE TEMPORARY TABLE _rc (tname VARCHAR(64), rows BIGINT);
  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO t;
    IF done THEN LEAVE read_loop; END IF;
    SET @s = CONCAT('INSERT INTO _rc SELECT ''', t, ''', COUNT(*) FROM `', t, '`');
    PREPARE stmt FROM @s;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END LOOP;
  CLOSE cur;
  SELECT tname, rows FROM _rc ORDER BY tname;
  SELECT COUNT(*) AS empty_tables, (SELECT COUNT(*) FROM _rc) AS total_tables
  FROM _rc WHERE rows = 0;
END$$
DELIMITER ;

CALL opencart_rowcount();
