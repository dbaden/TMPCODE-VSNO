/***************************************************************************************************
  VSNO - Module 06 : performance et coûts
  À exécuter dans VS Code, section par section, dans l'ordre.
***************************************************************************************************/

ALTER SESSION SET QUERY_TAG = 'vsno-m06';

USE ROLE tb_admin;
USE DATABASE tb_101;

/*==================================================================================================
  MESURER
==================================================================================================*/

-- Un warehouse dédié aux mesures
CREATE OR REPLACE WAREHOUSE tb_perf_wh
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Mesures de performance';

USE WAREHOUSE tb_perf_wh;

-- Désactiver le result cache pour des mesures honnêtes
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Requête de référence
SELECT
    truck_brand_name,
    COUNT(DISTINCT order_id) AS order_count,
    SUM(price)               AS total_sales
FROM analytics.orders_v
GROUP BY truck_brand_name
ORDER BY total_sales DESC;

-- Les dernières requêtes de la session
SELECT
    query_id,
    LEFT(query_text, 60)                       AS requete,
    warehouse_size,
    ROUND(total_elapsed_time / 1000, 1)        AS secondes,
    ROUND(bytes_scanned / POWER(1024, 3), 2)   AS go_lus
FROM TABLE(information_schema.query_history_by_session())
WHERE query_type = 'SELECT'
ORDER BY start_time DESC
LIMIT 10;

/*==================================================================================================
  CACHES
==================================================================================================*/

-- Result cache : la même requête, deux fois
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

SELECT truck_brand_name, COUNT(DISTINCT order_id) AS order_count, SUM(price) AS total_sales
FROM analytics.orders_v GROUP BY truck_brand_name ORDER BY total_sales DESC;

SELECT truck_brand_name, COUNT(DISTINCT order_id) AS order_count, SUM(price) AS total_sales
FROM analytics.orders_v GROUP BY truck_brand_name ORDER BY total_sales DESC;

-- Cache du warehouse : sans result cache, warehouse déjà démarré
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

SELECT truck_brand_name, COUNT(DISTINCT order_id) AS order_count, SUM(price) AS total_sales
FROM analytics.orders_v GROUP BY truck_brand_name ORDER BY total_sales DESC;

-- Suspendre le warehouse vide son cache
ALTER WAREHOUSE tb_perf_wh SUSPEND;

SELECT truck_brand_name, COUNT(DISTINCT order_id) AS order_count, SUM(price) AS total_sales
FROM analytics.orders_v GROUP BY truck_brand_name ORDER BY total_sales DESC;

/*==================================================================================================
  MATÉRIALISER
==================================================================================================*/

-- Étape 1 : trois questions métier sur la vue, avec un warehouse Large
ALTER WAREHOUSE tb_perf_wh SET WAREHOUSE_SIZE = 'LARGE';
ALTER SESSION SET QUERY_TAG = 'vsno-m06-vue';

SELECT DATE_TRUNC('month', date) AS mois, country, SUM(price) AS sales
FROM analytics.orders_v
WHERE date >= '2022-01-01' AND date < '2023-01-01'
GROUP BY mois, country
ORDER BY mois, country;

SELECT menu_item_name, SUM(quantity) AS quantity
FROM analytics.orders_v
WHERE country = 'United States'
GROUP BY menu_item_name
ORDER BY quantity DESC
LIMIT 10;

SELECT truck_brand_name, primary_city, SUM(price) AS sales
FROM analytics.orders_v
GROUP BY truck_brand_name, primary_city
ORDER BY sales DESC;

-- Étape 2 : matérialiser une fois les jointures, au grain de la journée
ALTER SESSION SET QUERY_TAG = 'vsno-m06-materialisation';

CREATE OR REPLACE TRANSIENT TABLE analytics.ventes_jour
    COMMENT = 'Ventes par jour, ville, marque et article'
