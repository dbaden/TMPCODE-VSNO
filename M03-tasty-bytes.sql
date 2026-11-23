/***************************************************************************************************
  VSNO - Module 03 : la plateforme Tasty Bytes pas à pas
  À exécuter dans VS Code, section par section, dans l'ordre.
  Adapté de « Zero to Snowflake » (Snowflake Inc.).
***************************************************************************************************/

ALTER SESSION SET QUERY_TAG = 'vsno-m03';

/*==================================================================================================
  ROLES
==================================================================================================*/

-- Les roles se créent avec SECURITYADMIN (ou USERADMIN)
USE ROLE securityadmin;

CREATE ROLE IF NOT EXISTS tb_admin         COMMENT = 'Administrateur Tasty Bytes';
CREATE ROLE IF NOT EXISTS tb_data_engineer COMMENT = 'Data engineer : construit et charge la plateforme';
CREATE ROLE IF NOT EXISTS tb_dev           COMMENT = 'Développeur : lit toutes les données';
CREATE ROLE IF NOT EXISTS tb_analyst       COMMENT = 'Analyste : lit uniquement la couche analytics';

-- Hiérarchie : un role hérite des privilèges des roles qui lui sont accordés
GRANT ROLE tb_dev           TO ROLE tb_data_engineer;
GRANT ROLE tb_analyst       TO ROLE tb_data_engineer;
GRANT ROLE tb_data_engineer TO ROLE tb_admin;
GRANT ROLE tb_admin         TO ROLE sysadmin;   -- rattacher les roles fonctionnels à SYSADMIN

-- Vérifier
SHOW ROLES LIKE 'TB%';
SHOW GRANTS TO ROLE tb_data_engineer;

/*==================================================================================================
  WAREHOUSES
==================================================================================================*/

-- Les warehouses se créent avec SYSADMIN
USE ROLE sysadmin;

-- Warehouse des data engineers : Large pour les chargements, réduit ensuite
CREATE OR REPLACE WAREHOUSE tb_de_wh
    WAREHOUSE_SIZE      = 'LARGE'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Data engineering Tasty Bytes';

-- Warehouse des développeurs
CREATE OR REPLACE WAREHOUSE tb_dev_wh
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Développement Tasty Bytes';

-- Warehouse des analystes : jusqu'à 2 clusters aux heures de pointe
CREATE OR REPLACE WAREHOUSE tb_analyst_wh
    WAREHOUSE_SIZE      = 'XSMALL'
    MIN_CLUSTER_COUNT   = 1
    MAX_CLUSTER_COUNT   = 2
    SCALING_POLICY      = 'STANDARD'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Analyse Tasty Bytes';

-- Donner accès aux warehouses
USE ROLE securityadmin;

GRANT USAGE, OPERATE, MODIFY ON WAREHOUSE tb_de_wh   TO ROLE tb_data_engineer;
GRANT USAGE, OPERATE         ON WAREHOUSE tb_dev_wh  TO ROLE tb_dev;
GRANT USAGE, OPERATE         ON WAREHOUSE tb_analyst_wh TO ROLE tb_analyst;

GRANT ALL ON WAREHOUSE tb_de_wh      TO ROLE tb_admin;
GRANT ALL ON WAREHOUSE tb_dev_wh     TO ROLE tb_admin;
GRANT ALL ON WAREHOUSE tb_analyst_wh TO ROLE tb_admin;

USE ROLE accountadmin;
GRANT CREATE WAREHOUSE ON ACCOUNT    TO ROLE tb_admin;

USE ROLE securityadmin;

SHOW WAREHOUSES LIKE 'TB%';

/*==================================================================================================
  DATABASE ET SCHEMAS
==================================================================================================*/

USE ROLE sysadmin;

CREATE OR REPLACE DATABASE tb_101 COMMENT = 'Plateforme de données Tasty Bytes';

CREATE OR REPLACE SCHEMA tb_101.raw_pos      COMMENT = 'Données brutes des caisses';
CREATE OR REPLACE SCHEMA tb_101.raw_customer COMMENT = 'Données brutes du programme de fidélité';
CREATE OR REPLACE SCHEMA tb_101.harmonized   COMMENT = 'Données nettoyées et reliées';
CREATE OR REPLACE SCHEMA tb_101.analytics    COMMENT = 'Données prêtes pour l''analyse';

-- Droits sur les données
USE ROLE securityadmin;

