/***************************************************************************************************
  VSNO - Module 07 : design et deploy
  À exécuter dans VS Code, section par section, dans l'ordre.
***************************************************************************************************/

ALTER SESSION SET QUERY_TAG = 'vsno-m07';

USE ROLE tb_data_engineer;
USE WAREHOUSE tb_de_wh;
USE DATABASE tb_101;

/*==================================================================================================
  CLONE ET TIME TRAVEL
==================================================================================================*/

-- Le défaut repéré au module 03 : une marque mal saisie
SELECT truck_build:make::VARCHAR AS make, COUNT(*) AS nb_camions
FROM raw_pos.truck_details
GROUP BY make
ORDER BY make;

-- Un environnement de développement en une instruction : zero-copy clone
CREATE OR REPLACE TABLE raw_pos.truck_dev CLONE raw_pos.truck_details;

-- Développer sur le clone : extraire année, marque et modèle
ALTER TABLE raw_pos.truck_dev ADD COLUMN year NUMBER;
ALTER TABLE raw_pos.truck_dev ADD COLUMN make VARCHAR;
ALTER TABLE raw_pos.truck_dev ADD COLUMN model VARCHAR;

UPDATE raw_pos.truck_dev
    SET year  = truck_build:year::NUMBER,
        make  = truck_build:make::VARCHAR,
        model = truck_build:model::VARCHAR;

SELECT make, COUNT(*) AS nb_camions
FROM raw_pos.truck_dev
GROUP BY make
ORDER BY make;

-- Corriger… en oubliant le WHERE
UPDATE raw_pos.truck_dev SET make = 'Ford';

SELECT make, COUNT(*) AS nb_camions
FROM raw_pos.truck_dev
GROUP BY make;

-- Retrouver l'instruction fautive dans l'historique
SELECT query_id, query_text, start_time
FROM TABLE(information_schema.query_history_by_session())
WHERE query_type = 'UPDATE'
  AND query_text ILIKE '%raw_pos.truck_dev%'
ORDER BY start_time DESC;

SET query_id = (
    SELECT query_id
    FROM TABLE(information_schema.query_history_by_session())
    WHERE query_type = 'UPDATE'
      AND query_text ILIKE '%raw_pos.truck_dev%'
    ORDER BY start_time DESC
    LIMIT 1
);

-- Time travel : la table juste avant cette instruction
SELECT make, COUNT(*) AS nb_camions
FROM raw_pos.truck_dev BEFORE(STATEMENT => $query_id)
GROUP BY make
ORDER BY make;

-- Restaurer cet état
CREATE OR REPLACE TABLE raw_pos.truck_dev
AS
SELECT * FROM raw_pos.truck_dev BEFORE(STATEMENT => $query_id);

-- La bonne correction
UPDATE raw_pos.truck_dev
    SET make = 'Ford'
    WHERE make = 'Ford_';

SELECT make, COUNT(*) AS nb_camions
FROM raw_pos.truck_dev
GROUP BY make
ORDER BY make;

-- Time travel par décalage : la table de production il y a 5 minutes
SELECT COUNT(*) FROM raw_pos.truck_details AT(OFFSET => -60 * 5);

-- Mettre en production : échanger les deux tables
ALTER TABLE raw_pos.truck_details SWAP WITH raw_pos.truck_dev;

SELECT make, COUNT(*) AS nb_camions
FROM raw_pos.truck_details
GROUP BY make
ORDER BY make;

-- Nettoyer… en supprimant la mauvaise table
DROP TABLE raw_pos.truck_details;

-- Restaurer la table supprimée
UNDROP TABLE raw_pos.truck_details;

SELECT COUNT(*) FROM raw_pos.truck_details;

-- Supprimer la bonne table (l'ancienne version, après l'échange)
DROP TABLE raw_pos.truck_dev;

-- Durée de rétention du time travel
SHOW TABLES LIKE 'TRUCK%' IN SCHEMA raw_pos;

-- Cloner toute une database
USE ROLE sysadmin;

CREATE OR REPLACE DATABASE tb_101_dev CLONE tb_101;
SHOW SCHEMAS IN DATABASE tb_101_dev;
DROP DATABASE tb_101_dev;

/*==================================================================================================
  PIPELINES : DYNAMIC TABLES
==================================================================================================*/

USE ROLE tb_data_engineer;
USE WAREHOUSE tb_de_wh;
USE DATABASE tb_101;

-- Les ingrédients, mis à jour automatiquement depuis menu_staging (module 05)
CREATE OR REPLACE DYNAMIC TABLE harmonized.ingredient
    TARGET_LAG = '1 minute'
    WAREHOUSE  = tb_de_wh
