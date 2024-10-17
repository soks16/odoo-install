#!/bin/bash

# Function to check dependencies
function check_dependencies() {
  echo "Vérification des dépendances nécessaires..."
  local dependencies=("git" "docker" "docker-compose" "nc" "sudo")
  for cmd in "${dependencies[@]}"; do
    if ! command -v $cmd &> /dev/null; then
      echo "Erreur : La commande '$cmd' n'est pas installée."
      exit 1
    fi
  done
  echo "Toutes les dépendances sont présentes."
}

# Appel de la fonction check_dependencies
check_dependencies

# Demander à l'utilisateur de choisir une version d'Odoo
echo "Veuillez choisir une version d'Odoo parmi les suivantes :"
select OE_VERSION in {11..18}; do
  if [[ -n "$OE_VERSION" ]]; then
    echo "Vous avez choisi la version Odoo $OE_VERSION."
    break
  else
    echo "Veuillez choisir un numéro valide."
  fi
done

case $OE_VERSION in
  11) POSTGRES_VERSION="9.6";;
  12|13) POSTGRES_VERSION="10";;
  14) POSTGRES_VERSION="12";;
  15) POSTGRES_VERSION="13";;
  16) POSTGRES_VERSION="14";;
  17|18) POSTGRES_VERSION="15";;
esac


while true; do
  read -p "Voulez-vous installer la version entreprise d'Odoo $OE_VERSION ? (oui/non) : " choix
  case $choix in
    [Oo][Uu][Ii] | [Yy][Ee][Ss]) IS_ENTERPRISE="True"; break;;
    [Nn][Oo][Nn] | [Nn][Oo]) IS_ENTERPRISE="False"; break;;
    *) echo "Veuillez répondre par oui ou non.";;
  esac
done

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
PROD_CONFIG="/opt/odoo${OE_VERSION}/config/${PROJECT_NAME}"
TEST_CONFIG="/opt/odoo${OE_VERSION}/config-test/${PROJECT_NAME}"
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

sudo chmod 755 $WEB_DIR
sudo chmod 755 $BRAND_DIR
sudo chmod 755 $SERVER_TOOLS_DIR


# Cloner les dépôts Git
echo "Clonage des dépôts Git..."
sudo git clone --depth 1 --branch $GIT_VERSION $REP_OCA_WEB $WEB_DIR 
sudo git clone --depth 1 --branch $GIT_VERSION $REP_OCA_BRAND $BRAND_DIR 
sudo git clone --depth 1 --branch $GIT_VERSION $REP_OCA_SERVER_TOOLS $SERVER_TOOLS_DIR 

if [ $IS_ENTERPRISE = "True" ]; then
  echo "Clone Enterprise version..."
  sudo git clone --depth 1 --branch $GIT_VERSION $REP_ENTERPRISE $ENTERPRISE_DIR
  sudo chmod 755 $ENTERPRISE_DIR
fi


function is_port_in_use() {
  nc -z localhost "$1" 2>/dev/null
}

CUSTOM_PORT_T=2
CUSTOM_PORT_P=1

# Set initial ports
TEST_PORT=${CUSTOM_PORT_T}00${OE_VERSION}
PROD_PORT=${CUSTOM_PORT_P}00${OE_VERSION}

function find_available_port() {
  local base_port=$1
  while is_port_in_use $base_port; do
    base_port=$((base_port + 1000))  # Increment by 1 instead of 1000
  done
  echo $base_port
}

# Créer ou mettre à jour le fichier odoo.conf
echo "Création du fichier odoo.conf..."
sudo tee $SRC_CONFIG > /dev/null <<EOL
[options]
admin_passwd = ODOO@ADMIN
db_host = ${PROJECT_NAME}_V${OE_VERSION}_db
db_port = 5432
db_user = odoo
db_password = ${PASS_DB}
;addons_path = /mnt/extra-addons/theme,/mnt/extra-addons/custom,/mnt/extra-addons/OCA/web
addons_path = /mnt/enterprise,/mnt/extra-addons/custom
;dbfilter = ^${PROJECT_NAME}_V${OE_VERSION}_PROD$
;dbfilter = ^${PROJECT_NAME}_V${OE_VERSION}_TEST$
logfile = /var/log/odoo/odoo-server.log
log_db = True
workers = 4
;max_cron_threads = 1
; WebSocket settings
;evented = True
;evented_port = 8072
;xmlrpc_port = $(find_available_port $TEST_PORT)
;xmlrpc_port = $(find_available_port $PROD_PORT)
;session_gc = True
;session_timeout = 7200
;session_cookie_samesite = None 
;session_store = redis
;redis_url = redis://<redis_host>:<redis_port>
EOL
echo "Le fichier odoo.conf a été créé."