-- Le data engineer construit tout : tous les droits sur les schemas
GRANT USAGE ON DATABASE tb_101 TO ROLE tb_data_engineer;
GRANT ALL ON SCHEMA tb_101.public       TO ROLE tb_data_engineer;
GRANT ALL ON SCHEMA tb_101.raw_pos      TO ROLE tb_data_engineer;
GRANT ALL ON SCHEMA tb_101.raw_customer TO ROLE tb_data_engineer;
GRANT ALL ON SCHEMA tb_101.harmonized   TO ROLE tb_data_engineer;
GRANT ALL ON SCHEMA tb_101.analytics    TO ROLE tb_data_engineer;

-- Le développeur lit tout, y compris les objets qui seront créés plus tard (future grants)
GRANT USAGE ON DATABASE tb_101 TO ROLE tb_dev;
GRANT USAGE ON ALL SCHEMAS IN DATABASE tb_101 TO ROLE tb_dev;
GRANT SELECT ON FUTURE TABLES IN SCHEMA tb_101.raw_pos      TO ROLE tb_dev;
GRANT SELECT ON FUTURE TABLES IN SCHEMA tb_101.raw_customer TO ROLE tb_dev;
GRANT SELECT ON FUTURE TABLES IN SCHEMA tb_101.harmonized   TO ROLE tb_dev;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA tb_101.harmonized   TO ROLE tb_dev;
GRANT SELECT ON FUTURE TABLES IN SCHEMA tb_101.analytics    TO ROLE tb_dev;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA tb_101.analytics    TO ROLE tb_dev;

-- L'analyste ne lit que la couche analytics
GRANT USAGE ON DATABASE tb_101 TO ROLE tb_analyst;
GRANT USAGE ON SCHEMA tb_101.analytics TO ROLE tb_analyst;
GRANT SELECT ON FUTURE TABLES IN SCHEMA tb_101.analytics TO ROLE tb_analyst;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA tb_101.analytics TO ROLE tb_analyst;

-- Explorer
USE ROLE tb_data_engineer;
SHOW SCHEMAS IN DATABASE tb_101;

SELECT schema_name, comment
FROM tb_101.information_schema.schemata
ORDER BY schema_name;

/*==================================================================================================
  CHARGEMENT
==================================================================================================*/

USE ROLE tb_data_engineer;
USE WAREHOUSE tb_de_wh;
USE DATABASE tb_101;

-- File format : comment lire les fichiers
CREATE OR REPLACE FILE FORMAT public.csv_ff
    TYPE = 'CSV'
    COMMENT = 'Fichiers CSV sans en-tête';

-- Stage externe : où sont les fichiers (bucket S3 public de Snowflake)
CREATE OR REPLACE STAGE public.s3load
    URL         = 's3://sfquickstarts/frostbyte_tastybytes/'
    FILE_FORMAT = public.csv_ff
    COMMENT     = 'Fichiers sources Tasty Bytes';

-- Lister les fichiers d'un dossier du stage
LIST @public.s3load/raw_pos/menu/;

-- Tables brutes
CREATE OR REPLACE TABLE raw_pos.country
(
    country_id      NUMBER(18,0),
    country         VARCHAR,
    iso_currency    VARCHAR(3),
    iso_country     VARCHAR(2),
    city_id         NUMBER(19,0),
    city            VARCHAR,
    city_population VARCHAR
);

CREATE OR REPLACE TABLE raw_pos.franchise
(
    franchise_id NUMBER(38,0),
    first_name   VARCHAR,
    last_name    VARCHAR,
    city         VARCHAR,
    country      VARCHAR,
    e_mail       VARCHAR,
    phone_number VARCHAR
);

CREATE OR REPLACE TABLE raw_pos.location
(
    location_id      NUMBER(19,0),
    placekey         VARCHAR,
    location         VARCHAR,
    city             VARCHAR,
    region           VARCHAR,
    iso_country_code VARCHAR,
    country          VARCHAR
);

CREATE OR REPLACE TABLE raw_pos.menu
(
    menu_id                      NUMBER(19,0),
    menu_type_id                 NUMBER(38,0),
    menu_type                    VARCHAR,
    truck_brand_name             VARCHAR,
    menu_item_id                 NUMBER(38,0),
    menu_item_name               VARCHAR,
    item_category                VARCHAR,
    item_subcategory             VARCHAR,
    cost_of_goods_usd            NUMBER(38,4),
    sale_price_usd               NUMBER(38,4),
    menu_item_health_metrics_obj VARIANT          -- données semi-structurées (module 05)
);