AS
SELECT
    i.value::STRING                    AS ingredient_name,
    ARRAY_AGG(DISTINCT m.menu_item_id) AS menu_ids
FROM raw_pos.menu_staging m,
    LATERAL FLATTEN(INPUT => m.menu_item_health_metrics_obj:menu_item_health_metrics) obj,
    LATERAL FLATTEN(INPUT => obj.value:ingredients) i
GROUP BY i.value::STRING;

SELECT * FROM harmonized.ingredient ORDER BY ingredient_name;

-- Une table intermédiaire : rafraîchie quand la suivante en a besoin
CREATE OR REPLACE DYNAMIC TABLE harmonized.ingredient_to_menu_lookup
    TARGET_LAG = DOWNSTREAM
    WAREHOUSE  = tb_de_wh
AS
SELECT
    i.value::STRING AS ingredient_name,
    m.menu_item_id
FROM raw_pos.menu_staging m,
    LATERAL FLATTEN(INPUT => m.menu_item_health_metrics_obj:menu_item_health_metrics) obj,
    LATERAL FLATTEN(INPUT => obj.value:ingredients) i;

-- Consommation d'ingrédients par camion et par mois : jointure sur les grosses tables,
-- le premier calcul se fait sur un warehouse plus grand
ALTER WAREHOUSE tb_de_wh SET WAREHOUSE_SIZE = 'LARGE';

CREATE OR REPLACE DYNAMIC TABLE harmonized.ingredient_usage_by_truck
    TARGET_LAG = '2 minutes'
    WAREHOUSE  = tb_de_wh
AS
SELECT
    oh.truck_id,
    YEAR(oh.order_ts)  AS order_year,
    MONTH(oh.order_ts) AS order_month,
    iml.ingredient_name,
    SUM(od.quantity)   AS total_ingredients_used
FROM raw_pos.order_detail od
JOIN raw_pos.order_header oh                  ON od.order_id = oh.order_id
JOIN harmonized.ingredient_to_menu_lookup iml ON od.menu_item_id = iml.menu_item_id
JOIN raw_pos.location l                       ON oh.location_id = l.location_id
WHERE l.country = 'United States'
GROUP BY ALL;

ALTER WAREHOUSE tb_de_wh SET WAREHOUSE_SIZE = 'XSMALL';

-- Un nouveau plat au menu : le Banh Mi de Better Off Bread
INSERT INTO raw_pos.menu_staging
SELECT
    10101, 15, 'Sandwiches', 'Better Off Bread', 157, 'Banh Mi', 'Main', 'Cold Option', 9.0, 12.0,
    PARSE_JSON('{
      "menu_item_id": 157,
      "menu_item_health_metrics": [{
        "ingredients": ["French Baguette", "Mayonnaise", "Pickled Daikon", "Cucumber", "Pork Belly"],
        "is_dairy_free_flag": "N",
        "is_gluten_free_flag": "N",
        "is_healthy_flag": "Y",
        "is_nut_free_flag": "Y"
      }]
    }');

-- Une commande de 2 Banh Mi, au camion 15, le 27 janvier 2022
INSERT INTO raw_pos.order_header
SELECT
    459520441, 15, 1030, 101565, NULL, 200322900,
    '08:00:00'::TIME, '14:00:00'::TIME, NULL,
    '2022-01-27 08:21:08'::TIMESTAMP_NTZ, NULL, 'USD', 14.00, NULL, NULL, 14.00;

INSERT INTO raw_pos.order_detail
SELECT 904745311, 459520441, 157, NULL, 0, 2, 14.00, 28.00, NULL;

-- Une à deux minutes plus tard : les nouveaux ingrédients et leur consommation
SELECT * FROM harmonized.ingredient
WHERE ingredient_name IN ('French Baguette', 'Pickled Daikon');

SELECT ingredient_name, SUM(total_ingredients_used) AS total_ingredients_used
FROM harmonized.ingredient_usage_by_truck
WHERE truck_id = 15 AND order_year = 2022 AND order_month = 1
GROUP BY ingredient_name
ORDER BY total_ingredients_used DESC;

-- Suivre les rafraîchissements
SHOW DYNAMIC TABLES IN SCHEMA harmonized;

SELECT name, state, refresh_action, refresh_trigger, data_timestamp
FROM TABLE(information_schema.dynamic_table_refresh_history())
ORDER BY data_timestamp DESC
LIMIT 20;

/*==================================================================================================
  PIPELINES : STREAM ET TASK
==================================================================================================*/

-- Un stream enregistre les changements d'une table
CREATE OR REPLACE STREAM raw_pos.menu_staging_stream ON TABLE raw_pos.menu_staging;

