#!/bin/bash
set -e

COMPOSE_FILE="docker-compose.yaml"
PROJECT_NAME="tcc"
CONTAINER_NAME="code-server"

# Função para extrair variável do .env (não usa `source`)
get_env_var() {
  local key="$1"
  if [ -f ".env" ]; then
    # Remove espaços, filtra linhas que começam com a chave e pega o valor após "="
    # Suporta valores entre aspas (simples ou duplas) e sem aspas.
    local line
    line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" .env || true)
    if [ -n "$line" ]; then
      # extrai após '=' e remove possíveis aspas e espaços
      echo "$line" | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//; s/^[\"']?//; s/[\"']?$//"
      return 0
    fi
  fi
  return 1
}

# Detectar UID e GID do usuário atual
USER_ID=$(id -u)
GROUP_ID=$(id -g)

# Se .env não existir, criar com valores padrões
if [ ! -f .env ]; then
  echo "Arquivo .env não encontrado — criando com valores padrão..."
  cat <<EOF > .env
PASSWORD=admin123
PUID=${USER_ID}
PGID=${GROUP_ID}
EOF
  chmod 600 .env
  echo "Arquivo .env criado com senha padrão: admin123 (altere em .env)"
fi

# Ler valores do .env
ENV_PASSWORD=$(get_env_var "PASSWORD" || true)
ENV_PUID=$(get_env_var "PUID" || true)
ENV_PGID=$(get_env_var "PGID" || true)

# Permitir sobrescrever a senha por argumento --password
CLI_PASSWORD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --password|--passwd)
      shift
      CLI_PASSWORD="$1"
      shift
      ;;
    build|up|down|logs|exec|restart|clean)
      # manter argumentos do comando principal; param será tratado depois
      break
      ;;
    *)
      # pula argumentos desconhecidos (serão tratados abaixo no case principal)
      break
      ;;
  esac
done

# Se foi passado na CLI, usa essa senha; caso contrário, usa do .env
if [ -n "$CLI_PASSWORD" ]; then
  PASSWORD_TO_USE="$CLI_PASSWORD"
else
  PASSWORD_TO_USE="$ENV_PASSWORD"
fi

# Se PUID/PGID no .env forem diferentes do host, preferir os valores do host
# (mas ninguém impede que .env especifique outros valores)
if [ -n "$ENV_PUID" ]; then
  PUID_TO_USE="$ENV_PUID"
else
  PUID_TO_USE="$USER_ID"
fi

if [ -n "$ENV_PGID" ]; then
  PGID_TO_USE="$ENV_PGID"
else
  PGID_TO_USE="$GROUP_ID"
fi

# Atualiza .env se PUID/PGID da máquina forem diferentes e .env diferente — facilita manter consistência.
# (Se .env foi criado pelo script, já contém os valores corretos.)
sed -i -E "s/^[[:space:]]*PUID[[:space:]]*=.*/PUID=${PUID_TO_USE}/" .env || true
sed -i -E "s/^[[:space:]]*PGID[[:space:]]*=.*/PGID=${PGID_TO_USE}/" .env || true
# Garante que PASSWORD esteja presente no .env (não sobrescreve se já existir)
if ! grep -Eq "^[[:space:]]*PASSWORD[[:space:]]*=" .env; then
  echo "PASSWORD=${PASSWORD_TO_USE}" >> .env
fi

# Segurança: garantir permissões do .env
chmod 600 .env || true

# Garantir que as pastas necessárias existam e tenham donas corretas
echo "Criando diretórios e ajustando permissões..."
mkdir -p config
# Ajusta dono de config e do workspace (diretório atual) para o UID/GID escolhidos
chown -R "${PUID_TO_USE}:${PGID_TO_USE}" config .
chmod -R u+rw config .

# Detectar engine padrão
ENGINE=""
if command -v podman &>/dev/null; then
  ENGINE="podman"
elif command -v docker &>/dev/null; then
  ENGINE="docker"
else
  echo "Erro: nem Podman nem Docker estão instalados."
  exit 1
fi

# Se usuário passar explicitamente
if [[ "$2" == "podman" || "$2" == "docker" ]]; then
  ENGINE="$2"
fi

# Voltar o cursor para o primeiro argumento (comando principal)
CMD="$1"

# Se CMD vazio, mostrar usage
if [ -z "$CMD" ]; then
  echo "Uso: $0 {build|up|down|logs|exec|restart|clean} [podman|docker] [--password novaSenha]"
  exit 1
fi

case "$CMD" in
  build)
    echo "🔧 Construindo imagem com $ENGINE (PUID=${PUID_TO_USE} PGID=${PGID_TO_USE})..."
    if [[ "$ENGINE" == "podman" ]]; then
      $ENGINE build --squash -t ${PROJECT_NAME}_code-server .
      podman-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" build
    else
      $ENGINE build --squash -t ${PROJECT_NAME}_code-server .
      docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" build
    fi
    # Limpar apenas imagens <none> criadas no build
    $ENGINE rmi $($ENGINE images -q --filter "reference=<none>") 2>/dev/null || true
    ;;
    
  up)
    echo "🚀 Subindo contêiner com $ENGINE-compose..."
    # lê novamente senha do .env antes de subir (caso tenha sido alterado)
    echo "Usando senha do .env para o Code Server (se definido)."
   if [[ "$ENGINE" == "podman" ]]; then
      podman-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    else
      docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    fi
    ;;
    
  down)
    echo "🧹 Derrubando contêiner..."
    if [[ "$ENGINE" == "podman" ]]; then
      podman-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
    else
      docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
    fi
    ;;
    
  logs)
    if [[ "$ENGINE" == "podman" ]]; then
      podman-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs -f
    else
      docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs -f
    fi
    ;;
    
  exec)
    echo "🔍 Acessando terminal dentro do contêiner..."
    $ENGINE exec -it "$CONTAINER_NAME" /bin/bash
    ;;
    
  restart)
    echo "🔄 Reiniciando contêiner..."
    if [[ "$ENGINE" == "podman" ]]; then
      podman-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
      podman-compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    else
      docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
      docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    fi
    ;;
      
  clean)
    echo "🧹 Limpando imagens <none> relacionadas ao build..."
    $ENGINE rmi $($ENGINE images -q --filter "reference=<none>") 2>/dev/null || true
    ;;
    
  *)
    echo "Uso: $0 {build|up|down|logs|exec|restart|clean} [podman|docker] [--password novaSenha]"
    exit 1
    ;;
esac
