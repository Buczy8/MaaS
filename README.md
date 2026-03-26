# Monitoring w chmurze: Terraform + Ansible + Docker + Zabbix

## 1. Zakres i cel

Projekt automatyzuje pelny cykl IaC:

- provisioning infrastruktury Azure przez Terraform,
- bootstrap i konfiguracje hostow przez Ansible,
- uruchomienie Zabbix Server/Web/DB przez Docker Compose,
- instalacje i konfiguracje Zabbix Agent 2 na obu VM.

Topologia:

- `group8VM` (grupa `azure_vm`): host glowny, Docker + Zabbix (web na porcie `80`), lokalny Agent 2,
- `group8AgentVM` (grupa `agent_vm`): host monitorowany, Agent 2 + Nginx + MariaDB.

## 2. Architektura i przeplyw

Kolejnosc uruchomienia (`make deploy`):

1. `terraform init` i `terraform apply` tworza zasoby oraz generuja `ansible/inventory.ini`.
2. `ansible/playbook.yaml` uruchamia role `base`, `docker`, `zabbix_server`, `zabbix_agent`, `nginx`, `mariadb` dla odpowiednich grup (`azure_vm`, `agent_vm`) i uzywa sekretu `pg_monitor_password` z Vault.
3. Rola `zabbix_server` kopiuje `docker-compose` oraz `docker/.env` na host glowny i uruchamia stack kontenerow, a `zabbix_agent` konfiguruje natywnego agenta.
4. `make open` probuje otworzyc `http://<public_ip_address>` z outputu Terraform.

Istotne zaleznosci:

- `ansible/playbook.yaml` wymaga lokalnego pliku `docker/.env`.
- `ansible/playbook.yaml` wymaga odszyfrowywalnego `ansible/secrets.yml`.
- inventory jest artefaktem Terraform (`local_file`) i moze zostac nadpisane przy kolejnym `apply`.

## 3. Repozytorium (kluczowe pliki)

- `Makefile` - orchestration (`init`, `plan`, `apply`, `provision`, `deploy`, `destroy`).
- `terraform/main.tf` - RG, VNet, Subnet, NSG, NIC, 2x VM, public IP, inventory output.
- `ansible/playbook.yaml` - glowny playbook uruchamiajacy role dla obu VM.
- `ansible/ansible.cfg` - lokalna konfiguracja Ansible (inventory, roles_path, SSH).
- `ansible/requirements.yml` - kolekcje Ansible wymagane przez role.
- `ansible/group_vars/azure_vm.yml` - zmienne `zabbix_agent` dla hosta glownego.
- `ansible/group_vars/agent_vm.yml` - zmienne `zabbix_agent` dla hosta monitorowanego.
- `ansible/roles/base/tasks/main.yaml` - wspolne taski bazowe (pakiety + klucze SSH).
- `ansible/roles/docker/tasks/main.yaml` - instalacja Dockera i Compose na `azure_vm`.
- `ansible/roles/zabbix_server/tasks/main.yaml` - uruchomienie Zabbix Server/Web/DB przez Docker Compose na `azure_vm`.
- `ansible/roles/zabbix_agent/tasks/main.yaml` - instalacja i konfiguracja Zabbix Agent 2 na hostach.
- `ansible/roles/nginx/tasks/main.yaml` - osobna konfiguracja Nginx na `agent_vm`.
- `ansible/roles/mariadb/tasks/main.yaml` - osobna konfiguracja MariaDB na `agent_vm`.
- `docker/docker-compose.yml` - `mysql:8.0`, `zabbix-server`, `zabbix-web`.
- `docker/.env.example` - template zmiennych dla Compose.
- `ansible/secrets.example.yml` - template sekretow do zaszyfrowania Vaultem.

## 4. Wymagania

Niezbedne narzedzia lokalnie:

- `terraform`
- `ansible`
- `ansible-galaxy` (do instalacji kolekcji)
- `az` (Azure CLI)
- `ssh-keygen`

Wymagane kolekcje Ansible:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

Możesz tez uzyc celu Makefile:

