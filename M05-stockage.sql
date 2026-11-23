/***************************************************************************************************
  VSNO - Module 05 : stockage et requêtage avancé
  À exécuter dans VS Code, section par section, dans l'ordre.
***************************************************************************************************/

ALTER SESSION SET QUERY_TAG = 'vsno-m05';

USE ROLE tb_data_engineer;
USE WAREHOUSE tb_de_wh;
USE DATABASE tb_101;

/*==================================================================================================
  STAGES
==================================================================================================*/

-- Les stages implicites : celui de l'utilisateur et celui de chaque table
LIST @~;
LIST @raw_pos.%franchise;

-- Un stage interne nommé : les fichiers sont stockés par Snowflake
CREATE OR REPLACE STAGE public.fichiers
    COMMENT = 'Fichiers déposés depuis le poste de travail';

-- Déposer un fichier : depuis le terminal de VS Code, dans le dossier code/ du module
--   snow stage copy data/nouvelles_franchises.csv @tb_101.public.fichiers --connection vsno

LIST @public.fichiers;

-- Lire un fichier directement dans le stage, avant de le charger
SELECT
    METADATA$FILENAME        AS fichier,
    METADATA$FILE_ROW_NUMBER AS ligne,
    $1, $2, $3, $4, $5
FROM @public.fichiers (FILE_FORMAT => 'public.csv_ff');

-- Un file format adapté : en-tête à ignorer, valeurs entre guillemets
CREATE OR REPLACE FILE FORMAT public.csv_entete_ff
    TYPE                         = 'CSV'
    SKIP_HEADER                  = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"';

-- Une table de staging, même structure que la table cible
CREATE OR REPLACE TRANSIENT TABLE raw_pos.franchise_staging LIKE raw_pos.franchise;

-- Tester le chargement sans rien charger
COPY INTO raw_pos.franchise_staging
FROM @public.fichiers
FILE_FORMAT = (FORMAT_NAME = 'public.csv_entete_ff')
VALIDATION_MODE = RETURN_ERRORS;

-- Comportement par défaut : le fichier en erreur n'est pas chargé
COPY INTO raw_pos.franchise_staging
FROM @public.fichiers
FILE_FORMAT = (FORMAT_NAME = 'public.csv_entete_ff');

-- Charger les lignes valides, écarter les autres
COPY INTO raw_pos.franchise_staging
FROM @public.fichiers
FILE_FORMAT = (FORMAT_NAME = 'public.csv_entete_ff')
ON_ERROR = CONTINUE;

SELECT * FROM raw_pos.franchise_staging;

-- Les lignes rejetées par le dernier chargement
SELECT * FROM TABLE(VALIDATE(raw_pos.franchise_staging, JOB_ID => '_last'));

-- Filtrer les fichiers d'un stage avec une expression régulière
LIST @public.s3load/raw_pos/ PATTERN = '.*menu.*';

-- Le menu dans une table de staging : elle servira au pipeline du module 07
CREATE OR REPLACE TRANSIENT TABLE raw_pos.menu_staging LIKE raw_pos.menu;

COPY INTO raw_pos.menu_staging
FROM @public.s3load/raw_pos/menu/;

/*==================================================================================================
  STOCKAGE
==================================================================================================*/

-- Trois types de tables
CREATE OR REPLACE TABLE           public.demo_permanente (id NUMBER);
CREATE OR REPLACE TRANSIENT TABLE public.demo_transient  (id NUMBER);
CREATE OR REPLACE TEMPORARY TABLE public.demo_temporaire (id NUMBER);

SHOW TABLES LIKE 'DEMO_%' IN SCHEMA public;   -- colonnes kind et retention_time

-- Durée de time travel d'une table permanente (1 jour par défaut, jusqu'à 90 en Enterprise)
ALTER TABLE public.demo_permanente SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- Séquence : des identifiants uniques
CREATE OR REPLACE SEQUENCE public.demo_seq START = 1 INCREMENT = 1;

SELECT public.demo_seq.NEXTVAL AS id;
SELECT public.demo_seq.NEXTVAL AS id;

-- Colonne auto-incrémentée
CREATE OR REPLACE TABLE public.demo_identity
(
    id      NUMBER IDENTITY(1, 1),
    libelle VARCHAR
);

INSERT INTO public.demo_identity (libelle) VALUES ('premier'), ('second');

SELECT * FROM public.demo_identity;

-- Nettoyage
DROP TABLE IF EXISTS public.demo_permanente;
DROP TABLE IF EXISTS public.demo_transient;
DROP TABLE IF EXISTS public.demo_temporaire;
DROP TABLE IF EXISTS public.demo_identity;
DROP SEQUENCE IF EXISTS public.demo_seq;

/*==================================================================================================
  DONNÉES SEMI-STRUCTURÉES
==================================================================================================*/

-- Une colonne VARIANT
SELECT TOP 10
    truck_brand_name,
    menu_item_name,
    menu_item_health_metrics_obj
FROM raw_pos.menu;

SHOW COLUMNS IN raw_pos.menu;

-- Accéder à un attribut : notation « : »
SELECT
    menu_item_health_metrics_obj:menu_item_id              AS menu_item_id,
    menu_item_health_metrics_obj:menu_item_health_metrics  AS menu_item_health_metrics