AS
SELECT
    date,
    country,
    primary_city,
    truck_brand_name,
    menu_item_name,
    SUM(quantity)            AS quantity,
    SUM(price)               AS sales,
    COUNT(DISTINCT order_id) AS order_count
FROM analytics.orders_v
GROUP BY ALL;

-- Étape 3 : les mêmes questions sur la table, avec un warehouse X-Small
ALTER WAREHOUSE tb_perf_wh SET WAREHOUSE_SIZE = 'XSMALL';
ALTER SESSION SET QUERY_TAG = 'vsno-m06-table';

SELECT DATE_TRUNC('month', date) AS mois, country, SUM(sales) AS sales
FROM analytics.ventes_jour
WHERE date >= '2022-01-01' AND date < '2023-01-01'
GROUP BY mois, country
ORDER BY mois, country;

SELECT menu_item_name, SUM(quantity) AS quantity
FROM analytics.ventes_jour
WHERE country = 'United States'
GROUP BY menu_item_name
ORDER BY quantity DESC
LIMIT 10;

SELECT truck_brand_name, primary_city, SUM(sales) AS sales
FROM analytics.ventes_jour
GROUP BY truck_brand_name, primary_city
ORDER BY sales DESC;

-- Étape 4 : comparer durées et crédits estimés
ALTER SESSION SET QUERY_TAG = 'vsno-m06';

SELECT
    query_tag,
    warehouse_size,
    COUNT(*)                                   AS nb_requetes,
    ROUND(SUM(total_elapsed_time) / 1000, 1)   AS secondes,
    ROUND(SUM(total_elapsed_time / 1000 / 3600 *
        CASE warehouse_size
            WHEN 'X-Small' THEN 1
            WHEN 'Small'   THEN 2
            WHEN 'Medium'  THEN 4
            WHEN 'Large'   THEN 8
            WHEN 'X-Large' THEN 16
        END), 4)                               AS credits_estimes
FROM TABLE(information_schema.query_history_by_session(RESULT_LIMIT => 1000))
WHERE query_tag IN ('vsno-m06-vue', 'vsno-m06-materialisation', 'vsno-m06-table')
  AND query_type IN ('SELECT', 'CREATE_TABLE_AS_SELECT')
GROUP BY query_tag, warehouse_size
ORDER BY MIN(start_time);

/*==================================================================================================
  BONNES PRATIQUES SQL
  Warehouse X-Small, result cache désactivé. Comparer les durées et le query profile.
==================================================================================================*/

-- Ne lire que les colonnes utiles
SELECT *
FROM raw_pos.order_header
WHERE order_ts >= '2022-06-01' AND order_ts < '2022-06-02';

SELECT order_id, truck_id, order_total
FROM raw_pos.order_header
WHERE order_ts >= '2022-06-01' AND order_ts < '2022-06-02';

-- Ne pas appliquer de fonction à la colonne filtrée
SELECT COUNT(*) AS nb_commandes, SUM(order_total) AS total
FROM raw_pos.order_header
WHERE TO_CHAR(order_ts, 'YYYY-MM') = '2022-06';

SELECT COUNT(*) AS nb_commandes, SUM(order_total) AS total
FROM raw_pos.order_header
WHERE order_ts >= '2022-06-01' AND order_ts < '2022-07-01';

-- LIMIT réduit les lignes renvoyées, pas les lignes lues
SELECT * FROM raw_pos.order_detail LIMIT 10;

SELECT order_detail_id, price
FROM raw_pos.order_detail
ORDER BY price DESC
LIMIT 10;

-- Attention aux jointures qui multiplient les lignes
SELECT SUM(oh.order_total) AS total_faux
FROM raw_pos.order_header oh
JOIN raw_pos.order_detail od ON oh.order_id = od.order_id
WHERE oh.order_ts >= '2022-06-01' AND oh.order_ts < '2022-06-02';

SELECT SUM(order_total) AS total_correct
FROM raw_pos.order_header
WHERE order_ts >= '2022-06-01' AND order_ts < '2022-06-02';