```bash
make ansible-deps
```

Autoryzacja Azure:

```bash
az login
az account show
```

## 5. Sekrety i dane wrazliwe

### 5.1 `docker/.env`

Utworz plik runtime dla Compose:

```bash
cp docker/.env.example docker/.env
```

Minimalna konfiguracja:

```dotenv
MYSQL_ROOT_PASSWORD=STRONG_ROOT_PASSWORD
MYSQL_USER=zabbix
MYSQL_PASSWORD=STRONG_ZABBIX_PASSWORD
MYSQL_DATABASE=zabbix
```

Uwagi:

- `**/.env` jest ignorowane przez `.gitignore`.
- brak pliku przerwie playbook `ansible/playbook.yaml` na tasku kopiowania `.env`.

### 5.2 `ansible/secrets.yml` (Vault)

Przygotowanie i szyfrowanie:

```bash
cp ansible/secrets.example.yml ansible/secrets.yml
ansible-vault encrypt ansible/secrets.yml
```

Edycja zaszyfrowanego pliku:

```bash
ansible-vault edit ansible/secrets.yml
```

`make provision` uruchamia playbook z `--ask-vault-pass`, wiec haslo Vault jest wymagane interaktywnie.

## 6. SSH i klucze

Terraform i Ansible oczekuja klucza:

- prywatny: `terraform/.ssh/id_rsa`
- publiczny: `terraform/.ssh/id_rsa.pub`

Generowanie:

```bash
mkdir -p terraform/.ssh
ssh-keygen -t rsa -b 4096 -f terraform/.ssh/id_rsa -N ""
```

Playbooki referencuja dodatkowo klucze w `terraform/.ssh/others/` (sekcja `authorized_key`). Jesli ich nie posiadasz, utworz:

```bash
mkdir -p terraform/.ssh/others
ssh-keygen -t rsa -b 4096 -f terraform/.ssh/others/id_rsa -N ""
ssh-keygen -t rsa -b 4096 -f terraform/.ssh/others/id_rsa_m -N ""
```

## 7. Procedura wdrozenia

### 7.1 Wariant krokowy

```bash
make ansible-deps
make init
make plan
make apply AUTO=1
make ansible-check
make provision
make status
make open
```

### 7.2 Wariant one-shot

```bash
make deploy
```

## 8. Konfiguracja Zabbixa (UI po wdrozeniu)

Po `make deploy` panel powinien otworzyc sie automatycznie (`make deploy` zawiera `make open`).
Nastepnie wykonaj konfiguracje hosta monitorowanego w panelu Zabbix.

1. Jesli panel nie otworzy sie sam, wejdz recznie na `http://<public_ip_glownej_vm>` i zaloguj sie do Zabbixa.
2. Przejdz do `Data collection -> Hosts -> Create host`.
3. Ustaw podstawowe pola:
   - `Host name`: `group8AgentVM`
   - `Visible name`: `group8AgentVM`
   - `Host groups`: dodaj docelowe grupy (np. `Linux servers`, `Databases`, `Web servers`).
4. W sekcji `Interfaces` dodaj/edytuj interfejs `Agent`:
   - `IP address`: `10.0.1.4`
   - `Port`: `10050`
   - `Connect to`: `IP`
5. W sekcji `Templates` podlinkuj:
   - `Linux by Zabbix agent`
   - `Nginx by Zabbix agent`
   - `MySQL by Zabbix agent 2`
6. W sekcji `Macros` dodaj makra MySQL:
   - `{$MYSQL.DSN}` = `tcp://localhost:3306`
   - `{$MYSQL.USER}` = `zbx_monitor`
   - `{$MYSQL.PASSWORD}` = `<haslo_uzytkownika_mysql>`
7. Zapisz hosta i sprawdz dane w `Monitoring -> Latest data`.

Mapowanie IP i grup z infrastruktury:

