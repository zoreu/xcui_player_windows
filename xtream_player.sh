#!/bin/bash
# xtream_player.sh - Xtream Codes Player para Linux
# Compatível com: Ubuntu, Debian, Fedora, Arch Linux

set -eo pipefail

# ===== CONFIGURAÇÕES =====
VERSION="1.0.0"
CONFIG_FILE="$HOME/.xtream_player.conf"

# Players suportados (ordem de preferência)
PLAYERS=("vlc" "mpv" "ffplay" "mplayer")
SELECTED_PLAYER=""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Variáveis globais
SERVER_URL=""
USERNAME=""
PASSWORD=""
BASE_URL=""

# Cache
CACHE_DIR="$HOME/.cache/xtream_player"
LIVE_CACHE="$CACHE_DIR/live.json"
VOD_CACHE="$CACHE_DIR/vod.json"
SERIES_CACHE="$CACHE_DIR/series.json"
LIVE_CATS_CACHE="$CACHE_DIR/live_cats.json"
VOD_CATS_CACHE="$CACHE_DIR/vod_cats.json"
SERIES_CATS_CACHE="$CACHE_DIR/series_cats.json"

# ===== FUNÇÕES AUXILIARES =====

print_header() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}         XTREAM CODES PLAYER - Linux v${VERSION}${NC}${CYAN}              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_error() {
    echo -e "${RED}✗ Erro: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# ===== DEPENDÊNCIAS =====

check_dependencies() {
    local missing=()
    
    # jq é obrigatório para JSON
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    # curl é obrigatório para requisições
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi
    
    # Verificar pelo menos um player
    local player_found=false
    for player in "${PLAYERS[@]}"; do
        if command -v "$player" &> /dev/null; then
            SELECTED_PLAYER="$player"
            player_found=true
            break
        fi
    done
    
    if [ "$player_found" = false ]; then
        print_error "Nenhum player de vídeo encontrado!"
        echo "Instale um dos seguintes: ${PLAYERS[*]}"
        missing+=("vlc/mpv/ffplay/mplayer")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Dependências faltando: ${missing[*]}"
        echo
        echo "Instale com:"
        echo "  Ubuntu/Debian: sudo apt install jq curl vlc"
        echo "  Fedora:        sudo dnf install jq curl vlc"
        echo "  Arch:          sudo pacman -S jq curl vlc"
        exit 1
    fi
    
    print_success "Dependências OK (Player: $SELECTED_PLAYER)"
    return 0
}

# ===== CACHE =====

init_cache() {
    mkdir -p "$CACHE_DIR"
}

clear_cache() {
    rm -f "$LIVE_CACHE" "$VOD_CACHE" "$SERIES_CACHE"
    rm -f "$LIVE_CATS_CACHE" "$VOD_CATS_CACHE" "$SERIES_CATS_CACHE"
    print_success "Cache limpo"
}

# ===== CONFIGURAÇÃO =====

save_config() {
    cat > "$CONFIG_FILE" <<EOF
SERVER_URL="$SERVER_URL"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
SELECTED_PLAYER="$SELECTED_PLAYER"
EOF
    chmod 600 "$CONFIG_FILE"
    print_success "Configuração salva"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# ===== API XTREAM =====

api_call() {
    local url="$1"
    local output="$2"
    
    if ! curl -s -f -m 30 "$url" -o "$output" 2>/dev/null; then
        return 1
    fi
    
    # Verificar se é JSON válido
    if ! jq empty "$output" 2>/dev/null; then
        return 1
    fi
    
    return 0
}

authenticate() {
    print_info "Conectando ao servidor..."
    
    local auth_url="${SERVER_URL}/player_api.php?username=${USERNAME}&password=${PASSWORD}"
    local temp_file=$(mktemp)
    
    if api_call "$auth_url" "$temp_file"; then
        local status=$(jq -r '.user_info.status // "error"' "$temp_file")
        rm -f "$temp_file"
        
        if [ "$status" = "Active" ]; then
            BASE_URL="$SERVER_URL"
            print_success "Conectado com sucesso!"
            return 0
        fi
    fi
    
    rm -f "$temp_file"
    print_error "Falha na autenticação"
    return 1
}

get_live_streams() {
    local category_id="$1"
    local url="${BASE_URL}/player_api.php?username=${USERNAME}&password=${PASSWORD}&action=get_live_streams"
    
    if [ -n "$category_id" ]; then
        url="${url}&category_id=${category_id}"
    fi
    
    if [ -z "$category_id" ] && [ -f "$LIVE_CACHE" ]; then
        return 0
    fi
    
    print_info "Carregando canais..."
    api_call "$url" "$LIVE_CACHE"
}

get_vod_streams() {
    local category_id="$1"
    local url="${BASE_URL}/player_api.php?username=${USERNAME}&password=${PASSWORD}&action=get_vod_streams"
    
    if [ -n "$category_id" ]; then
        url="${url}&category_id=${category_id}"
    fi
    
    if [ -z "$category_id" ] && [ -f "$VOD_CACHE" ]; then
        return 0
    fi
    
    print_info "Carregando filmes..."
    api_call "$url" "$VOD_CACHE"
}

get_series() {
    local category_id="$1"
    local url="${BASE_URL}/player_api.php?username=${USERNAME}&password=${PASSWORD}&action=get_series"
    
    if [ -n "$category_id" ]; then
        url="${url}&category_id=${category_id}"
    fi
    
    if [ -z "$category_id" ] && [ -f "$SERIES_CACHE" ]; then
        return 0
    fi
    
    print_info "Carregando séries..."
    api_call "$url" "$SERIES_CACHE"
}

get_categories() {
    local type="$1"  # live, vod, series
    local cache_file=""
    
    case "$type" in
        live)   cache_file="$LIVE_CATS_CACHE" ;;
        vod)    cache_file="$VOD_CATS_CACHE" ;;
        series) cache_file="$SERIES_CATS_CACHE" ;;
    esac
    
    if [ -f "$cache_file" ]; then
        return 0
    fi
    
    local url="${BASE_URL}/player_api.php?username=${USERNAME}&password=${PASSWORD}&action=get_${type}_categories"
    api_call "$url" "$cache_file"
}