CREATE OR REPLACE TABLE raw_pos.truck
(
    truck_id           NUMBER(38,0),
    menu_type_id       NUMBER(38,0),
    primary_city       VARCHAR,
    region             VARCHAR,
    iso_region         VARCHAR,
    country            VARCHAR,
    iso_country_code   VARCHAR,
    franchise_flag     NUMBER(38,0),
    year               NUMBER(38,0),
    make               VARCHAR,
    model              VARCHAR,
    ev_flag            NUMBER(38,0),
    franchise_id       NUMBER(38,0),
    truck_opening_date DATE
);

CREATE OR REPLACE TABLE raw_pos.order_header
(
    order_id              NUMBER(38,0),
    truck_id              NUMBER(38,0),
    location_id           FLOAT,
    customer_id           NUMBER(38,0),
    discount_id           VARCHAR,
    shift_id              NUMBER(38,0),
    shift_start_time      TIME(9),
    shift_end_time        TIME(9),
    order_channel         VARCHAR,
    order_ts              TIMESTAMP_NTZ(9),
    served_ts             VARCHAR,
    order_currency        VARCHAR(3),
    order_amount          NUMBER(38,4),
    order_tax_amount      VARCHAR,
    order_discount_amount VARCHAR,
    order_total           NUMBER(38,4)
);

CREATE OR REPLACE TABLE raw_pos.order_detail
(
    order_detail_id            NUMBER(38,0),
    order_id                   NUMBER(38,0),
    menu_item_id               NUMBER(38,0),
    discount_id                VARCHAR,
    line_number                NUMBER(38,0),
    quantity                   NUMBER(5,0),
    unit_price                 NUMBER(38,4),
    price                      NUMBER(38,4),
    order_item_discount_amount VARCHAR
);

CREATE OR REPLACE TABLE raw_customer.customer_loyalty
(
    customer_id        NUMBER(38,0),
    first_name         VARCHAR,
    last_name          VARCHAR,
    city               VARCHAR,
    country            VARCHAR,
    postal_code        VARCHAR,
    preferred_language VARCHAR,
    gender             VARCHAR,
    favourite_brand    VARCHAR,
    marital_status     VARCHAR,
    children_count     VARCHAR,
    sign_up_date       DATE,
    birthday_date      DATE,
    e_mail             VARCHAR,
    phone_number       VARCHAR
);

-- Chargement des petites tables
COPY INTO raw_pos.country               FROM @public.s3load/raw_pos/country/;
COPY INTO raw_pos.franchise             FROM @public.s3load/raw_pos/franchise/;
COPY INTO raw_pos.location              FROM @public.s3load/raw_pos/location/;
COPY INTO raw_pos.menu                  FROM @public.s3load/raw_pos/menu/;
COPY INTO raw_pos.truck                 FROM @public.s3load/raw_pos/truck/;
COPY INTO raw_customer.customer_loyalty FROM @public.s3load/raw_customer/customer_loyalty/;

-- Chargement des grosses tables (plusieurs minutes : à lancer avant la pause)
COPY INTO raw_pos.order_header FROM @public.s3load/raw_pos/order_header/;
COPY INTO raw_pos.order_detail FROM @public.s3load/raw_pos/order_detail/;

-- Les chargements lourds sont terminés : on réduit le warehouse
ALTER WAREHOUSE tb_de_wh SET WAREHOUSE_SIZE = 'XSMALL';

-- Vérifier les volumes chargés
SELECT 'country' AS table_name, COUNT(*) AS nb_lignes FROM raw_pos.country
UNION ALL SELECT 'franchise',        COUNT(*) FROM raw_pos.franchise
UNION ALL SELECT 'location',         COUNT(*) FROM raw_pos.location
UNION ALL SELECT 'menu',             COUNT(*) FROM raw_pos.menu
UNION ALL SELECT 'truck',            COUNT(*) FROM raw_pos.truck
UNION ALL SELECT 'customer_loyalty', COUNT(*) FROM raw_customer.customer_loyalty
UNION ALL SELECT 'order_header',     COUNT(*) FROM raw_pos.order_header
UNION ALL SELECT 'order_detail',     COUNT(*) FROM raw_pos.order_detail;

-- Historique de chargement d'une table
SELECT file_name, row_count, status, last_load_time
FROM TABLE(information_schema.copy_history(
    TABLE_NAME => 'RAW_POS.ORDER_HEADER',
    START_TIME => DATEADD(hour, -2, CURRENT_TIMESTAMP())))
ORDER BY last_load_time DESC;

/*==================================================================================================
  TRANSFORMATION
==================================================================================================*/

USE ROLE tb_data_engineer;
USE WAREHOUSE tb_de_wh;
USE DATABASE tb_101;

