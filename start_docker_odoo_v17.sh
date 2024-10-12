#!/bin/bash

OE_VERSION="17"
IS_ENTERPRISE="True"

REP_ENTERPRISE="https://github.com/soks16/enterprise.git"

REP_OCA_WEB="https://github.com/OCA/web.git"
REP_OCA_BRAND="https://github.com/OCA/brand.git"
REP_OCA_SERVER_TOOLS="https://github.com/OCA/server-tools.git"
PASS_DB="odoo@2024"
GIT_VERSION="${OE_VERSION}.0"

# Demander le nom du projet
while [[ -z "$PROJECT_NAME" ]]; do
  read -p "Nom du projet: " PROJECT_NAME
  if [[ -z "$PROJECT_NAME" ]]; then
    echo "Le nom du projet ne peut pas être vide. Veuillez entrer un nom valide."
  fi
done

# Demander si l'utilisateur veut installer deux instances
while true; do
  read -p "Combien d'instances voulez-vous installer ? (1 = TEST seulement, 2 = PROD et TEST) : " INSTALL_TWO_INSTANCES
  case $INSTALL_TWO_INSTANCES in
    1) INSTALL_TWO_INSTANCES="no"; break;;
    2) INSTALL_TWO_INSTANCES="yes"; break;;
    *) echo "Veuillez répondre par 1 ou 2.";;
  esac
done


# Définir les chemins de configuration et de clonage
PROD_CONFIG="/opt/odoo${OE_VERSION}/config/odoo.conf"
TEST_CONFIG="/opt/odoo${OE_VERSION}/config-test/odoo.conf"
SRC_CONFIG="./odoo.conf"
COMPOSE_FILE="./docker-compose.yml"

# Chemins des répertoires pour les dépôts Git
WEB_DIR="/opt/odoo${OE_VERSION}/OCA/web"
BRAND_DIR="/opt/odoo${OE_VERSION}/OCA/brand"
SERVER_TOOLS_DIR="/opt/odoo${OE_VERSION}/OCA/server-tools"
ENTERPRISE_DIR="/opt/odoo${OE_VERSION}/enterprise"

# Vérifier si le fichier SRC_CONFIG ou COMPOSE_FILE existe déjà, et le supprimer si oui
if [ -f "$SRC_CONFIG" ]; then
  sudo rm $SRC_CONFIG
fi

if [ -f "$COMPOSE_FILE" ]; then
  sudo rm $COMPOSE_FILE
fi

# Créer les répertoires pour les dépôts Git s'ils n'existent pas
sudo mkdir -p $WEB_DIR
sudo mkdir -p $BRAND_DIR
sudo mkdir -p $SERVER_TOOLS_DIR
sudo mkdir -p $ENTERPRISE_DIR

sudo chmod 777 $WEB_DIR
sudo chmod 777 $BRAND_DIR
sudo chmod 777 $SERVER_TOOLS_DIR


# Cloner les dépôts Git
echo "Clonage des dépôts Git..."
sudo git clone --depth 1 --branch $GIT_VERSION $REP_OCA_WEB $WEB_DIR
sudo git clone --depth 1 --branch $GIT_VERSION $REP_OCA_BRAND $BRAND_DIR
sudo git clone --depth 1 --branch $GIT_VERSION $REP_OCA_SERVER_TOOLS $SERVER_TOOLS_DIR

if [ $IS_ENTERPRISE = "True" ]; then
  echo "Clone Enterprise version..."
  sudo git clone --depth 1 --branch $GIT_VERSION $REP_ENTERPRISE $ENTERPRISE_DIR
fi

sudo chmod 777 $ENTERPRISE_DIR

# Créer ou mettre à jour le fichier odoo.conf
echo "Création du fichier odoo.conf..."
sudo tee $SRC_CONFIG > /dev/null <<EOL
[options]
admin_passwd = ODOO@ADMIN
db_host = ${PROJECT_NAME}_V${OE_VERSION}_db
db_port = 5432
db_user = odoo
db_password = ${PASS_DB}
addons_path = /mnt/enterprise,/mnt/extra-addons/custom
;dbfilter = ^${PROJECT_NAME}_PROD$
;dbfilter = ^${PROJECT_NAME}_TEST$
logfile = /var/log/odoo/odoo-server.log
log_db = True
EOL
echo "Le fichier odoo.conf a été créé."

# Si l'utilisateur choisit d'installer deux instances
if [ "$INSTALL_TWO_INSTANCES" = "yes" ]; then
  # Créer les répertoires de configuration pour production et test
  sudo mkdir -p /opt/odoo${OE_VERSION}/config /opt/odoo${OE_VERSION}/config-test

  # Copier le fichier de configuration vers les répertoires respectifs
  echo "Copie du fichier odoo.conf vers /opt/odoo${OE_VERSION}/config pour la production..."
  sudo cp $SRC_CONFIG $PROD_CONFIG && echo "Copie vers la configuration de production réussie."

  echo "Copie du fichier odoo.conf vers /opt/odoo${OE_VERSION}/config-test pour le test..."
  sudo cp $SRC_CONFIG $TEST_CONFIG && echo "Copie vers la configuration de test réussie."

  # Définir les bonnes permissions (optionnel)
  sudo chmod 777 $PROD_CONFIG
  sudo chmod 777 $TEST_CONFIG

  # Créer docker-compose.yml avec odoo_prod et odoo_test
  sudo tee $COMPOSE_FILE > /dev/null <<EOL