- `group8VM` (`azure_vm`) - host glowny Zabbixa.
- interfejs dockerowy serwera Zabbix: `172.17.0.21`.
- `group8AgentVM` (`agent_vm`) - host monitorowany dodawany w UI.
- prywatny adres agenta: `10.0.1.4`.
- Aktualne adresy sprawdzaj w `ansible/inventory.ini` (plik jest generowany przez Terraform).

Walidacja po konfiguracji:

```bash
make status
make ping
cat ansible/inventory.ini
```

## 9. Symulacja ruchu i obciazenia na maszynie `group8AgentVM`

Ponizsze komendy uruchamiaj po SSH na `group8AgentVM` jako uzytkownik z uprawnieniami `sudo`.

### 9.1 Ruch HTTP na Nginx

Szybki test endpointu:

```bash
curl -I http://127.0.0.1/
```

Symulacja ruchu HTTP w tle i bez outputu:

```bash
nohup bash -c 'while true; do curl -s -o /dev/null http://127.0.0.1/; done' >/dev/null 2>&1 & echo $! > /tmp/zbx_http_load.pid
```

Zatrzymanie:

```bash
kill "$(cat /tmp/zbx_http_load.pid)"
rm -f /tmp/zbx_http_load.pid
```

### 9.2 Ruch do bazy MariaDB

Zaklada konto monitorujace `zbx_monitor` skonfigurowane przez Ansible.

Pojedynczy test logowania:

```bash
mysql -u zbx_monitor -p -h 127.0.0.1 -e "SELECT NOW();"
```

Symulacja ruchu SQL w tle i bez outputu:

```bash
nohup bash -c 'export MYSQL_PWD="<haslo_zbx_monitor>"; while true; do mysql -u zbx_monitor -h 127.0.0.1 -e "SHOW STATUS LIKE "'"'Threads_connected'"'";" >/dev/null 2>&1; done' >/dev/null 2>&1 & echo $! > /tmp/zbx_sql_load.pid
```

Zatrzymanie:

```bash
kill "$(cat /tmp/zbx_sql_load.pid)"
rm -f /tmp/zbx_sql_load.pid
```

### 9.3 Obciazenie CPU

Obciazenie CPU w tle i bez outputu (2 procesy `yes`):

```bash
nohup bash -c 'yes >/dev/null 2>&1 & yes >/dev/null 2>&1 & wait' >/dev/null 2>&1 & echo $! > /tmp/zbx_cpu_load.pid
```

Dla mocniejszego obciazenia (4 procesy):

```bash
nohup bash -c 'yes >/dev/null 2>&1 & yes >/dev/null 2>&1 & yes >/dev/null 2>&1 & yes >/dev/null 2>&1 & wait' >/dev/null 2>&1 & echo $! > /tmp/zbx_cpu_load.pid
```

Zatrzymanie:

```bash
kill "$(cat /tmp/zbx_cpu_load.pid)"
pkill -f '^yes$' || true
rm -f /tmp/zbx_cpu_load.pid
```

W trakcie testow monitoruj zuzycie CPU i load:

```bash
top
uptime
```

## 10. Znane punkty awarii

- `Vault secret not found`/`Decryption failed`: brak `ansible/secrets.yml` lub bledne haslo Vault.
- `copy ../docker/.env failed`: brak `docker/.env` lokalnie.
- `UNREACHABLE!`: niespojny klucz SSH, zly user, niedostepny host.
- Zabbix UI na `:80` nie odpowiada: kontenery jeszcze startuja lub blad DB init.
- Rozjazd IP: `ansible/inventory.ini` nadpisywane przez Terraform, nie edytowac recznie trwale.

## 11. Bezpieczenstwo operacyjne

- Sekrety trzymaj tylko w `ansible/secrets.yml` (Vault) i lokalnym `docker/.env`.
- Nie commituj `terraform/.ssh/`, `ansible/secrets.yml`, `.env`.
- Ograniczaj publiczny dostep do NSG (obecnie otwarte `22` i `80` globalnie).
- Po testach usun zasoby, aby uniknac kosztow.

## 12. Deprovisioning

```bash
make destroy CONFIRM=YES AUTO=1
```

Komenda usuwa zasoby Terraform utworzone w Azure.