get_series_info() {
    local series_id="$1"
    local url="${BASE_URL}/player_api.php?username=${USERNAME}&password=${PASSWORD}&action=get_series_info&series_id=${series_id}"
    local temp_file=$(mktemp)
    
    if api_call "$url" "$temp_file"; then
        cat "$temp_file"
        rm -f "$temp_file"
        return 0
    fi
    
    rm -f "$temp_file"
    return 1
}

# ===== PLAYER =====

play_stream() {
    local url="$1"
    local title="$2"
    
    print_info "Reproduzindo: $title"
    print_info "Player: $SELECTED_PLAYER"
    
    case "$SELECTED_PLAYER" in
        vlc)
            vlc "$url" --meta-title="$title" &>/dev/null &
            ;;
        mpv)
            mpv "$url" --title="$title" &>/dev/null &
            ;;
        ffplay)
            ffplay -window_title "$title" "$url" &>/dev/null &
            ;;
        mplayer)
            mplayer -title "$title" "$url" &>/dev/null &
            ;;
    esac
    
    print_success "Player iniciado"
}

# ===== INTERFACE - MENUS =====

select_player() {
    print_header
    echo -e "${BOLD}Selecione o player:${NC}"
    echo
    
    local available_players=()
    local i=1
    
    for player in "${PLAYERS[@]}"; do
        if command -v "$player" &> /dev/null; then
            available_players+=("$player")
            echo "  $i) $player"
            ((i++))
        fi
    done
    
    echo "  0) Voltar"
    echo
    read -p "Opção: " choice
    
    if [ "$choice" = "0" ]; then
        return
    fi
    
    if [ "$choice" -ge 1 ] && [ "$choice" -le "${#available_players[@]}" ]; then
        SELECTED_PLAYER="${available_players[$((choice-1))]}"
        print_success "Player selecionado: $SELECTED_PLAYER"
        save_config
        sleep 1
    fi
}

