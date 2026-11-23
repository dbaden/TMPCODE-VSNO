"""
VSNO - Module 04 : Snowpark, la même requête en Python.
Exécution depuis le terminal :  python ventes_par_marque.py
"""
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, count_distinct, sum as sum_

# Ouvrir une session avec la connexion déclarée dans ~/.snowflake/connections.toml
session = Session.builder.config("connection_name", "vsno").create()
session.query_tag = "vsno-m04"

# Fixer le contexte, comme les USE … d'un script SQL
session.use_role("tb_data_engineer")
session.use_warehouse("tb_de_wh")
session.use_database("tb_101")

# Décrire le calcul : rien n'est encore exécuté
orders = session.table("analytics.orders_v")

ventes = (
    orders
    .group_by("truck_brand_name")
    .agg(
        count_distinct("order_id").alias("order_count"),
        sum_("price").alias("total_sales"),
    )
    .sort(col("total_sales").desc())
)

# Afficher la requête SQL que Snowpark enverra à Snowflake
print(ventes.queries["queries"][-1])

# Exécuter et afficher les 10 premières lignes
ventes.show(10)

# Récupérer le résultat en DataFrame pandas
df = ventes.to_pandas()
print(df.head())

# Enregistrer le résultat dans une table, pour les collègues
ventes.write.save_as_table("analytics.ventes_par_marque", mode="overwrite")

session.close()
