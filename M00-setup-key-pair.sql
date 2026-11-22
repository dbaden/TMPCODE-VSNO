/***************************************************************************************************
  VSNO - Module 00 : enregistrement de la clé publique
  À exécuter dans une feuille de calcul SQL de Snowsight.

  Avant d'exécuter, remplacer :
    <NOM_UTILISATEUR>  par le nom d'utilisateur choisi lors de l'activation du compte
    <CLE_PUBLIQUE>     par la clé publique affichée dans le terminal du conteneur
***************************************************************************************************/

USE ROLE accountadmin;

-- 1. Associer la clé publique à l'utilisateur
ALTER USER <NOM_UTILISATEUR> SET RSA_PUBLIC_KEY = '<CLE_PUBLIQUE>';

-- 2. Vérifier que la clé est enregistrée (la valeur RSA_PUBLIC_KEY_FP ne doit pas être vide)
DESC USER <NOM_UTILISATEUR>
    ->> SELECT "property", "value" FROM $1 WHERE "property" = 'RSA_PUBLIC_KEY_FP';

-- 3. Informations à reporter dans le fichier de configuration de la connexion
SELECT
    CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS account,
    CURRENT_USER()      AS user_name,
    CURRENT_ROLE()      AS role,
    CURRENT_WAREHOUSE() AS warehouse;