-- Regrouper année, marque et modèle d'un camion dans une colonne semi-structurée
ALTER TABLE raw_pos.truck ADD COLUMN truck_build OBJECT;

UPDATE raw_pos.truck
    SET truck_build = OBJECT_CONSTRUCT('year', year, 'make', make, 'model', model);

SELECT truck_id, year, make, model, truck_build
FROM raw_pos.truck
LIMIT 5;

-- Créer une table à partir d'une requête (CTAS), sans les colonnes devenues redondantes
CREATE OR REPLACE TABLE raw_pos.truck_details
AS
SELECT * EXCLUDE (year, make, model)
FROM raw_pos.truck;

-- Couche harmonized : relier les tables brutes
CREATE OR REPLACE VIEW harmonized.orders_v
    COMMENT = 'Une ligne par article commandé, avec camion, menu, franchise et client'
AS
SELECT
    oh.order_id,
    oh.truck_id,
    oh.order_ts,
    od.order_detail_id,
    od.line_number,
    m.truck_brand_name,
    m.menu_type,
    t.primary_city,
    t.region,
    t.country,
    t.franchise_flag,
    t.franchise_id,
    f.first_name AS franchisee_first_name,
    f.last_name  AS franchisee_last_name,
    l.location_id,
    cl.customer_id,
    cl.first_name,
    cl.last_name,
    cl.e_mail,
    cl.phone_number,
    cl.children_count,
    cl.gender,
    cl.marital_status,
    od.menu_item_id,
    m.menu_item_name,
    od.quantity,
    od.unit_price,
    od.price,
    oh.order_amount,
    oh.order_tax_amount,
    oh.order_discount_amount,
    oh.order_total
FROM raw_pos.order_detail od
JOIN raw_pos.order_header oh ON od.order_id = oh.order_id
JOIN raw_pos.truck t         ON oh.truck_id = t.truck_id
JOIN raw_pos.menu m          ON od.menu_item_id = m.menu_item_id
JOIN raw_pos.franchise f     ON t.franchise_id = f.franchise_id
JOIN raw_pos.location l      ON oh.location_id = l.location_id
LEFT JOIN raw_customer.customer_loyalty cl ON oh.customer_id = cl.customer_id;

CREATE OR REPLACE VIEW harmonized.customer_loyalty_metrics_v
    COMMENT = 'Une ligne par client fidélisé, avec ses ventes totales'
AS
SELECT
    cl.customer_id,
    cl.city,
    cl.country,
    cl.first_name,
    cl.last_name,
    cl.phone_number,
    cl.e_mail,
    SUM(oh.order_total)                AS total_sales,
    ARRAY_AGG(DISTINCT oh.location_id) AS visited_location_ids_array
FROM raw_customer.customer_loyalty cl
JOIN raw_pos.order_header oh ON cl.customer_id = oh.customer_id
GROUP BY cl.customer_id, cl.city, cl.country, cl.first_name,
         cl.last_name, cl.phone_number, cl.e_mail;

-- Couche analytics : ce que voient les utilisateurs métier
CREATE OR REPLACE VIEW analytics.orders_v
    COMMENT = 'Détail des commandes Tasty Bytes'
AS
SELECT DATE(o.order_ts) AS date, *
FROM harmonized.orders_v o;

CREATE OR REPLACE VIEW analytics.customer_loyalty_metrics_v
    COMMENT = 'Indicateurs des clients fidélisés'
AS
SELECT * FROM harmonized.customer_loyalty_metrics_v;

-- Qui voit quoi ?
USE ROLE tb_analyst;
USE SECONDARY ROLES NONE;   -- seuls les droits de tb_analyst comptent
USE WAREHOUSE tb_analyst_wh;

SELECT COUNT(*) FROM tb_101.raw_pos.menu;        -- erreur attendue : la couche raw n'est pas visible
SELECT COUNT(*) FROM tb_101.analytics.orders_v;  -- fonctionne

-- Interroger la couche analytics
SELECT
    truck_brand_name,
    COUNT(DISTINCT order_id) AS order_count,
    SUM(price)               AS total_sales
FROM tb_101.analytics.orders_v
GROUP BY truck_brand_name
ORDER BY total_sales DESC;

SELECT
    country,
    primary_city,
    SUM(price) AS total_sales
FROM tb_101.analytics.orders_v
WHERE YEAR(date) = 2022
GROUP BY country, primary_city
ORDER BY total_sales DESC
LIMIT 10;

-- Retour au comportement par défaut : tous les roles de l'utilisateur sont actifs
USE SECONDARY ROLES ALL;