menu_categories() {
    local type="$1"
    local type_name="$2"
    local cache_file=""
    
    case "$type" in
        live)   cache_file="$LIVE_CATS_CACHE" ;;
        vod)    cache_file="$VOD_CATS_CACHE" ;;
        series) cache_file="$SERIES_CATS_CACHE" ;;
    esac
    
    while true; do
        print_header
        echo -e "${BOLD}Categorias - $type_name${NC}"
        echo
        
        get_categories "$type"
        
        if [ ! -f "$cache_file" ]; then
            print_error "Erro ao carregar categorias"
            read -p "Pressione ENTER para voltar..."
            return
        fi
        
        echo "  0) Todas as categorias"
        
        local categories=$(jq -r '.[] | "\(.category_id)|\(.category_name)"' "$cache_file" 2>/dev/null | head -30)
        
        if [ -z "$categories" ]; then
            print_warning "Nenhuma categoria encontrada"
            read -p "Pressione ENTER para voltar..."
            return
        fi
        
        local i=1
        while IFS='|' read -r cat_id cat_name; do
            [ -n "$cat_id" ] && echo "  $i) $cat_name"
            ((i++))
        done <<< "$categories"
        
        echo
        echo "  99) Voltar"
        echo
        read -p "Opção: " choice
        
        if [ "$choice" = "99" ]; then
            return
        fi
        
        if [ "$choice" = "0" ]; then
            browse_content "$type" "" "Todas - $type_name"
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            local selected_cat=$(echo "$categories" | sed -n "${choice}p")
            local cat_id=$(echo "$selected_cat" | cut -d'|' -f1)
            local cat_name=$(echo "$selected_cat" | cut -d'|' -f2)
            browse_content "$type" "$cat_id" "$cat_name"
        fi
    done
}

browse_content() {
    local type="$1"
    local category_id="$2"
    local category_name="$3"
    local cache_file=""
    
    case "$type" in
        live)   
            cache_file="$LIVE_CACHE"
            get_live_streams "$category_id"
            ;;
        vod)    
            cache_file="$VOD_CACHE"
            get_vod_streams "$category_id"
            ;;
        series) 
            cache_file="$SERIES_CACHE"
            get_series "$category_id"
            ;;
    esac
    
    if [ ! -f "$cache_file" ]; then
        print_error "Erro ao carregar conteúdo"
        read -p "Pressione ENTER para voltar..."
        return
    fi
    
    local page=1
    local per_page=15
    
    while true; do
        print_header
        echo -e "${BOLD}$category_name${NC}"
        echo
        
        # Filtrar por categoria se necessário
        local jq_filter=""
        if [ -n "$category_id" ]; then
            jq_filter=".[] | select(.category_id == \"$category_id\")"
        else
            jq_filter=".[]"
        fi
        
        local total=$(jq "[$jq_filter] | length" "$cache_file" 2>/dev/null || echo "0")
        
        if [ "$total" -eq 0 ]; then
            print_warning "Nenhum conteúdo encontrado"
            read -p "Pressione ENTER para voltar..."
            return
        fi
        
        local total_pages=$(( (total + per_page - 1) / per_page ))
        local start=$(( (page - 1) * per_page ))
        
        echo -e "Página ${page}/${total_pages} (Total: ${total})"
        echo
        
        local content=$(jq -r "[$jq_filter] | .[$start:$start+$per_page] | .[] | \"\(.stream_id // .series_id)|\(.name)\"" "$cache_file" 2>/dev/null)
        
        if [ -z "$content" ]; then
            print_warning "Nenhum item nesta página"
            read -p "Pressione ENTER para voltar..."
            return
        fi
        
        local i=1
        while IFS='|' read -r id name; do
            [ -n "$id" ] && echo "  $i) $name"
            ((i++))
        done <<< "$content"
        
        echo
        [ "$page" -gt 1 ] && echo "  p) Página anterior"
        [ "$page" -lt "$total_pages" ] && echo "  n) Próxima página"
        echo "  s) Buscar"
        echo "  0) Voltar"
        echo
        read -p "Opção: " choice
        
        if [ "$choice" = "0" ]; then
            return
        elif [ "$choice" = "p" ] && [ "$page" -gt 1 ]; then
            ((page--))
        elif [ "$choice" = "n" ] && [ "$page" -lt "$total_pages" ]; then
            ((page++))
        elif [ "$choice" = "s" ]; then
            search_content "$type"
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            local selected=$(echo "$content" | sed -n "${choice}p")
            local selected_id=$(echo "$selected" | cut -d'|' -f1)
            local selected_name=$(echo "$selected" | cut -d'|' -f2)
            
            if [ "$type" = "series" ]; then
                browse_series "$selected_id" "$selected_name"
            else
                play_content "$type" "$selected_id" "$selected_name"
            fi
        fi
    done
}