-- QUALIFY : filtrer sur une fonction de fenêtrage (dernière commande de chaque client)
SELECT customer_id, order_id, order_ts, order_total
FROM raw_pos.order_header
WHERE customer_id IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_ts DESC) = 1;

-- Un comptage approché suffit souvent
SELECT COUNT(DISTINCT customer_id)        AS clients_exact  FROM raw_pos.order_header;
SELECT APPROX_COUNT_DISTINCT(customer_id) AS clients_approx FROM raw_pos.order_header;

/*==================================================================================================
  GARDE-FOUS
==================================================================================================*/

-- Délais maximum sur un warehouse
ALTER WAREHOUSE tb_perf_wh SET
    STATEMENT_TIMEOUT_IN_SECONDS        = 1800   -- une requête : 30 minutes au plus
    STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 600;   -- attente en file : 10 minutes au plus

SHOW PARAMETERS LIKE '%STATEMENT%' IN WAREHOUSE tb_perf_wh;

-- Les paramètres de compte demandent ACCOUNTADMIN
USE ROLE accountadmin;

ALTER ACCOUNT SET STATEMENT_TIMEOUT_IN_SECONDS = 18000;   -- 5 heures

-- Resource monitor : un quota de crédits par mois
CREATE OR REPLACE RESOURCE MONITOR tb_perf_rm
    WITH CREDIT_QUOTA    = 20
         FREQUENCY       = MONTHLY
         START_TIMESTAMP = IMMEDIATELY
    TRIGGERS ON 75  PERCENT DO NOTIFY
             ON 90  PERCENT DO SUSPEND
             ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE tb_perf_wh SET RESOURCE_MONITOR = tb_perf_rm;

-- Budget : suivi des dépenses, configuré ensuite dans Snowsight
CREATE OR REPLACE SNOWFLAKE.CORE.BUDGET tb_101.public.tb_budget()
    COMMENT = 'Budget Tasty Bytes';

-- Tag : attribuer les coûts à une équipe
CREATE OR REPLACE TAG tb_101.public.cost_center
    ALLOWED_VALUES 'DATA_ENGINEERING', 'DEVELOPMENT', 'ANALYTICS';

ALTER WAREHOUSE tb_de_wh      SET TAG tb_101.public.cost_center = 'DATA_ENGINEERING';
ALTER WAREHOUSE tb_dev_wh     SET TAG tb_101.public.cost_center = 'DEVELOPMENT';
ALTER WAREHOUSE tb_analyst_wh SET TAG tb_101.public.cost_center = 'ANALYTICS';

-- Lire sa consommation (ACCOUNT_USAGE : données mises à jour avec quelques heures de décalage)
SELECT
    warehouse_name,
    ROUND(SUM(credits_used), 2) AS credits
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY credits DESC;

-- Consommation par équipe, grâce au tag
SELECT
    tr.tag_value                     AS cost_center,
    ROUND(SUM(wmh.credits_used), 2)  AS credits
FROM snowflake.account_usage.warehouse_metering_history wmh
JOIN snowflake.account_usage.tag_references tr
    ON  tr.object_name = wmh.warehouse_name
    AND tr.domain      = 'WAREHOUSE'
    AND tr.tag_name    = 'COST_CENTER'
WHERE wmh.start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY tr.tag_value
ORDER BY credits DESC;

-- Les requêtes les plus longues des dernières 24 heures
SELECT
    query_tag,
    warehouse_name,
    warehouse_size,
    ROUND(total_elapsed_time / 1000, 1) AS secondes,
    LEFT(query_text, 80)                AS requete
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
ORDER BY total_elapsed_time DESC
LIMIT 10;

/*==================================================================================================
  RESET (optionnel)
==================================================================================================*/
-- ALTER ACCOUNT UNSET STATEMENT_TIMEOUT_IN_SECONDS;
-- DROP RESOURCE MONITOR IF EXISTS tb_perf_rm;
-- DROP WAREHOUSE IF EXISTS tb_perf_wh;