# Si l'utilisateur choisit d'installer deux instances
if [ "$INSTALL_TWO_INSTANCES" = "yes" ]; then
  # Créer les répertoires de configuration pour production et test
  # Définir les bonnes permissions (optionnel)
  PROD_PORT=$(find_available_port $PROD_PORT)
  TEST_PORT=$(find_available_port $TEST_PORT)
  sudo mkdir -p $TEST_CONFIG 
  sudo mkdir -p $PROD_CONFIG

  sudo touch /opt/odoo${OE_VERSION}/odoo-log-test/${PROJECT_NAME}/odoo-server.log

  # Copier le fichier de configuration vers les répertoires respectifs
  echo "Copie du fichier odoo.conf vers /opt/odoo${OE_VERSION}/config/${PROJECT_NAME} pour la production..."
  sudo cp $SRC_CONFIG $PROD_CONFIG/odoo.conf && echo "Copie vers la configuration de production réussie."
  sudo chmod 644 $PROD_CONFIG/odoo.conf
  
  echo "Copie du fichier odoo.conf vers /opt/odoo${OE_VERSION}/config-test/${PROJECT_NAME} pour le test..."
  sudo mv $SRC_CONFIG $TEST_CONFIG/odoo.conf && echo "Copie vers la configuration de test réussie."
  sudo chmod 644 $TEST_CONFIG/odoo.conf
  sudo chmod 755 -R $PROD_CONFIG
  sudo chmod 755 -R $TEST_CONFIG

  # Créer docker-compose.yml avec odoo_prod et odoo_test
  sudo tee $COMPOSE_FILE > /dev/null <<EOL
version: '3'

services:
  postgres:
    image: postgres:$POSTGRES_VERSION
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_db
    environment:
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=${PASS_DB}
      - POSTGRES_DB=postgres
    volumes:
      - /opt/odoo${OE_VERSION}/odoo-db-data/${PROJECT_NAME}:/var/lib/postgresql/data
    networks:
      - odoo-network
    restart: always

  odoo_prod:
    image: odoo:${GIT_VERSION}
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_prod
    depends_on:
      - postgres
    tty: true
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G 
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
      - /opt/odoo${OE_VERSION}/config/${PROJECT_NAME}:/etc/odoo
      - /opt/odoo${OE_VERSION}/odoo-log/${PROJECT_NAME}:/var/log/odoo
      - /opt/odoo${OE_VERSION}/odoo-web-data/${PROJECT_NAME}:/var/lib/odoo
      - "/opt/odoo${OE_VERSION}/odoo-web-data/${PROJECT_NAME}:/var/lib/odoo"
    ports:
      - "${PROD_PORT}:8069"
    networks:
      - odoo-network
    restart: always

  odoo_test:
    image: odoo:${GIT_VERSION}
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_test
    depends_on:
      - postgres
    tty: true
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G 
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
      - /opt/odoo${OE_VERSION}/config-test/${PROJECT_NAME}:/etc/odoo
      - /opt/odoo${OE_VERSION}/odoo-log-test/${PROJECT_NAME}:/var/log/odoo
      - "/opt/odoo${OE_VERSION}/odoo-web-data/${PROJECT_NAME}:/var/lib/odoo"
    ports:
      - "${TEST_PORT}:8069"
    networks:
      - odoo-network
    restart: always
    
volumes:
  - odoo-db-data-${PROJECT_NAME}:/var/lib/postgresql/data
  - odoo-web-data-${PROJECT_NAME}:/var/lib/odoo

networks:
  odoo-network:
EOL
  