version: '3'

services:
  postgres:
    image: postgres:latest
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_db
    environment:
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=${PASS_DB}
      - POSTGRES_DB=postgres
    volumes:
      - /opt/odoo${OE_VERSION}/odoo-db-data:/var/lib/postgresql/data
    networks:
      - odoo-network
    restart: always

  odoo_prod:
    image: odoo:${OE_VERSION}
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_prod
    depends_on:
      - postgres
    tty: true
    environment:
      - HOST=${PROJECT_NAME}_V${OE_VERSION}_db
      - USER=odoo
      - PASSWORD=${PASS_DB}
    volumes:
      - /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}:/mnt/extra-addons/custom
      - /opt/odoo${OE_VERSION}/OCA/brand:/mnt/extra-addons/OCA/brand
      - /opt/odoo${OE_VERSION}/OCA/server-tools:/mnt/extra-addons/OCA/server-tools
      - /opt/odoo${OE_VERSION}/OCA/web:/mnt/extra-addons/OCA/web
      - /opt/odoo${OE_VERSION}/enterprise/addons:/mnt/enterprise
      - /opt/odoo${OE_VERSION}/config:/etc/odoo
      - /opt/odoo${OE_VERSION}/odoo-log:/var/log/odoo
    ports:
      - "100${OE_VERSION}:8069"
    networks:
      - odoo-network
    restart: always

  odoo_test:
    image: odoo:${OE_VERSION}
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_test
    depends_on:
      - postgres
    tty: true
    environment:
      - HOST=${PROJECT_NAME}_V${OE_VERSION}_db
      - USER=odoo
      - PASSWORD=${PASS_DB}
    volumes:
      - /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}:/mnt/extra-addons/custom
      - /opt/odoo${OE_VERSION}/OCA/brand:/mnt/extra-addons/OCA/brand
      - /opt/odoo${OE_VERSION}/OCA/server-tools:/mnt/extra-addons/OCA/server-tools
      - /opt/odoo${OE_VERSION}/OCA/web:/mnt/extra-addons/OCA/web
      - /opt/odoo${OE_VERSION}/enterprise/addons:/mnt/enterprise
      - /opt/odoo${OE_VERSION}/config-test:/etc/odoo
      - /opt/odoo${OE_VERSION}/odoo-log-test:/var/log/odoo
    ports:
      - "200${OE_VERSION}:8069"
    networks:
      - odoo-network
    restart: always

networks:
  odoo-network:
EOL

else
  # Si l'utilisateur choisit d'installer uniquement une instance de test
  sudo mkdir -p /opt/odoo${OE_VERSION}/config-test

  # Copier le fichier de configuration uniquement pour le test
  echo "Copie du fichier odoo.conf vers /opt/odoo${OE_VERSION}/config-test pour le test..."
  sudo cp $SRC_CONFIG $TEST_CONFIG && echo "Copie vers la configuration de test réussie."

  # Définir les bonnes permissions (optionnel)
  sudo chmod 777 $TEST_CONFIG

  # Créer docker-compose.yml avec seulement odoo_test
  sudo tee $COMPOSE_FILE > /dev/null <<EOL
version: '3'

services:
  postgres:
    image: postgres:latest
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_db
    environment:
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=${PASS_DB}
      - POSTGRES_DB=postgres
    volumes:
      - /opt/odoo${OE_VERSION}/odoo-db-data:/var/lib/postgresql/data
    networks:
      - odoo-network
    restart: always

  odoo_test:
    image: odoo:${OE_VERSION}
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_test
    depends_on:
      - postgres
    tty: true
    environment:
      - HOST=${PROJECT_NAME}_V${OE_VERSION}_db
      - USER=odoo
      - PASSWORD=${PASS_DB}
    volumes:
      - /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}:/mnt/extra-addons/custom
      - /opt/odoo${OE_VERSION}/OCA/brand:/mnt/extra-addons/OCA/brand
      - /opt/odoo${OE_VERSION}/OCA/server-tools:/mnt/extra-addons/OCA/server-tools
      - /opt/odoo${OE_VERSION}/OCA/web:/mnt/extra-addons/OCA/web
      - /opt/odoo${OE_VERSION}/enterprise/addons:/mnt/enterprise
      - /opt/odoo${OE_VERSION}/config-test:/etc/odoo
      - /opt/odoo${OE_VERSION}/odoo-log-test:/var/log/odoo
    ports:
      - "200${OE_VERSION}:8069"
    networks:
      - odoo-network
    restart: always

networks:
  odoo-network:
EOL

fi

# Lancer Docker Compose avec sudo et le nom du projet
echo "Démarrage de Docker Compose pour Odoo version ${OE_VERSION} avec le projet '${PROJECT_NAME}'..."
sudo docker-compose -f docker-compose.yml -p ${PROJECT_NAME}_V${OE_VERSION} up -d
sudo chmod -R 777 /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}

echo "Les instances Odoo version ${GIT_VERSION} sont maintenant en cours d'exécution."