-- La table que la task va alimenter : le journal des nouveaux plats
CREATE OR REPLACE TABLE harmonized.menu_journal
(
    menu_item_id     NUMBER,
    menu_item_name   VARCHAR,
    truck_brand_name VARCHAR,
    ajoute_le        TIMESTAMP_LTZ
);

-- Un autre nouveau plat
INSERT INTO raw_pos.menu_staging
SELECT
    10102, 15, 'Sandwiches', 'Better Off Bread', 158, 'Croque Monsieur', 'Main', 'Hot Option', 7.0, 11.0,
    PARSE_JSON('{
      "menu_item_id": 158,
      "menu_item_health_metrics": [{
        "ingredients": ["Bread", "Ham", "Cheese", "Butter"],
        "is_dairy_free_flag": "N",
        "is_gluten_free_flag": "N",
        "is_healthy_flag": "N",
        "is_nut_free_flag": "Y"
      }]
    }');

-- Le stream contient la ligne ajoutée
SELECT menu_item_id, menu_item_name, METADATA$ACTION, METADATA$ISUPDATE
FROM raw_pos.menu_staging_stream;

-- Une task : une instruction SQL planifiée
CREATE OR REPLACE TASK harmonized.menu_journal_task
    WAREHOUSE = tb_de_wh
    SCHEDULE  = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('raw_pos.menu_staging_stream')
AS
INSERT INTO harmonized.menu_journal
SELECT menu_item_id, menu_item_name, truck_brand_name, CURRENT_TIMESTAMP()
FROM raw_pos.menu_staging_stream
WHERE METADATA$ACTION = 'INSERT';

-- Exécuter des tasks demande un privilège de compte
USE ROLE accountadmin;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE tb_data_engineer;
USE ROLE tb_data_engineer;

-- Lancer la task une fois, à la demande
EXECUTE TASK harmonized.menu_journal_task;

-- Quelques secondes plus tard
SELECT name, state, scheduled_time, completed_time
FROM TABLE(information_schema.task_history(TASK_NAME => 'MENU_JOURNAL_TASK'))
ORDER BY scheduled_time DESC;

SELECT * FROM harmonized.menu_journal;

-- Le stream a été consommé : il est vide
SELECT COUNT(*) FROM raw_pos.menu_staging_stream;

-- Planifier, puis arrêter la planification
ALTER TASK harmonized.menu_journal_task RESUME;
SHOW TASKS IN SCHEMA harmonized;
ALTER TASK harmonized.menu_journal_task SUSPEND;

-- Snowpipe (pour mémoire, non exécuté : nécessite des notifications du stockage cloud)
-- CREATE PIPE raw_pos.menu_pipe
--     AUTO_INGEST = TRUE
-- AS
-- COPY INTO raw_pos.menu_staging FROM @public.s3load/raw_pos/menu/;

/*==================================================================================================
  PARTAGER
==================================================================================================*/

CREATE OR REPLACE VIEW analytics.ingredient_usage_v
    COMMENT = 'Consommation mensuelle d''ingrédients par camion, États-Unis'
AS
SELECT * FROM harmonized.ingredient_usage_by_truck;

SHOW GRANTS ON VIEW analytics.ingredient_usage_v;

USE ROLE tb_analyst;
USE SECONDARY ROLES NONE;   -- seuls les droits de tb_analyst comptent
USE WAREHOUSE tb_analyst_wh;

SELECT ingredient_name, SUM(total_ingredients_used) AS total_ingredients_used
FROM tb_101.analytics.ingredient_usage_v
WHERE truck_id = 15 AND order_year = 2022 AND order_month = 1
GROUP BY ingredient_name
ORDER BY total_ingredients_used DESC;

-- Retour au comportement par défaut : tous les roles de l'utilisateur sont actifs
USE SECONDARY ROLES ALL;

/*==================================================================================================
  ARRÊTER LES PIPELINES
  Une dynamic table ou une task active continue de consommer des crédits.
==================================================================================================*/

USE ROLE tb_data_engineer;

ALTER DYNAMIC TABLE harmonized.ingredient_usage_by_truck SUSPEND;
ALTER DYNAMIC TABLE harmonized.ingredient_to_menu_lookup SUSPEND;
ALTER DYNAMIC TABLE harmonized.ingredient               SUSPEND;
ALTER TASK harmonized.menu_journal_task SUSPEND;

/*==================================================================================================
  RESET (optionnel)
==================================================================================================*/
-- DELETE FROM raw_pos.order_detail WHERE order_detail_id = 904745311;
-- DELETE FROM raw_pos.order_header WHERE order_id = 459520441;
-- DELETE FROM raw_pos.menu_staging WHERE menu_item_id IN (157, 158);
