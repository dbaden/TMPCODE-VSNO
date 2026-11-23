/***************************************************************************************************
  VSNO - Module 02 : premiers pas avec l'extension Snowflake
  À exécuter dans VS Code, section par section.
***************************************************************************************************/

/*--
  Contexte de la session
  Qui suis-je, avec quel role, sur quel warehouse, dans quelle database ?
--*/
SELECT
    CURRENT_ACCOUNT()   AS account,
    CURRENT_USER()      AS user_name,
    CURRENT_ROLE()      AS role,
    CURRENT_WAREHOUSE() AS warehouse,
    CURRENT_DATABASE()  AS database;

/*--
  Fixer le contexte en tête de script
  Le script ne dépend plus des réglages de l'interface : il donne le même résultat partout.
--*/
USE ROLE accountadmin;
USE WAREHOUSE compute_wh;

/*--
  Étiqueter ses requêtes
  Le query tag permet de retrouver facilement ses requêtes dans l'historique.
--*/
ALTER SESSION SET QUERY_TAG = 'vsno-m02';

/*--
  Requête miroir
  À exécuter ici, puis à l'identique dans une feuille de calcul Snowsight.
--*/
SELECT
    c_mktsegment,
    COUNT(*) AS nb_clients
FROM snowflake_sample_data.tpch_sf1.customer
GROUP BY c_mktsegment
ORDER BY nb_clients DESC;

/*--
  Explorer le compte
--*/
SHOW DATABASES;
SHOW WAREHOUSES;
