# Wartank Multi-Bot

Bot multi-conta para wartank-pt.net com sessões isoladas, painel em tempo real e recuperação automática de falhas.

---

## Funcionalidades

| Função | Descrição |
|--------|-----------|
| **Login** | Automático via `accounts.txt`. Credenciais encriptadas em base64 por conta. |
| **Adiante a Combate** | Executa 9 disparos (3 inimigos) a cada ciclo. |
| **PVP** | Batalha automática nos horários definidos (ver tabela abaixo). |

---

## Isolamento entre contas

Cada conta corre num processo independente com:

- Cookies próprios (`~/.wartank/<conta>/cookies.txt`)
- Credenciais próprias (`~/.wartank/<conta>/cript_file`)
- Log próprio (`~/.wartank/<conta>/bot.log`)
- Ficheiro de status próprio (`~/.wartank/status/<conta>.status`)

**Se uma conta morrer, as outras continuam a funcionar.**

---

## Instalação

```bash
# 1. Clonar / extrair o bot
cd ~/wartank-multi

# 2. Dar permissões
chmod +x *.sh

# 3. Editar accounts.txt
nano accounts.txt
```

### Formato do accounts.txt

```
username1:password1
username2:password2
username3:password3
```

- Uma conta por linha
- Separador: `:`
- Linhas começadas por `#` são ignoradas

---

## Utilização

```bash
# Iniciar todas as contas + painel em tempo real
bash controller.sh

# Parar todos os workers
bash controller.sh stop

# Ver painel uma única vez
bash controller.sh status
```

Para parar tudo enquanto o painel está activo: **Ctrl+C**

---

## Painel em tempo real

O painel actualiza a cada 5 segundos e mostra por conta:

| Coluna | Significado |
|--------|-------------|
| Conta | Username |
| Estado | `online` / `battle` / `pvp` / `login` / `reconect.` / `erro login` / `stopped` / `morto` |
| Nivel | Nível do jogador |
| Fuel | Combustível actual |
| Ultima act. | Hora da última actualização de estado |

---

## Configuração avançada (opcional)

As seguintes variáveis de ambiente podem ser definidas antes de iniciar:

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `BATTLE_LA` | `3` | Segundos de atraso entre disparos no Adiante a Combate |
| `BATTLE_SHOTS` | `9` | Número de disparos por sessão de Adiante a Combate |
| `BATTLE_TIMEOUT` | `600` | Timeout máximo (segundos) por sessão de combate |

Exemplo:
```bash
BATTLE_LA=4 BATTLE_SHOTS=9 bash controller.sh
```

---

## Horários PVP

O PVP ocorre a cada **13 minutos** dentro de três janelas diárias.  
Janela de tolerância: **4 minutos** após cada horário.

**Total: 57 batalhas PVP por dia.**

### Janela 1 — 05:00 às 11:00

| | | | | | | | | | |
|--|--|--|--|--|--|--|--|--|--|
| 05:00 | 05:13 | 05:26 | 05:39 | 05:52 | 06:05 | 06:18 | 06:31 | 06:44 | 06:57 |
| 07:10 | 07:23 | 07:36 | 07:49 | 08:02 | 08:15 | 08:28 | 08:41 | 08:54 | 09:07 |
| 09:20 | 09:33 | 09:46 | 09:59 | 10:12 | 10:25 | 10:38 | 10:51 | 11:00 | — |

**29 batalhas nesta janela.**

### Janela 2 — 13:00 às 17:00

| | | | | | | | | | |
|--|--|--|--|--|--|--|--|--|--|
| 13:00 | 13:13 | 13:26 | 13:39 | 13:52 | 14:05 | 14:18 | 14:31 | 14:44 | 14:57 |
| 15:10 | 15:23 | 15:36 | 15:49 | 16:02 | 16:15 | 16:28 | 16:41 | 16:54 | 17:00 |

**20 batalhas nesta janela.**

### Janela 3 — 19:00 às 21:00

| | | | | | | | | | |
|--|--|--|--|--|--|--|--|--|--|
| 19:00 | 19:13 | 19:26 | 19:39 | 19:52 | 20:05 | 20:18 | 20:31 | 20:44 | 20:57 |
| 21:00 | — | — | — | — | — | — | — | — | — |

**11 batalhas nesta janela.**

---

## Estrutura de ficheiros

```
wartank-multi/
├── controller.sh     ← Ponto de entrada principal
├── worker.sh         ← Motor por conta (chamado pelo controlador)
├── core.sh           ← Funções base (fetch, log, sessão)
├── login.sh          ← Login automático
├── battle.sh         ← Adiante a Combate
├── pvp.sh            ← PVP com horários
├── status.sh         ← Helpers de estado
├── accounts.txt      ← Contas (editar antes de usar)
└── README.md         ← Este ficheiro

~/.wartank/
├── pids/             ← PIDs dos workers activos
├── status/           ← Estado em tempo real por conta
└── <conta>/          ← Dados isolados por conta
    ├── cookies.txt
    ├── cript_file
    ├── bot.log
    └── SRC
```

---

## Notas de segurança

- As passwords são armazenadas em base64 (ofuscação, não encriptação forte).
- Os ficheiros de credenciais têm permissões `600` (só o dono lê).
- Nunca partilhes o ficheiro `accounts.txt` nem a pasta `~/.wartank/`.

---

## Compatibilidade

Testado em:
- **Termux** (Android)
- **Ubuntu / Debian** (Linux)

Dependências: `bash`, `curl`, `grep`, `sed`, `awk`, `base64`, `python3` (opcional, tem fallback em awk)