else

  TEST_PORT=$(find_available_port $TEST_PORT)
  # Si l'utilisateur choisit d'installer uniquement une instance de test
  sudo mkdir -p $TEST_CONFIG
  sudo chmod 755 -R $TEST_CONFIG
  # Copier le fichier de configuration uniquement pour le test
  echo "Copie du fichier odoo.conf vers /opt/odoo${OE_VERSION}/config-test/${PROJECT_NAME} pour le test..."
  sudo mv $SRC_CONFIG $TEST_CONFIG/odoo.conf && echo "Copie vers la configuration de test réussie."
  sudo chmod 644 $TEST_CONFIG/odoo.conf
  
  # Créer docker-compose.yml avec seulement odoo_test
  sudo tee $COMPOSE_FILE > /dev/null <<EOL
version: '3'

services:
  postgres:
    image: postgres:$POSTGRES_VERSION
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_db
    environment:
      - POSTGRES_USER=odoo
      - POSTGRES_PASSWORD=${PASS_DB}
      - POSTGRES_DB=postgres
    volumes:
      - "/opt/odoo${OE_VERSION}/odoo-db-data/${PROJECT_NAME}:/var/lib/postgresql/data"
    networks:
      - odoo-network
    restart: always

  odoo_test:
    image: odoo:${GIT_VERSION}
    container_name: ${PROJECT_NAME}_V${OE_VERSION}_test
    depends_on:
      - postgres
    tty: true
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 2G 
    environment:
      - HOST=${PROJECT_NAME}_V${OE_VERSION}_db
      - USER=odoo
      - PASSWORD=${PASS_DB}
    volumes:
      - /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}:/mnt/extra-addons/custom
      - /opt/odoo${OE_VERSION}/custom/addons/theme:/mnt/extra-addons/theme
      - /opt/odoo${OE_VERSION}/OCA/brand:/mnt/extra-addons/OCA/brand
      - /opt/odoo${OE_VERSION}/OCA/server-tools:/mnt/extra-addons/OCA/server-tools
      - /opt/odoo${OE_VERSION}/OCA/web:/mnt/extra-addons/OCA/web
      - /opt/odoo${OE_VERSION}/enterprise/addons:/mnt/enterprise
      - /opt/odoo${OE_VERSION}/config-test/${PROJECT_NAME}:/etc/odoo
      - /opt/odoo${OE_VERSION}/odoo-log-test/${PROJECT_NAME}:/var/log/odoo
      - "/opt/odoo${OE_VERSION}/odoo-web-data/${PROJECT_NAME}:/var/lib/odoo"
    ports:
      - "${TEST_PORT}:8069"
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
sudo chmod 755 -R /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}
sudo mv $COMPOSE_FILE /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}/docker-compose.yml
sudo chmod 777 /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}/docker-compose.yml

# Afficher l'adresse IP de la machine physique et les ports
IP_ADDRESS=$(hostname -I | awk '{print $1}')  # Get the first IP address
echo "Les instances Odoo version ${GIT_VERSION} sont maintenant en cours d'exécution."
echo "Ports utilisés :"

if [ "$INSTALL_TWO_INSTANCES" = "yes" ]; then
  sudo chmod 777 -R /opt/odoo${OE_VERSION}
  echo "  - Production: http://$IP_ADDRESS:$PROD_PORT"
  echo "  - Test: http://$IP_ADDRESS:$TEST_PORT"
  echo "Pour des modifications sur les containers veuillez modifier le fichier docker-compose.yml et excuter la commande suivante:"
  echo "==> Chemin: cd /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}"
  echo "==> docker-compose -f docker-compose.yml -p ${PROJECT_NAME}_V${OE_VERSION} up -d"
  echo "==> File conf: nano /opt/odoo${OE_VERSION}/config/${PROJECT_NAME}/odoo.conf"
  echo "==> File conf: nano /opt/odoo${OE_VERSION}/config-test/${PROJECT_NAME}/odoo.conf"
else
  sudo chmod 777 -R /opt/odoo${OE_VERSION}
  echo "  - Test: http://$IP_ADDRESS:$TEST_PORT"
  echo "Pour des modifications sur les containers veuillez modifier le fichier docker-compose.yml et excuter la commande suivante:"
  echo "==> Chemin: cd /opt/odoo${OE_VERSION}/custom/addons/${PROJECT_NAME}"
  echo "==> Command: docker-compose -f docker-compose.yml -p ${PROJECT_NAME}_V${OE_VERSION} up -d"
  echo "==> File conf: nano /opt/odoo${OE_VERSION}/config-test/${PROJECT_NAME}/odoo.conf"
fi

