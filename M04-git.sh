# VSNO - Module 04 : versionner son travail avec Git
# Commandes à exécuter dans le terminal de VS Code, une par une.

# Créer un projet
mkdir -p /lab/tasty-bytes/
cd /lab/tasty-bytes/
touch README.md .gitignore

# Configurer git lors de la première utilisation
git config --global user.name "<PRENOM NOM>"
git config --global user.email "<EMAIL>"

# Versionner le projet avec git
git init -b main
git status
git add .
git commit -m "Mon premier commit"
git log --oneline

# Exclure ce qui ne doit jamais être versionné :
# copier ces lignes dans .gitignore, puis enregistrer
# la modification depuis le panneau Source Control de VS Code
#
# .gitignore
# *.p8
# *.pem
# connections.toml
# .env
# __pycache__/

# --- Partager avec GitHub ---

# Git lit le token GitHub dans les variables d'environnement
git config --global credential.helper \
  '!f() { test "$1" = get && echo "username=${GITHUB_USER}" && echo "password=${GITHUB_TOKEN}"; }; f'

# Récupérer le dépôt dans /lab
cd /lab
git clone "https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
cd "${GITHUB_REPO}"

# Travailler dans un dossier à son nom
mkdir -p <prenom-nom>
echo "# <PRENOM NOM>" > <prenom-nom>/README.md
git add .
git commit -m "Dossier de <PRENOM NOM>"

# Récupérer d'abord les commits des autres, puis envoyer les siens
git pull --rebase
git push