search_content() {
    local type="$1"
    
    print_header
    echo -e "${BOLD}Buscar${NC}"
    echo
    read -p "Digite o termo de busca: " search_term
    
    if [ -z "$search_term" ]; then
        return
    fi
    
    local cache_file=""
    case "$type" in
        live)   cache_file="$LIVE_CACHE" ;;
        vod)    cache_file="$VOD_CACHE" ;;
        series) cache_file="$SERIES_CACHE" ;;
    esac
    
    print_header
    echo -e "${BOLD}Resultados para: $search_term${NC}"
    echo
    
    local results=$(jq -r ".[] | select(.name | test(\"$search_term\"; \"i\")) | \"\(.stream_id // .series_id)|\(.name)\"" "$cache_file" 2>/dev/null | head -20)
    
    if [ -z "$results" ]; then
        print_warning "Nenhum resultado encontrado"
        read -p "Pressione ENTER para voltar..."
        return
    fi
    
    local i=1
    while IFS='|' read -r id name; do
        echo "  $i) $name"
        ((i++))
    done <<< "$results"
    
    echo
    echo "  0) Voltar"
    echo
    read -p "Selecione: " choice
    
    if [ "$choice" = "0" ]; then
        return
    fi
    
    if [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        local selected=$(echo "$results" | sed -n "${choice}p")
        local selected_id=$(echo "$selected" | cut -d'|' -f1)
        local selected_name=$(echo "$selected" | cut -d'|' -f2)
        
        if [ "$type" = "series" ]; then
            browse_series "$selected_id" "$selected_name"
        else
            play_content "$type" "$selected_id" "$selected_name"
        fi
    fi
}

play_content() {
    local type="$1"
    local id="$2"
    local name="$3"
    
    local stream_url=""
    
    case "$type" in
        live)
            stream_url="${BASE_URL}/live/${USERNAME}/${PASSWORD}/${id}.ts"
            ;;
        vod)
            stream_url="${BASE_URL}/movie/${USERNAME}/${PASSWORD}/${id}.mp4"
            ;;
    esac
    
    print_header
    echo -e "${BOLD}Reproduzir${NC}"
    echo
    echo "Nome: $name"
    echo "Player: $SELECTED_PLAYER"
    echo
    read -p "Confirmar? (s/N): " confirm
    
    if [ "$confirm" = "s" ] || [ "$confirm" = "S" ]; then
        play_stream "$stream_url" "$name"
        sleep 2
    fi
}

browse_series() {
    local series_id="$1"
    local series_name="$2"
    
    print_info "Carregando informações da série..."
    
    local series_info=$(get_series_info "$series_id")
    
    if [ -z "$series_info" ]; then
        print_error "Erro ao carregar série"
        read -p "Pressione ENTER para voltar..."
        return
    fi
    
    # Salvar info temporariamente para debug
    local temp_series="/tmp/series_${series_id}.json"
    echo "$series_info" > "$temp_series"
    
    # Extrair temporadas - melhorado para ambos os formatos
    local seasons=""
    
    # Tentar formato 1: array seasons
    seasons=$(echo "$series_info" | jq -r '.seasons[]?.season_number // empty' 2>/dev/null | sort -n)
    
    # Se não encontrou, tentar formato 2: objeto episodes
    if [ -z "$seasons" ]; then
        seasons=$(echo "$series_info" | jq -r '.episodes | keys[]? // empty' 2>/dev/null | sort -n)
    fi
    
    # Se ainda não encontrou, tentar formato 3: episodes como array
    if [ -z "$seasons" ]; then
        seasons=$(echo "$series_info" | jq -r 'if .episodes then (.episodes | to_entries | .[].key) else empty end' 2>/dev/null | sort -n)
    fi
    
    if [ -z "$seasons" ]; then
        print_error "Nenhuma temporada encontrada"
        echo
        echo "Debug - Estrutura do JSON:"
        echo "$series_info" | jq -r 'keys' 2>/dev/null || echo "Erro ao parsear JSON"
        echo
        read -p "Pressione ENTER para voltar..."
        rm -f "$temp_series"
        return
    fi
    
    while true; do
        print_header
        echo -e "${BOLD}Série: $series_name${NC}"
        echo
        echo "Temporadas disponíveis:"
        echo
        
        local i=1
        while read -r season; do
            [ -n "$season" ] && echo "  $i) Temporada $season"
            ((i++))
        done <<< "$seasons"
        
        echo
        echo "  0) Voltar"
        echo
        read -p "Selecione a temporada: " choice
        
        if [ "$choice" = "0" ]; then
            rm -f "$temp_series"
            return
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            local selected_season=$(echo "$seasons" | sed -n "${choice}p")
            browse_episodes "$series_id" "$series_name" "$selected_season" "$temp_series"
        fi
    done
}

