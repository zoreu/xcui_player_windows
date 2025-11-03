#requires -Version 5.1
# XtreamPlayer_PS5.ps1 - Versão compatível PowerShell 5.1 - CORRIGIDO

# Corrigir codificação UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Caminho do VLC (padrão) e configuração do player
$script:VlcPath = "C:\Program Files\VideoLAN\VLC\vlc.exe"
$script:PlayerSelecionado = "Windows Media Player"  # Padrão: VLC, alternativas: "Windows Media Player"

# -------------------------
# Variaveis globais
# -------------------------
$script:ServerURL = ""
$script:Username = ""
$script:Password = ""
$script:BaseURL = ""

$script:Canais = @()
$script:Filmes = @()
$script:Series = @()
$script:CategoriasTV = @()
$script:CategoriasFilmes = @()
$script:CategoriasSeries = @()

# Cache para evitar chamadas repetidas
$script:CacheCanais = @{}
$script:CacheFilmes = @{}
$script:CacheSeries = @{}
$script:DadosCarregados = $false

# -------------------------
# Funcoes de API / util
# -------------------------
function Invoke-Xtream {
    param([string]$url)
    try {
        Write-Host "Fazendo requisicao para: $url" -ForegroundColor Gray
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        return $response
    } catch {
        Write-Host "Erro na requisicao: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-XtreamAuth {
    param([string]$url, [string]$username, [string]$password)
    $authUrl = "$url/player_api.php?username=$username&password=$password"
    return Invoke-Xtream -url $authUrl
}

function Get-LiveStreams {
    param([string]$categoryId = "")
    
    # Usar cache se disponível
    if ($categoryId -eq "" -and $script:Canais.Count -gt 0) {
        return $script:Canais
    }
    
    $url = "$script:BaseURL/player_api.php?username=$script:Username&password=$script:Password&action=get_live_streams"
    if ($categoryId -and $categoryId -ne "") { 
        $url = $url + "&category_id=" + $categoryId 
    }
    
    $resultado = Invoke-Xtream -url $url
    if ($categoryId -eq "" -and $resultado) {
        $script:Canais = $resultado
    }
    
    return $resultado
}

function Get-VODStreams {
    param([string]$categoryId = "")
    
    # Usar cache se disponível
    if ($categoryId -eq "" -and $script:Filmes.Count -gt 0) {
        return $script:Filmes
    }
    
    $url = "$script:BaseURL/player_api.php?username=$script:Username&password=$script:Password&action=get_vod_streams"
    if ($categoryId -and $categoryId -ne "") { 
        $url = $url + "&category_id=" + $categoryId 
    }
    
    $resultado = Invoke-Xtream -url $url
    if ($categoryId -eq "" -and $resultado) {
        $script:Filmes = $resultado
    }
    
    return $resultado
}

function Get-Series {
    param([string]$categoryId = "")
    
    # Usar cache se disponível
    if ($categoryId -eq "" -and $script:Series.Count -gt 0) {
        return $script:Series
    }
    
    $url = "$script:BaseURL/player_api.php?username=$script:Username&password=$script:Password&action=get_series"
    if ($categoryId -and $categoryId -ne "") { 
        $url = $url + "&category_id=" + $categoryId 
    }
    
    $resultado = Invoke-Xtream -url $url
    if ($categoryId -eq "" -and $resultado) {
        $script:Series = $resultado
    }
    
    return $resultado
}

function Get-Categories {
    param([string]$type = "live")
    
    # Verificar se já temos as categorias em cache
    if ($type -eq "live" -and $script:CategoriasTV.Count -gt 0) {
        return $script:CategoriasTV
    }
    elseif ($type -eq "vod" -and $script:CategoriasFilmes.Count -gt 0) {
        return $script:CategoriasFilmes
    }
    elseif ($type -eq "series" -and $script:CategoriasSeries.Count -gt 0) {
        return $script:CategoriasSeries
    }
    
    $url = "$script:BaseURL/player_api.php?username=$script:Username&password=$script:Password&action=get_${type}_categories"
    $resultado = Invoke-Xtream -url $url
    
    # Armazenar em cache
    if ($resultado) {
        switch ($type) {
            "live" { $script:CategoriasTV = $resultado }
            "vod" { $script:CategoriasFilmes = $resultado }
            "series" { $script:CategoriasSeries = $resultado }
        }
    }
    
    return $resultado
}

# -------------------------
# Funcoes de Series / Temporadas / Episodios (compatíveis PS5) - CORRIGIDAS
# -------------------------
function Get-SeriesInfo {
    param([string]$seriesId)
    $url = "$script:BaseURL/player_api.php?username=$script:Username&password=$script:Password&action=get_series_info&series_id=$seriesId"
    Write-Host "Buscando informacoes da serie ID: $seriesId" -ForegroundColor Yellow
    $response = Invoke-Xtream -url $url
    if ($response) { 
        Write-Host "Informacoes da serie obtidas com sucesso" -ForegroundColor Green
    }
    return $response
}

function Get-Seasons {
    param([object]$seriesInfo)
    $temporadas = @()
    if (-not $seriesInfo) { 
        Write-Host "SeriesInfo está vazio" -ForegroundColor Yellow
        return $temporadas 
    }

    try {
        Write-Host "Analisando estrutura das temporadas..." -ForegroundColor Gray
        
        # Nova estrutura: seasons array (que é o caso da sua API)
        if ($seriesInfo.seasons -and ($seriesInfo.seasons -is [System.Array])) {
            Write-Host "Encontrada estrutura 'seasons' com $($seriesInfo.seasons.Count) temporadas" -ForegroundColor Green
            foreach ($season in $seriesInfo.seasons) {
                if ($season.season_number -ne $null) {
                    $temporadas += $season.season_number
                }
            }
            $temporadas = $temporadas | Sort-Object
        }
        # Estrutura antiga: episodes como PSCustomObject
        elseif ($seriesInfo.episodes -and ($seriesInfo.episodes -is [PSCustomObject])) {
            Write-Host "Encontrada estrutura 'episodes' (PSCustomObject)" -ForegroundColor Green
            $keys = @()
            foreach ($prop in $seriesInfo.episodes.PSObject.Properties) {
                # Filtrar apenas propriedades numéricas
                if ($prop.Name -match '^\d+$') {
                    $keys += [int]$prop.Name
                }
            }
            $temporadas = $keys | Sort-Object
        }
        else {
            Write-Host "Nenhuma estrutura de temporadas encontrada" -ForegroundColor Yellow
        }

        Write-Host "Temporadas encontradas: $($temporadas -join ', ')" -ForegroundColor Cyan
    } catch {
        Write-Host "Erro extraindo temporadas: $($_.Exception.Message)" -ForegroundColor Red
    }

    return $temporadas
}

function Format-Duration {
    param([string]$seconds)
    if ([string]::IsNullOrEmpty($seconds) -or $seconds -eq "0") { return "N/A" }
    try {
        $d = [double]$seconds
        $ts = [TimeSpan]::FromSeconds($d)
        if ($ts.Hours -gt 0) { return "$($ts.Hours)h $($ts.Minutes)m" } else { return "$($ts.Minutes)m" }
    } catch {
        return "N/A"
    }
}

# -------------------------
# Função para reproduzir conteúdo - COM ESCOLHA DE PLAYER
# -------------------------
function Start-Player {
    param([string]$streamUrl)
    
    try {
        switch ($script:PlayerSelecionado) {
            "VLC" {
                if (Test-Path $script:VlcPath) {
                    Write-Host "Abrindo no VLC: $streamUrl" -ForegroundColor Green
                    Start-Process -FilePath $script:VlcPath -ArgumentList $streamUrl -ErrorAction SilentlyContinue
                } else {
                    Write-Host "VLC não encontrado no caminho padrão. Usando Windows Media Player." -ForegroundColor Yellow
                    Start-Process -FilePath "wmplayer.exe" -ArgumentList $streamUrl
                }
            }
            "Windows Media Player" {
                Write-Host "Abrindo no Windows Media Player: $streamUrl" -ForegroundColor Green
                Start-Process -FilePath "wmplayer.exe" -ArgumentList $streamUrl
            }
            default {
                Write-Host "Player desconhecido. Usando Windows Media Player." -ForegroundColor Yellow
                Start-Process -FilePath "wmplayer.exe" -ArgumentList $streamUrl
            }
        }
    } catch {
        Write-Host "Erro ao abrir player: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Tentando abrir com player padrão do Windows..." -ForegroundColor Yellow
        try {
            Start-Process -FilePath $streamUrl
        } catch {
            Write-Host "Falha ao abrir o conteúdo." -ForegroundColor Red
        }
    }
}

# -------------------------
# UI: Browser de Series (compatível PS5) - COMPLETAMENTE CORRIGIDO
# -------------------------
function Show-SeriesBrowser {
    param([object]$serie)

    $seriesForm = New-Object System.Windows.Forms.Form
    $seriesForm.Text = "Serie: $($serie.name)"
    $seriesForm.Size = New-Object System.Drawing.Size(900, 600)
    $seriesForm.StartPosition = "CenterScreen"
    $seriesForm.MaximizeBox = $false
    $seriesForm.BackColor = [System.Drawing.Color]::White

    $lblTemporada = New-Object System.Windows.Forms.Label
    $lblTemporada.Text = "Temporada:"
    $lblTemporada.Location = New-Object System.Drawing.Point(10, 15)
    $lblTemporada.Size = New-Object System.Drawing.Size(70, 20)
    $lblTemporada.BackColor = [System.Drawing.Color]::White

    $cmbTemporadas = New-Object System.Windows.Forms.ComboBox
    $cmbTemporadas.Location = New-Object System.Drawing.Point(85, 12)
    $cmbTemporadas.Size = New-Object System.Drawing.Size(150, 22)
    $cmbTemporadas.DropDownStyle = "DropDownList"
    $cmbTemporadas.BackColor = [System.Drawing.Color]::White
    $cmbTemporadas.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

    $lblInfoSerie = New-Object System.Windows.Forms.Label
    $lblInfoSerie.Text = "Serie: $($serie.name)"
    $lblInfoSerie.Location = New-Object System.Drawing.Point(250, 15)
    $lblInfoSerie.Size = New-Object System.Drawing.Size(600, 20)
    $lblInfoSerie.ForeColor = [System.Drawing.Color]::Blue
    $lblInfoSerie.BackColor = [System.Drawing.Color]::White

    $lstEpisodios = New-Object System.Windows.Forms.ListView
    $lstEpisodios.Location = New-Object System.Drawing.Point(10, 50)
    $lstEpisodios.Size = New-Object System.Drawing.Size(860, 450)
    $lstEpisodios.View = "Details"
    $lstEpisodios.FullRowSelect = $true
    $lstEpisodios.GridLines = $true
    $lstEpisodios.BackColor = [System.Drawing.Color]::White
    $lstEpisodios.ForeColor = [System.Drawing.Color]::Black
    $lstEpisodios.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lstEpisodios.Columns.Add("Episodio", 100) | Out-Null
    $lstEpisodios.Columns.Add("Titulo", 400) | Out-Null
    $lstEpisodios.Columns.Add("Duracao", 100) | Out-Null
    $lstEpisodios.Columns.Add("Data", 150) | Out-Null

    $btnFechar = New-Object System.Windows.Forms.Button
    $btnFechar.Text = "Fechar"
    $btnFechar.Location = New-Object System.Drawing.Point(700, 510)
    $btnFechar.Size = New-Object System.Drawing.Size(80, 30)
    $btnFechar.BackColor = [System.Drawing.Color]::LightGray
    $btnFechar.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $btnFechar.Add_Click({ $seriesForm.Close() })

    $btnPlay = New-Object System.Windows.Forms.Button
    $btnPlay.Text = "Reproduzir"
    $btnPlay.Location = New-Object System.Drawing.Point(790, 510)
    $btnPlay.Size = New-Object System.Drawing.Size(80, 30)
    $btnPlay.BackColor = [System.Drawing.Color]::LightGreen
    $btnPlay.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $btnPlay.Add_Click({
        if ($lstEpisodios.SelectedItems.Count -gt 0) {
            $episodio = $lstEpisodios.SelectedItems[0].Tag
            Play-Episodio -episodio $episodio -serie $serie
        }
    })

    $seriesForm.Controls.AddRange(@($lblTemporada, $cmbTemporadas, $lblInfoSerie, $lstEpisodios, $btnFechar, $btnPlay))

    function Load-SeriesData {
        Write-Host "Carregando informacoes da serie: $($serie.name)" -ForegroundColor Yellow
        $seriesInfo = Get-SeriesInfo -seriesId $serie.series_id
        if (-not $seriesInfo) {
            [System.Windows.Forms.MessageBox]::Show("Erro ao carregar informacoes da serie.", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        Write-Host "Estrutura da serie recebida:" -ForegroundColor Cyan
        Write-Host "Tem seasons: $($seriesInfo.seasons -ne $null)" -ForegroundColor Gray
        Write-Host "Tem episodes: $($seriesInfo.episodes -ne $null)" -ForegroundColor Gray
        if ($seriesInfo.episodes) {
            Write-Host "Tipo de episodes: $($seriesInfo.episodes.GetType().Name)" -ForegroundColor Gray
            if ($seriesInfo.episodes -is [PSCustomObject]) {
                Write-Host "Propriedades disponiveis em episodes: $($seriesInfo.episodes.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
                # Debug: verificar o conteúdo da primeira temporada
                if ($seriesInfo.episodes.PSObject.Properties.Name -contains "1") {
                    $temp1Episodes = $seriesInfo.episodes."1"
                    Write-Host "Episodios da temporada 1: $($temp1Episodes.Count)" -ForegroundColor Green
                    if ($temp1Episodes.Count -gt 0) {
                        Write-Host "Primeiro episodio da temp 1: $($temp1Episodes[0].title)" -ForegroundColor Green
                    }
                }
            }
        }

        $script:Temporadas = Get-Seasons -seriesInfo $seriesInfo
        $cmbTemporadas.Items.Clear()
        # guardamos seriesInfo no Tag do combo
        $cmbTemporadas.Tag = $seriesInfo

        if ($script:Temporadas -and $script:Temporadas.Count -gt 0) {
            foreach ($temp in $script:Temporadas) {
                $cmbTemporadas.Items.Add("Temporada " + $temp) | Out-Null
            }
            $cmbTemporadas.SelectedIndex = 0
        } else {
            $cmbTemporadas.Items.Add("Nenhuma temporada") | Out-Null
            $cmbTemporadas.SelectedIndex = 0
            $lstEpisodios.Items.Clear()
            $item = New-Object System.Windows.Forms.ListViewItem("N/A")
            $item.SubItems.Add("Nenhum episodio encontrado") | Out-Null
            $item.SubItems.Add("N/A") | Out-Null
            $item.SubItems.Add("N/A") | Out-Null
            $lstEpisodios.Items.Add($item) | Out-Null
        }
    }

    function Load-Episodios {
        param([object]$seriesInfo, [string]$temporada)
        $lstEpisodios.Items.Clear()
        if ($temporada -eq "Nenhuma temporada") { return }

        Write-Host "Carregando episodios para $temporada..." -ForegroundColor Yellow

        try {
            $seasonKey = $temporada -replace "Temporada ", ""
            Write-Host "Buscando episodios para temporada: $seasonKey" -ForegroundColor Gray

            # ESTRUTURA CORRIGIDA: episodes como PSCustomObject
            if ($seriesInfo.episodes -and ($seriesInfo.episodes -is [PSCustomObject])) {
                Write-Host "Usando estrutura episodes (PSCustomObject)" -ForegroundColor Green
                
                # Verificar se a propriedade existe
                if ($seriesInfo.episodes.PSObject.Properties.Name -contains $seasonKey) {
                    $foundEpisodes = $seriesInfo.episodes.$seasonKey
                    
                    if ($foundEpisodes -and $foundEpisodes.Count -gt 0) {
                        Write-Host "Encontrados $($foundEpisodes.Count) episodios" -ForegroundColor Green
                        
                        # Debug: verificar o primeiro episódio
                        $firstEpisode = $foundEpisodes[0]
                        Write-Host "Primeiro episodio - Tipo: $($firstEpisode.GetType().Name)" -ForegroundColor Gray
                        Write-Host "Propriedades: $($firstEpisode.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
                        
                        if ($firstEpisode.PSObject.Properties.Name -contains "title") {
                            Write-Host "Primeiro titulo: $($firstEpisode.title)" -ForegroundColor Green
                        }
                        
                        # Processar episódios
                        Process-Episodios -episodios $foundEpisodes
                    } else {
                        Write-Host "Nenhum episodio encontrado para a temporada $seasonKey" -ForegroundColor Yellow
                        $item = New-Object System.Windows.Forms.ListViewItem("N/A")
                        $item.SubItems.Add("Nenhum episodio encontrado para esta temporada") | Out-Null
                        $item.SubItems.Add("N/A") | Out-Null
                        $item.SubItems.Add("N/A") | Out-Null
                        $lstEpisodios.Items.Add($item) | Out-Null
                    }
                } else {
                    Write-Host "Temporada $seasonKey nao encontrada em episodes" -ForegroundColor Yellow
                    Write-Host "Propriedades disponiveis: $($seriesInfo.episodes.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
                    $item = New-Object System.Windows.Forms.ListViewItem("N/A")
                    $item.SubItems.Add("Temporada nao encontrada") | Out-Null
                    $lstEpisodios.Items.Add($item) | Out-Null
                }
            }
            else {
                Write-Host "Estrutura de episodios nao reconhecida" -ForegroundColor Yellow
                $item = New-Object System.Windows.Forms.ListViewItem("N/A")
                $item.SubItems.Add("Estrutura de episodios nao suportada") | Out-Null
                $lstEpisodios.Items.Add($item) | Out-Null
            }
        } catch {
            Write-Host "Erro ao carregar episodios: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
            $item = New-Object System.Windows.Forms.ListViewItem("N/A")
            $item.SubItems.Add("Erro ao carregar episodios: $($_.Exception.Message)") | Out-Null
            $lstEpisodios.Items.Add($item) | Out-Null
        }
    }

    function Process-Episodios {
        param([array]$episodios)
        
        Write-Host "Processando $($episodios.Count) episodios..." -ForegroundColor Green
        
        # Ordenar episódios pelo número
        $episodiosOrdenados = $episodios | Sort-Object { 
            if ($_.episode_num) { [int]$_.episode_num } 
            elseif ($_.episode) { [int]$_.episode }
            else { 0 }
        }
        
        foreach ($ep in $episodiosOrdenados) {
            # Debug do objeto episódio
            Write-Host "Processando episodio - Tipo: $($ep.GetType().Name)" -ForegroundColor Gray
            
            # numero do episodio
            $epNum = "?"
            if ($ep.PSObject.Properties.Name -contains "episode_num") { 
                $epNum = $ep.episode_num 
                Write-Host "Episodio num: $epNum" -ForegroundColor Gray
            }
            elseif ($ep.PSObject.Properties.Name -contains "episode") { 
                $epNum = $ep.episode 
                Write-Host "Episodio: $epNum" -ForegroundColor Gray
            }

            $titleVal = "N/A"
            if ($ep.PSObject.Properties.Name -contains "title" -and $ep.title) { 
                $titleVal = $ep.title -replace "`r`n"," " 
                # Decodificar caracteres Unicode
                $titleVal = [System.Text.RegularExpressions.Regex]::Unescape($titleVal)
                Write-Host "Titulo: $titleVal" -ForegroundColor Gray
            }

            $durationVal = "N/A"
            if ($ep.PSObject.Properties.Name -contains "duration" -and $ep.duration) { 
                $durationVal = Format-Duration $ep.duration 
            }
            elseif ($ep.info -and $ep.info.duration_secs) { 
                $durationVal = Format-Duration $ep.info.duration_secs 
            }
            elseif ($ep.info -and $ep.info.duration) {
                $durationVal = $ep.info.duration
            }

            $dateVal = "N/A"
            if ($ep.PSObject.Properties.Name -contains "date_added" -and $ep.date_added) { 
                $dateVal = $ep.date_added 
            }
            elseif ($ep.info -and $ep.info.releasedate) { 
                $dateVal = $ep.info.releasedate 
            }
            elseif ($ep.info -and $ep.info.release_date) {
                $dateVal = $ep.info.release_date
            }

            Write-Host "Adicionando episodio: E$epNum - $titleVal" -ForegroundColor Green
            
            $item = New-Object System.Windows.Forms.ListViewItem("E$($epNum)")
            $item.SubItems.Add($titleVal) | Out-Null
            $item.SubItems.Add($durationVal) | Out-Null
            $item.SubItems.Add($dateVal) | Out-Null
            $item.Tag = $ep
            $lstEpisodios.Items.Add($item) | Out-Null
        }
        Write-Host "Episodios carregados com sucesso" -ForegroundColor Green
    }

    function Play-Episodio {
        param([object]$episodio, [object]$serie)
        if (-not $episodio) { return }
        if (-not $episodio.PSObject.Properties.Name -contains "id") {
            [System.Windows.Forms.MessageBox]::Show("ID do episodio nao encontrado. Impossível reproduzir.", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        $streamUrl = $script:BaseURL + "/series/" + $script:Username + "/" + $script:Password + "/" + $episodio.id + ".mp4"

        $seasonNum = "?"
        if ($episodio.PSObject.Properties.Name -contains "season") { $seasonNum = $episodio.season }
        
        $episodeNum = "?"
        if ($episodio.PSObject.Properties.Name -contains "episode_num") { $episodeNum = $episodio.episode_num }
        elseif ($episodio.PSObject.Properties.Name -contains "episode") { $episodeNum = $episodio.episode }

        $title = ""
        if ($episodio.PSObject.Properties.Name -contains "title") { $title = $episodio.title }

        $playerText = $script:PlayerSelecionado
        $msg = "Reproduzir: " + $serie.name + "`n" + "Temporada " + $seasonNum + " - Episodio " + $episodeNum + "`nTitulo: " + $title + "`nPlayer: " + $playerText + "`n`nDeseja abrir o player?"
        $res = [System.Windows.Forms.MessageBox]::Show($msg, "Reproduzir Episodio", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-Player -streamUrl $streamUrl
        }
    }

    # Eventos
    $cmbTemporadas.Add_SelectedIndexChanged({
        try {
            if ($cmbTemporadas.SelectedIndex -ge 0) {
                $seriesInfo = $cmbTemporadas.Tag
                $selectedSeasonText = $cmbTemporadas.SelectedItem
                Write-Host "Mudando para temporada: $selectedSeasonText" -ForegroundColor Cyan
                Load-Episodios -seriesInfo $seriesInfo -temporada $selectedSeasonText
            }
        } catch {
            Write-Host "Erro ao mudar temporada: $($_.Exception.Message)" -ForegroundColor Red
        }
    })

    $lstEpisodios.Add_DoubleClick({
        if ($lstEpisodios.SelectedItems.Count -gt 0) {
            $episodio = $lstEpisodios.SelectedItems[0].Tag
            Play-Episodio -episodio $episodio -serie $serie
        }
    })

    # Carrega dados
    Load-SeriesData
    $seriesForm.ShowDialog() | Out-Null
}


# -------------------------
# UI: Interface Principal (menu lateral) - compatível PS5 - CORRIGIDA
# -------------------------
function Show-MainForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Xtream Codes Player - PS5 Compativel"
    $form.Size = New-Object System.Drawing.Size(1100, 720)
    $form.StartPosition = "CenterScreen"
    $form.Font = New-Object System.Drawing.Font("Arial", 10)
    $form.BackColor = [System.Drawing.Color]::White

    # side panel
    $sidePanel = New-Object System.Windows.Forms.Panel
    $sidePanel.Location = New-Object System.Drawing.Point(10, 10)
    $sidePanel.Size = New-Object System.Drawing.Size(220, 660)
    $sidePanel.BorderStyle = "FixedSingle"
    $sidePanel.BackColor = [System.Drawing.Color]::White

    # main panel
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Location = New-Object System.Drawing.Point(240, 10)
    $mainPanel.Size = New-Object System.Drawing.Size(840, 660)
    $mainPanel.BorderStyle = "FixedSingle"
    $mainPanel.BackColor = [System.Drawing.Color]::White

    # login controls
    $lblServer = New-Object System.Windows.Forms.Label
    $lblServer.Text = "Servidor"
    $lblServer.Location = New-Object System.Drawing.Point(10, 10)
    $lblServer.Size = New-Object System.Drawing.Size(200, 20)
    $lblServer.BackColor = [System.Drawing.Color]::White
    
    $txtServer = New-Object System.Windows.Forms.TextBox
    $txtServer.Location = New-Object System.Drawing.Point(10, 35)
    $txtServer.Size = New-Object System.Drawing.Size(200, 22)
    $txtServer.Text = $script:ServerURL
    $txtServer.BackColor = [System.Drawing.Color]::White

    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Text = "Usuario"
    $lblUser.Location = New-Object System.Drawing.Point(10, 65)
    $lblUser.Size = New-Object System.Drawing.Size(200, 20)
    $lblUser.BackColor = [System.Drawing.Color]::White
    
    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Location = New-Object System.Drawing.Point(10, 90)
    $txtUser.Size = New-Object System.Drawing.Size(200, 22)
    $txtUser.Text = $script:Username
    $txtUser.BackColor = [System.Drawing.Color]::White

    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Text = "Senha"
    $lblPass.Location = New-Object System.Drawing.Point(10, 120)
    $lblPass.Size = New-Object System.Drawing.Size(200, 20)
    $lblPass.BackColor = [System.Drawing.Color]::White
    
    $txtPass = New-Object System.Windows.Forms.TextBox
    $txtPass.Location = New-Object System.Drawing.Point(10, 145)
    $txtPass.Size = New-Object System.Drawing.Size(200, 22)
    $txtPass.UseSystemPasswordChar = $true
    $txtPass.Text = $script:Password
    $txtPass.BackColor = [System.Drawing.Color]::White

    $btnConnect = New-Object System.Windows.Forms.Button
    $btnConnect.Text = "Conectar"
    $btnConnect.Location = New-Object System.Drawing.Point(10, 180)
    $btnConnect.Size = New-Object System.Drawing.Size(200, 30)
    $btnConnect.BackColor = [System.Drawing.Color]::LightBlue
    $btnConnect.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Status: Nao conectado"
    $lblStatus.Location = New-Object System.Drawing.Point(10, 220)
    $lblStatus.Size = New-Object System.Drawing.Size(200, 20)
    $lblStatus.BackColor = [System.Drawing.Color]::White

    # Configurações do Player - APENAS VLC E WINDOWS MEDIA PLAYER
    $lblPlayer = New-Object System.Windows.Forms.Label
    $lblPlayer.Text = "Player:"
    $lblPlayer.Location = New-Object System.Drawing.Point(10, 250)
    $lblPlayer.Size = New-Object System.Drawing.Size(200, 20)
    $lblPlayer.BackColor = [System.Drawing.Color]::White

    $cmbPlayer = New-Object System.Windows.Forms.ComboBox
    $cmbPlayer.Location = New-Object System.Drawing.Point(10, 275)
    $cmbPlayer.Size = New-Object System.Drawing.Size(200, 22)
    $cmbPlayer.DropDownStyle = "DropDownList"
    $cmbPlayer.Items.AddRange(@("VLC", "Windows Media Player"))
    $cmbPlayer.SelectedItem = $script:PlayerSelecionado
    $cmbPlayer.BackColor = [System.Drawing.Color]::White
    $cmbPlayer.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

    # Botões de conteúdo
    $btnLive = New-Object System.Windows.Forms.Button
    $btnLive.Text = "TV Ao Vivo"
    $btnLive.Location = New-Object System.Drawing.Point(10, 310)
    $btnLive.Size = New-Object System.Drawing.Size(200, 40)
    $btnLive.Enabled = $false
    $btnLive.BackColor = [System.Drawing.Color]::LightGreen
    $btnLive.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

    $btnVOD = New-Object System.Windows.Forms.Button
    $btnVOD.Text = "Filmes (VOD)"
    $btnVOD.Location = New-Object System.Drawing.Point(10, 360)
    $btnVOD.Size = New-Object System.Drawing.Size(200, 40)
    $btnVOD.Enabled = $false
    $btnVOD.BackColor = [System.Drawing.Color]::LightCoral
    $btnVOD.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

    $btnSeries = New-Object System.Windows.Forms.Button
    $btnSeries.Text = "Series"
    $btnSeries.Location = New-Object System.Drawing.Point(10, 410)
    $btnSeries.Size = New-Object System.Drawing.Size(200, 40)
    $btnSeries.Enabled = $false
    $btnSeries.BackColor = [System.Drawing.Color]::LightGoldenrodYellow
    $btnSeries.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

    $sidePanel.Controls.AddRange(@($lblServer, $txtServer, $lblUser, $txtUser, $lblPass, $txtPass, $btnConnect, $lblStatus, $lblPlayer, $cmbPlayer, $btnLive, $btnVOD, $btnSeries))

    # main panel controls
    $lblSearchMain = New-Object System.Windows.Forms.Label
    $lblSearchMain.Text = "Pesquisar"
    $lblSearchMain.Location = New-Object System.Drawing.Point(10, 10)
    $lblSearchMain.Size = New-Object System.Drawing.Size(80, 20)
    $lblSearchMain.BackColor = [System.Drawing.Color]::White
    
    $txtSearchMain = New-Object System.Windows.Forms.TextBox
    $txtSearchMain.Location = New-Object System.Drawing.Point(90, 10)
    $txtSearchMain.Size = New-Object System.Drawing.Size(300, 22)
    $txtSearchMain.Enabled = $false
    $txtSearchMain.BackColor = [System.Drawing.Color]::White

    $btnSearchMain = New-Object System.Windows.Forms.Button
    $btnSearchMain.Text = "Pesquisar"
    $btnSearchMain.Location = New-Object System.Drawing.Point(400, 8)
    $btnSearchMain.Size = New-Object System.Drawing.Size(90, 26)
    $btnSearchMain.BackColor = [System.Drawing.Color]::LightGray
    $btnSearchMain.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

    $lblType = New-Object System.Windows.Forms.Label
    $lblType.Text = "Tipo:"
    $lblType.Location = New-Object System.Drawing.Point(10, 45)
    $lblType.Size = New-Object System.Drawing.Size(50, 20)
    $lblType.BackColor = [System.Drawing.Color]::White
    
    $cmbType = New-Object System.Windows.Forms.ComboBox
    $cmbType.Location = New-Object System.Drawing.Point(60, 43)
    $cmbType.Size = New-Object System.Drawing.Size(160, 22)
    $cmbType.DropDownStyle = "DropDownList"
    $cmbType.Items.AddRange(@("TV Ao Vivo","Filmes","Series"))
    $cmbType.SelectedIndex = 0
    $cmbType.BackColor = [System.Drawing.Color]::White
    $cmbType.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

    $lblCategory = New-Object System.Windows.Forms.Label
    $lblCategory.Text = "Categoria:"
    $lblCategory.Location = New-Object System.Drawing.Point(240, 45)
    $lblCategory.Size = New-Object System.Drawing.Size(70, 20)
    $lblCategory.BackColor = [System.Drawing.Color]::White
    
    $cmbCategory = New-Object System.Windows.Forms.ComboBox
    $cmbCategory.Location = New-Object System.Drawing.Point(315, 43)
    $cmbCategory.Size = New-Object System.Drawing.Size(300, 22)
    $cmbCategory.DropDownStyle = "DropDownList"
    $cmbCategory.Items.Add("Todas as Categorias")
    $cmbCategory.SelectedIndex = 0
    $cmbCategory.Enabled = $false
    $cmbCategory.BackColor = [System.Drawing.Color]::White
    $cmbCategory.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard

    $lstContent = New-Object System.Windows.Forms.ListView
    $lstContent.Location = New-Object System.Drawing.Point(10, 80)
    $lstContent.Size = New-Object System.Drawing.Size(820, 540)
    $lstContent.View = "Details"
    $lstContent.FullRowSelect = $true
    $lstContent.GridLines = $true
    $lstContent.MultiSelect = $false
    $lstContent.BackColor = [System.Drawing.Color]::White
    $lstContent.ForeColor = [System.Drawing.Color]::Black
    $lstContent.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lstContent.Columns.Add("Nome", 380) | Out-Null
    $lstContent.Columns.Add("ID", 80) | Out-Null
    $lstContent.Columns.Add("Categoria", 220) | Out-Null
    $lstContent.Columns.Add("Tipo", 100) | Out-Null

    $mainPanel.Controls.AddRange(@($lblSearchMain, $txtSearchMain, $btnSearchMain, $lblType, $cmbType, $lblCategory, $cmbCategory, $lstContent))

    $form.Controls.AddRange(@($sidePanel, $mainPanel))

    # -------------------------
    # Variáveis locais para controle de estado
    # -------------------------
    $script:UpdatingUI = $false

    # -------------------------
    # Funcoes auxiliares locais - CORRIGIDAS
    # -------------------------
    function Load-AllData {
        Write-Host "Carregando todas as categorias e conteudos..." -ForegroundColor Yellow
        
        # Carregar categorias apenas uma vez
        $script:CategoriasTV = Get-Categories -type "live"
        $script:CategoriasFilmes = Get-Categories -type "vod" 
        $script:CategoriasSeries = Get-Categories -type "series"

        Write-Host ("Categorias carregadas: TV={0} | Filmes={1} | Series={2}" -f $script:CategoriasTV.Count, $script:CategoriasFilmes.Count, $script:CategoriasSeries.Count) -ForegroundColor Green

        # Carregar conteudos completos apenas uma vez
        Write-Host "Carregando canais..." -ForegroundColor Yellow
        $script:Canais = Get-LiveStreams
        
        Write-Host "Carregando filmes..." -ForegroundColor Yellow
        $script:Filmes = Get-VODStreams
        
        Write-Host "Carregando series..." -ForegroundColor Yellow
        $script:Series = Get-Series

        Write-Host ("Conteudos carregados: Canais={0} | Filmes={1} | Series={2}" -f $script:Canais.Count, $script:Filmes.Count, $script:Series.Count) -ForegroundColor Green

        $script:DadosCarregados = $true
        Update-Categories
        Update-ContentList
    }

    function Update-Categories {
        if ($script:UpdatingUI) { return }
        $script:UpdatingUI = $true
        
        try {
            $cmbCategory.Items.Clear()
            $cmbCategory.Items.Add("Todas as Categorias") | Out-Null

            $sel = $cmbType.SelectedItem
            if ($sel -eq "TV Ao Vivo" -and $script:CategoriasTV) {
                foreach ($cat in $script:CategoriasTV) { $cmbCategory.Items.Add($cat.category_name) | Out-Null }
            } elseif ($sel -eq "Filmes" -and $script:CategoriasFilmes) {
                foreach ($cat in $script:CategoriasFilmes) { $cmbCategory.Items.Add($cat.category_name) | Out-Null }
            } elseif ($sel -eq "Series" -and $script:CategoriasSeries) {
                foreach ($cat in $script:CategoriasSeries) { $cmbCategory.Items.Add($cat.category_name) | Out-Null }
            }
            $cmbCategory.SelectedIndex = 0
        } finally {
            $script:UpdatingUI = $false
        }
    }

    function Update-ContentList {
        if ($script:UpdatingUI) { return }
        $script:UpdatingUI = $true
        
        try {
            $lstContent.BeginUpdate()
            $lstContent.Items.Clear()
            Write-Host "Atualizando lista de conteudo..." -ForegroundColor Yellow

            $selectedCategory = $cmbCategory.SelectedItem
            $contentType = $cmbType.SelectedItem

            if ($contentType -eq "TV Ao Vivo" -and $script:Canais) {
                Write-Host "Exibindo canais do cache..." -ForegroundColor Green
                $canaisFiltrados = @()
                
                if ($selectedCategory -eq "Todas as Categorias") {
                    $canaisFiltrados = $script:Canais
                } else {
                    # Filtrar por categoria
                    $categoriaId = ($script:CategoriasTV | Where-Object { $_.category_name -eq $selectedCategory }).category_id
                    if ($categoriaId) {
                        $canaisFiltrados = $script:Canais | Where-Object { $_.category_id -eq $categoriaId }
                    } else {
                        $canaisFiltrados = $script:Canais
                    }
                }
                
                # Limitar a exibição para melhor performance
                $canaisParaExibir = if ($canaisFiltrados.Count -gt 1000) { 
                    $canaisFiltrados | Select-Object -First 1000 
                } else { 
                    $canaisFiltrados 
                }
                
                foreach ($canal in $canaisParaExibir) {
                    $categoria = ($script:CategoriasTV | Where-Object { $_.category_id -eq $canal.category_id }).category_name
                    $item = New-Object System.Windows.Forms.ListViewItem($canal.name)
                    $item.SubItems.Add($canal.stream_id) | Out-Null
                    $item.SubItems.Add($categoria) | Out-Null
                    $item.SubItems.Add("TV") | Out-Null
                    $item.Tag = $canal
                    $lstContent.Items.Add($item) | Out-Null
                }
                
                if ($canaisFiltrados.Count -gt 1000) {
                    $item = New-Object System.Windows.Forms.ListViewItem("...")
                    $item.SubItems.Add("") | Out-Null
                    $item.SubItems.Add("Mostrando 1000 de " + $canaisFiltrados.Count + " canais") | Out-Null
                    $item.SubItems.Add("") | Out-Null
                    $lstContent.Items.Add($item) | Out-Null
                }
                
                Write-Host ("Canais exibidos: {0}" -f $canaisParaExibir.Count) -ForegroundColor Green
            } elseif ($contentType -eq "Filmes" -and $script:Filmes) {
                Write-Host "Exibindo filmes do cache..." -ForegroundColor Green
                $filmesFiltrados = @()
                
                if ($selectedCategory -eq "Todas as Categorias") {
                    $filmesFiltrados = $script:Filmes
                } else {
                    # Filtrar por categoria
                    $categoriaId = ($script:CategoriasFilmes | Where-Object { $_.category_name -eq $selectedCategory }).category_id
                    if ($categoriaId) {
                        $filmesFiltrados = $script:Filmes | Where-Object { $_.category_id -eq $categoriaId }
                    } else {
                        $filmesFiltrados = $script:Filmes
                    }
                }
                
                # Limitar a exibição para melhor performance
                $filmesParaExibir = if ($filmesFiltrados.Count -gt 1000) { 
                    $filmesFiltrados | Select-Object -First 1000 
                } else { 
                    $filmesFiltrados 
                }
                
                foreach ($filme in $filmesParaExibir) {
                    $categoria = ($script:CategoriasFilmes | Where-Object { $_.category_id -eq $filme.category_id }).category_name
                    $item = New-Object System.Windows.Forms.ListViewItem($filme.name)
                    $item.SubItems.Add($filme.stream_id) | Out-Null
                    $item.SubItems.Add($categoria) | Out-Null
                    $item.SubItems.Add("Filme") | Out-Null
                    $item.Tag = $filme
                    $lstContent.Items.Add($item) | Out-Null
                }
                
                if ($filmesFiltrados.Count -gt 1000) {
                    $item = New-Object System.Windows.Forms.ListViewItem("...")
                    $item.SubItems.Add("") | Out-Null
                    $item.SubItems.Add("Mostrando 1000 de " + $filmesFiltrados.Count + " filmes") | Out-Null
                    $item.SubItems.Add("") | Out-Null
                    $lstContent.Items.Add($item) | Out-Null
                }
                
                Write-Host ("Filmes exibidos: {0}" -f $filmesParaExibir.Count) -ForegroundColor Green
            } elseif ($contentType -eq "Series" -and $script:Series) {
                Write-Host "Exibindo series do cache..." -ForegroundColor Green
                $seriesFiltradas = @()
                
                if ($selectedCategory -eq "Todas as Categorias") {
                    $seriesFiltradas = $script:Series
                } else {
                    # Filtrar por categoria
                    $categoriaId = ($script:CategoriasSeries | Where-Object { $_.category_name -eq $selectedCategory }).category_id
                    if ($categoriaId) {
                        $seriesFiltradas = $script:Series | Where-Object { $_.category_id -eq $categoriaId }
                    } else {
                        $seriesFiltradas = $script:Series
                    }
                }
                
                # Limitar a exibição para melhor performance
                $seriesParaExibir = if ($seriesFiltradas.Count -gt 1000) { 
                    $seriesFiltradas | Select-Object -First 1000 
                } else { 
                    $seriesFiltradas 
                }
                
                foreach ($serie in $seriesParaExibir) {
                    $categoria = ($script:CategoriasSeries | Where-Object { $_.category_id -eq $serie.category_id }).category_name
                    $item = New-Object System.Windows.Forms.ListViewItem($serie.name)
                    $item.SubItems.Add($serie.series_id) | Out-Null
                    $item.SubItems.Add($categoria) | Out-Null
                    $item.SubItems.Add("Serie") | Out-Null
                    $item.Tag = $serie
                    $lstContent.Items.Add($item) | Out-Null
                }
                
                if ($seriesFiltradas.Count -gt 1000) {
                    $item = New-Object System.Windows.Forms.ListViewItem("...")
                    $item.SubItems.Add("") | Out-Null
                    $item.SubItems.Add("Mostrando 1000 de " + $seriesFiltradas.Count + " series") | Out-Null
                    $item.SubItems.Add("") | Out-Null
                    $lstContent.Items.Add($item) | Out-Null
                }
                
                Write-Host ("Series exibidas: {0}" -f $seriesParaExibir.Count) -ForegroundColor Green
            }

            $lstContent.AutoResizeColumns([System.Windows.Forms.ColumnHeaderAutoResizeStyle]::ColumnContent)
        } finally {
            $lstContent.EndUpdate()
            $script:UpdatingUI = $false
        }
    }

    function Search-Content {
        param([string]$searchTerm)
        $lstContent.Items.Clear()
        Write-Host "Pesquisando por: $searchTerm" -ForegroundColor Cyan
        if ([string]::IsNullOrWhiteSpace($searchTerm)) {
            $item = New-Object System.Windows.Forms.ListViewItem("Termo de pesquisa vazio")
            $lstContent.Items.Add($item) | Out-Null
            return
        }

        $results = @()

        # Pesquisar nos dados em cache
        # Live
        if ($script:Canais) {
            foreach ($it in $script:Canais) {
                if ($it.name -match $searchTerm) {
                    $catName = ($script:CategoriasTV | Where-Object { $_.category_id -eq $it.category_id }).category_name
                    $results += [PSCustomObject]@{ Type="TV"; Name=$it.name; ID=$it.stream_id; Category=$catName; Object=$it }
                }
            }
        }

        # VOD
        if ($script:Filmes) {
            foreach ($it in $script:Filmes) {
                if ($it.name -match $searchTerm) {
                    $catName = ($script:CategoriasFilmes | Where-Object { $_.category_id -eq $it.category_id }).category_name
                    $results += [PSCustomObject]@{ Type="Filme"; Name=$it.name; ID=$it.stream_id; Category=$catName; Object=$it }
                }
            }
        }

        # Series
        if ($script:Series) {
            foreach ($it in $script:Series) {
                if ($it.name -match $searchTerm) {
                    $catName = ($script:CategoriasSeries | Where-Object { $_.category_id -eq $it.category_id }).category_name
                    $results += [PSCustomObject]@{ Type="Serie"; Name=$it.name; ID=$it.series_id; Category=$catName; Object=$it }
                }
            }
        }

        if ($results.Count -eq 0) {
            $item = New-Object System.Windows.Forms.ListViewItem("Nenhum resultado")
            $item.SubItems.Add("") | Out-Null
            $item.SubItems.Add("") | Out-Null
            $item.SubItems.Add("") | Out-Null
            $lstContent.Items.Add($item) | Out-Null
        } else {
            foreach ($r in $results) {
                $item = New-Object System.Windows.Forms.ListViewItem($r.Name)
                $item.SubItems.Add($r.ID) | Out-Null
                $item.SubItems.Add($r.Category) | Out-Null
                $item.SubItems.Add($r.Type) | Out-Null
                $item.Tag = $r.Object
                $lstContent.Items.Add($item) | Out-Null
            }
        }

        $lstContent.AutoResizeColumns([System.Windows.Forms.ColumnHeaderAutoResizeStyle]::ColumnContent)
    }

    function Play-Content {
        param($item)
        $content = $item.Tag
        if (-not $content) { return }
        $type = $item.SubItems[3].Text
        if ($type -eq "TV") {
            $streamUrl = $script:BaseURL + "/live/" + $script:Username + "/" + $script:Password + "/" + $content.stream_id + ".ts"
            $playerText = $script:PlayerSelecionado
            $res = [System.Windows.Forms.MessageBox]::Show("Abrir canal: " + $content.name + "`nPlayer: " + $playerText + "`n`nDeseja reproduzir?", "TV Ao Vivo", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-Player -streamUrl $streamUrl
            }
        } elseif ($type -eq "Filme") {
            $streamUrl = $script:BaseURL + "/movie/" + $script:Username + "/" + $script:Password + "/" + $content.stream_id + ".mp4"
            $playerText = $script:PlayerSelecionado
            $res = [System.Windows.Forms.MessageBox]::Show("Abrir filme: " + $content.name + "`nPlayer: " + $playerText + "`n`nDeseja reproduzir?", "Filme", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-Player -streamUrl $streamUrl
            }
        } else {
            # Serie
            Show-SeriesBrowser -serie $content
            return
        }
    }

    # -------------------------
    # Eventos UI - CORRIGIDOS
    # -------------------------
    $cmbType.Add_SelectedIndexChanged({
        if (-not $script:UpdatingUI) {
            Update-Categories
            Update-ContentList
        }
    })

    $cmbCategory.Add_SelectedIndexChanged({
        if (-not $script:UpdatingUI) {
            Update-ContentList
        }
    })

    $btnSearchMain.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($txtSearchMain.Text)) {
            Search-Content -searchTerm $txtSearchMain.Text
        }
    })

    $lstContent.Add_DoubleClick({
        if ($lstContent.SelectedItems.Count -gt 0) {
            $sel = $lstContent.SelectedItems[0]
            Play-Content $sel
        }
    })

    $btnLive.Add_Click({ 
        if (-not $script:UpdatingUI) {
            $cmbType.SelectedItem = "TV Ao Vivo"
            Update-Categories
            Update-ContentList 
        }
    })
    
    $btnVOD.Add_Click({ 
        if (-not $script:UpdatingUI) {
            $cmbType.SelectedItem = "Filmes"
            Update-Categories
            Update-ContentList 
        }
    })
    
    $btnSeries.Add_Click({ 
        if (-not $script:UpdatingUI) {
            $cmbType.SelectedItem = "Series"
            Update-Categories
            Update-ContentList 
        }
    })

    # Evento para mudar o player
    $cmbPlayer.Add_SelectedIndexChanged({
        $script:PlayerSelecionado = $cmbPlayer.SelectedItem
        Write-Host "Player alterado para: $script:PlayerSelecionado" -ForegroundColor Cyan
    })

    # Conectar botão
    $btnConnect.Add_Click({
        $script:ServerURL = $txtServer.Text.TrimEnd("/")
        $script:Username = $txtUser.Text
        $script:Password = $txtPass.Text
        $script:BaseURL = $script:ServerURL

        if ([string]::IsNullOrEmpty($script:ServerURL) -or [string]::IsNullOrEmpty($script:Username) -or [string]::IsNullOrEmpty($script:Password)) {
            [System.Windows.Forms.MessageBox]::Show("Preencha todos os campos de login!", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        Write-Host "Conectando ao servidor..." -ForegroundColor Yellow
        $auth = Get-XtreamAuth -url $script:ServerURL -username $script:Username -password $script:Password
        if ($auth -and $auth.user_info -and $auth.user_info.status -eq "Active") {
            Load-AllData
            $lblStatus.Text = "Status: Conectado"
            $btnLive.Enabled = $true
            $btnVOD.Enabled = $true
            $btnSeries.Enabled = $true
            $cmbCategory.Enabled = $true
            $txtSearchMain.Enabled = $true
            [System.Windows.Forms.MessageBox]::Show("Conectado com sucesso!", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            [System.Windows.Forms.MessageBox]::Show("Falha na autenticacao. Verifique suas credenciais.", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            $lblStatus.Text = "Status: Não conectado"
        }
    })

    $form.ShowDialog() | Out-Null
}

# -------------------------
# Start
# -------------------------
Write-Host "Xtream Codes Player (PS5 compativel) iniciado..." -ForegroundColor Cyan
Show-MainForm