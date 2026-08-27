Wartank Multi-Contas (versão leve)
Bot multi-conta para wartank-pt.net, pensado para contas secundárias no Android (Termux).
Versão leve: XP, missões, recursos da base e PvP — sem o ciclo completo do Wartank-Macro (conta principal).
O que faz
Módulo
Função
Adiante a combate
XP — horários fixos a cada 40 min (ex.: 00:00, 00:40, 01:20…)
PvP
05:23, 11:23 e 21:23 — até 3 batalhas por sessão
CW
Guerra de clã, se estiver activa
Missões
Recolha de recompensas (simples)
Base
Pegar produção, mina (minério), polígono (buff grátis de ataque), sala de armas
Escolta
Combate + startMasking (recarregamento no jogo)
Assault
Missão especial — cooldown de 20 h após o fim
Não inclui: PvE, DM, Divisão (company), mercado prata→ouro (desligado por defeito).
Isolamento entre contas
Cada conta corre num processo à parte:
~/.wartank/
├── accounts.conf          ← lista de usernames
├── pids/                  ← PIDs dos workers
├── status/                ← painel em tempo real
└── <conta>/
    ├── cookies.txt
    ├── cript_file         ← credenciais (base64, chmod 600)
    ├── bot.log
    ├── SRC
    └── last_assault_ts    ← cooldown assault
Se uma conta cair, as outras continuam.
Requisitos
Termux (F-Droid) ou Linux
bash, curl, grep, sed, awk, base64
pkg update && pkg upgrade -y
pkg install git curl bash
Instalação
cd ~
git clone https://github.com/ramalhotimoteo1-oss/Wartank-Mult-Contas.git
cd ~/Wartank-Mult-Contas
chmod +x *.sh
Contas
bash controller.sh add      # username + password
bash controller.sh remove   # remove uma conta
As passwords não ficam em texto no accounts.conf — só o username. As credenciais vão para ~/.wartank/<conta>/cript_file.
Utilização
# Iniciar todas as contas + painel
bash controller.sh

# Parar tudo
bash controller.sh stop

# Painel uma vez
bash controller.sh status
Com o painel activo: Ctrl+C para tudo.
Recomendado no telemóvel:
termux-wake-lock
Sugestão: 2 a 4 contas em paralelo no mesmo dispositivo.
Painel
Actualiza a cada 5 segundos:
Coluna
Significado
Conta
Username
Estado
online / battle / pvp / login / reconect. / erro login / stopped / morto
Niv
Nível
Fuel
Combustível
Última
Hora da última actualização
Configuração (igual para todas)
Variáveis de ambiente opcionais (antes de controller.sh):
Variável
Padrão
Descrição
BATTLE_LA
3
Segundos entre disparos (Adiante)
BATTLE_SHOTS
9
Disparos por sessão de battle
BATTLE_WINDOW
3
Janela (min) do slot de battle
FUNC_battle
y
Adiante a combate
FUNC_missions
y
Missões
FUNC_buildings
y
Base
FUNC_pvp
y
PvP
FUNC_cw
y
Guerra de clã
FUNC_convoy
y
Escolta
FUNC_assault
y
Assault
ASSAULT_COOLDOWN_SEC
72000
20 h após assault
Exemplo:
FUNC_assault=n BATTLE_SHOTS=9 bash controller.sh
Horários
Adiante a combate: a cada 40 minutos (minuto total múltiplo de 40), janela de 3 min, combustível ≥ 90.
PvP: 05:23, 11:23, 21:23 (janela de 4 min).
Assault: só de novo ~20 h depois do fim/destruição.
Estrutura do projecto
Wartank-Mult-Contas/
├── controller.sh       ← start / stop / status / add / remove
├── worker.sh           ← ciclo por conta
├── core.sh
├── login.sh
├── status.sh
├── combat_common.sh
├── battle.sh
├── pvp.sh
├── cw.sh
├── convoy.sh
├── assault.sh
├── missions.sh
├── base.sh
└── README.md
Conta principal vs multi
Wartank-Macro

Este repo
Uso
1 conta (completa)
Várias contas (leve)
PvE / DM / Divisão
Sim
Não
PvP
Sim
Sim
Base / missões / escolta
Sim
Sim
Segurança
Credenciais em base64 + chmod 600 (ofuscação, não criptografia forte)
Não partilhes ~/.wartank/ nem o ecrã com passwords
Não commits com accounts.conf ou cript_file
Actualizar
cd ~/Wartank-Mult-Contas
git pull
chmod +x *.sh
Apoio
Doações / contacto: ramirosh015@gmail.com
Projecto sem fins lucrativos — ajuda a manter o servidor PT-BR activo.