browse_episodes() {
    local series_id="$1"
    local series_name="$2"
    local season_num="$3"
    local series_file="$4"  # Arquivo temporário com o JSON
    
    # Extrair episódios da temporada - suporte a múltiplos formatos
    local episodes=""
    
    # Formato 1: seasons array com episodes
    episodes=$(jq -r --arg season "$season_num" '
        .seasons[]? | 
        select(.season_number == ($season | tonumber)) | 
        .episodes[]? | 
        "\(.id)|\(.episode_num // .episode)|\(.title // "Sem título")"
    ' "$series_file" 2>/dev/null)
    
    # Formato 2: episodes como objeto com chaves numéricas
    if [ -z "$episodes" ]; then
        episodes=$(jq -r --arg season "$season_num" '
            .episodes[$season][]? | 
            "\(.id)|\(.episode_num // .episode)|\(.title // "Sem título")"
        ' "$series_file" 2>/dev/null)
    fi
    
    # Formato 3: episodes direto como array
    if [ -z "$episodes" ]; then
        episodes=$(jq -r --arg season "$season_num" '
            .episodes[]? | 
            select(.season == ($season | tonumber)) | 
            "\(.id)|\(.episode_num // .episode)|\(.title // "Sem título")"
        ' "$series_file" 2>/dev/null)
    fi
    
    if [ -z "$episodes" ]; then
        print_error "Nenhum episódio encontrado"
        echo
        echo "Debug - Tentando extrair estrutura da temporada $season_num:"
        jq --arg season "$season_num" '.episodes[$season] // .seasons[] | select(.season_number == ($season | tonumber))' "$series_file" 2>/dev/null | head -20
        echo
        read -p "Pressione ENTER para voltar..."
        return
    fi
    
    local page=1
    local per_page=15
    local episodes_array=()
    
    # Ler episódios em array
    while IFS= read -r line; do
        [ -n "$line" ] && episodes_array+=("$line")
    done <<< "$episodes"
    
    local total=${#episodes_array[@]}
    local total_pages=$(( (total + per_page - 1) / per_page ))
    
    while true; do
        print_header
        echo -e "${BOLD}$series_name - Temporada $season_num${NC}"
        echo
        echo "Página ${page}/${total_pages} (Total: ${total} episódios)"
        echo
        
        local start=$(( (page - 1) * per_page ))
        local end=$(( start + per_page ))
        
        local i=1
        for idx in $(seq $start $((end - 1))); do
            if [ $idx -lt $total ]; then
                local ep_line="${episodes_array[$idx]}"
                local ep_id=$(echo "$ep_line" | cut -d'|' -f1)
                local ep_num=$(echo "$ep_line" | cut -d'|' -f2)
                local ep_title=$(echo "$ep_line" | cut -d'|' -f3)
                echo "  $i) E$ep_num - $ep_title"
            fi
            ((i++))
        done
        
        echo
        [ "$page" -gt 1 ] && echo "  p) Página anterior"
        [ "$page" -lt "$total_pages" ] && echo "  n) Próxima página"
        echo "  0) Voltar"
        echo
        read -p "Selecione o episódio: " choice
        
        if [ "$choice" = "0" ]; then
            return
        elif [ "$choice" = "p" ] && [ "$page" -gt 1 ]; then
            ((page--))
        elif [ "$choice" = "n" ] && [ "$page" -lt "$total_pages" ]; then
            ((page++))
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            local array_idx=$(( start + choice - 1 ))
            if [ $array_idx -lt $total ]; then
                local selected="${episodes_array[$array_idx]}"
                local ep_id=$(echo "$selected" | cut -d'|' -f1)
                local ep_num=$(echo "$selected" | cut -d'|' -f2)
                local ep_title=$(echo "$selected" | cut -d'|' -f3)
                
                play_episode "$series_name" "$season_num" "$ep_num" "$ep_title" "$ep_id"
            fi
        fi
    done
}

play_episode() {
    local series_name="$1"
    local season="$2"
    local episode="$3"
    local title="$4"
    local ep_id="$5"
    
    local stream_url="${BASE_URL}/series/${USERNAME}/${PASSWORD}/${ep_id}.mp4"
    
    print_header
    echo -e "${BOLD}Reproduzir Episódio${NC}"
    echo
    echo "Série: $series_name"
    echo "Temporada: $season"
    echo "Episódio: $episode"
    echo "Título: $title"
    echo "Player: $SELECTED_PLAYER"
    echo
    read -p "Confirmar? (s/N): " confirm
    
    if [ "$confirm" = "s" ] || [ "$confirm" = "S" ]; then
        play_stream "$stream_url" "$series_name - S${season}E${episode}"
        sleep 2
    fi
}

# ===== MENU PRINCIPAL =====

main_menu() {
    while true; do
        print_header
        
        if [ -n "$SERVER_URL" ]; then
            echo -e "${GREEN}✓ Conectado: $SERVER_URL${NC}"
            echo -e "  Usuário: $USERNAME"
            echo -e "  Player: $SELECTED_PLAYER"
        else
            echo -e "${RED}✗ Não conectado${NC}"
        fi
        
        echo
        echo -e "${BOLD}Menu Principal:${NC}"
        echo
        echo "  1) Configurar conexão"
        echo "  2) TV Ao Vivo"
        echo "  3) Filmes (VOD)"
        echo "  4) Séries"
        echo "  5) Selecionar player"
        echo "  6) Limpar cache"
        echo "  0) Sair"
        echo
        read -p "Opção: " choice
        
        case "$choice" in
            1) setup_connection ;;
            2) 
                if [ -n "$BASE_URL" ]; then
                    menu_categories "live" "TV Ao Vivo"
                else
                    print_error "Configure a conexão primeiro!"
                    sleep 2
                fi
                ;;
            3) 
                if [ -n "$BASE_URL" ]; then
                    menu_categories "vod" "Filmes"
                else
                    print_error "Configure a conexão primeiro!"
                    sleep 2
                fi
                ;;
            4) 
                if [ -n "$BASE_URL" ]; then
                    menu_categories "series" "Séries"
                else
                    print_error "Configure a conexão primeiro!"
                    sleep 2
                fi
                ;;
            5) select_player ;;
            6) clear_cache ;;
            0) 
                print_info "Saindo..."
                exit 0
                ;;
        esac
    done
}

setup_connection() {
    print_header
    echo -e "${BOLD}Configurar Conexão${NC}"
    echo
    
    read -p "Servidor (ex: http://server.com:8080): " SERVER_URL
    SERVER_URL="${SERVER_URL%/}"  # Remove trailing slash
    
    read -p "Usuário: " USERNAME
    read -sp "Senha: " PASSWORD
    echo
    
    if authenticate; then
        save_config
        
        print_info "Carregando dados..."
        get_categories "live"
        get_categories "vod"
        get_categories "series"
        get_live_streams ""
        get_vod_streams ""
        get_series ""
        
        print_success "Dados carregados!"
        sleep 2
    else
        SERVER_URL=""
        USERNAME=""
        PASSWORD=""
        BASE_URL=""
        sleep 2
    fi
}

# ===== MAIN =====

main() {
    check_dependencies
    init_cache
    load_config || true  # Não falhar se config não existir
    main_menu
}

# Executar
main "$@"