FROM raw_pos.menu;

-- Accéder à un élément de tableau : notation « [] », puis typer avec « :: »
SELECT
    menu_item_name,
    menu_item_health_metrics_obj:menu_item_id::INTEGER                           AS menu_item_id,
    menu_item_health_metrics_obj:menu_item_health_metrics[0]:ingredients::ARRAY  AS ingredients
FROM raw_pos.menu;

-- Notation équivalente entre crochets
SELECT
    menu_item_name,
    menu_item_health_metrics_obj['menu_item_id']::INTEGER AS menu_item_id
FROM raw_pos.menu;

-- FLATTEN : une ligne par élément du tableau
SELECT
    m.menu_item_name,
    m.menu_item_health_metrics_obj:menu_item_id::INTEGER AS menu_item_id,
    obj.value:ingredients::ARRAY                         AS ingredients,
    obj.value:is_healthy_flag::VARCHAR(1)                AS is_healthy_flag,
    obj.value:is_gluten_free_flag::VARCHAR(1)            AS is_gluten_free_flag,
    obj.value:is_dairy_free_flag::VARCHAR(1)             AS is_dairy_free_flag,
    obj.value:is_nut_free_flag::VARCHAR(1)               AS is_nut_free_flag
FROM raw_pos.menu m,
    LATERAL FLATTEN(INPUT => m.menu_item_health_metrics_obj:menu_item_health_metrics) obj;

-- Deux niveaux de FLATTEN : une ligne par ingrédient
SELECT
    m.menu_item_name,
    i.value::STRING AS ingredient
FROM raw_pos.menu m,
    LATERAL FLATTEN(INPUT => m.menu_item_health_metrics_obj:menu_item_health_metrics) obj,
    LATERAL FLATTEN(INPUT => obj.value:ingredients) i;

-- Exposer le résultat dans les couches harmonized et analytics
CREATE OR REPLACE VIEW harmonized.menu_v
    COMMENT = 'Menu avec ingrédients et restrictions alimentaires'
AS
SELECT
    m.menu_id,
    m.menu_type_id,
    m.menu_type,
    m.truck_brand_name,
    m.menu_item_health_metrics_obj:menu_item_id::INTEGER AS menu_item_id,
    m.menu_item_name,
    m.item_category,
    m.item_subcategory,
    m.cost_of_goods_usd,
    m.sale_price_usd,
    obj.value:ingredients::ARRAY              AS ingredients,
    obj.value:is_healthy_flag::VARCHAR(1)     AS is_healthy_flag,
    obj.value:is_gluten_free_flag::VARCHAR(1) AS is_gluten_free_flag,
    obj.value:is_dairy_free_flag::VARCHAR(1)  AS is_dairy_free_flag,
    obj.value:is_nut_free_flag::VARCHAR(1)    AS is_nut_free_flag
FROM raw_pos.menu m,
    LATERAL FLATTEN(INPUT => m.menu_item_health_metrics_obj:menu_item_health_metrics) obj;

CREATE OR REPLACE VIEW analytics.menu_v
    COMMENT = 'Menu avec ingrédients et restrictions alimentaires'
AS
SELECT *
    EXCLUDE (menu_type_id)
    RENAME (truck_brand_name AS brand_name)
FROM harmonized.menu_v;

-- Fonctions de tableaux, côté analyste
USE ROLE tb_analyst;
USE SECONDARY ROLES NONE;   -- seuls les droits de tb_analyst comptent
USE WAREHOUSE tb_analyst_wh;

-- Les plats qui contiennent de la laitue
SELECT menu_item_name, ingredients
FROM tb_101.analytics.menu_v
WHERE ARRAY_CONTAINS('Lettuce'::VARIANT, ingredients);

-- Les ingrédients communs entre plats de marques différentes
SELECT
    m1.brand_name,
    m1.menu_item_name,
    m2.brand_name     AS overlap_brand,
    m2.menu_item_name AS overlap_menu_item_name,
    ARRAY_INTERSECTION(m1.ingredients, m2.ingredients) AS overlapping_ingredients
FROM tb_101.analytics.menu_v m1
JOIN tb_101.analytics.menu_v m2
    ON  m1.menu_item_id <> m2.menu_item_id
    AND m1.menu_type    <> m2.menu_type
WHERE m1.item_category <> 'Beverage'
  AND ARRAYS_OVERLAP(m1.ingredients, m2.ingredients)
ORDER BY ARRAY_SIZE(overlapping_ingredients) DESC;

-- Indicateurs par marque
SELECT
    brand_name,
    COUNT(DISTINCT menu_item_id)                              AS total_menu_items,
    SUM(CASE WHEN is_gluten_free_flag = 'Y' THEN 1 ELSE 0 END) AS gluten_free_item_count,
    SUM(CASE WHEN is_dairy_free_flag  = 'Y' THEN 1 ELSE 0 END) AS dairy_free_item_count,
    SUM(CASE WHEN is_nut_free_flag    = 'Y' THEN 1 ELSE 0 END) AS nut_free_item_count
FROM tb_101.analytics.menu_v
GROUP BY brand_name
ORDER BY brand_name;

-- Retour au comportement par défaut : tous les roles de l'utilisateur sont actifs
USE SECONDARY ROLES ALL;
