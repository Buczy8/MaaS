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
2. `ansible/install_agent.yml` konfiguruje `agent_vm` i uzywa sekretu `pg_monitor_password` z Vault.
3. `ansible/setup.yml` konfiguruje `azure_vm`, kopiuje `docker-compose.yml` i `docker/.env`, uruchamia stack kontenerow.
4. `make open` probuje otworzyc `http://<public_ip_address>` z outputu Terraform.

Istotne zaleznosci:

- `ansible/setup.yml` wymaga lokalnego pliku `docker/.env`.
- `ansible/install_agent.yml` wymaga odszyfrowywalnego `ansible/secrets.yml`.
- inventory jest artefaktem Terraform (`local_file`) i moze zostac nadpisane przy kolejnym `apply`.

## 3. Repozytorium (kluczowe pliki)

- `Makefile` - orchestration (`init`, `plan`, `apply`, `provision`, `deploy`, `destroy`).
- `terraform/main.tf` - RG, VNet, Subnet, NSG, NIC, 2x VM, public IP, inventory output.
- `ansible/install_agent.yml` - konfiguracja `agent_vm`, `vars_files: secrets.yml`.
- `ansible/setup.yml` - konfiguracja `azure_vm`, Docker, Compose, Agent 2, SWAP.
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

Wymagana kolekcja Ansible (uzywana przez `community.docker.docker_compose_v2`):

```bash
ansible-galaxy collection install community.docker
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
- brak pliku przerwie playbook `ansible/setup.yml` na tasku kopiowania `.env`.

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
make init
make plan
make apply AUTO=1
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

## 9. Znane punkty awarii

- `Vault secret not found`/`Decryption failed`: brak `ansible/secrets.yml` lub bledne haslo Vault.
- `copy ../docker/.env failed`: brak `docker/.env` lokalnie.
- `UNREACHABLE!`: niespojny klucz SSH, zly user, niedostepny host.
- Zabbix UI na `:80` nie odpowiada: kontenery jeszcze startuja lub blad DB init.
- Rozjazd IP: `ansible/inventory.ini` nadpisywane przez Terraform, nie edytowac recznie trwale.

## 10. Bezpieczenstwo operacyjne

- Sekrety trzymaj tylko w `ansible/secrets.yml` (Vault) i lokalnym `docker/.env`.
- Nie commituj `terraform/.ssh/`, `ansible/secrets.yml`, `.env`.
- Ograniczaj publiczny dostep do NSG (obecnie otwarte `22` i `80` globalnie).
- Po testach usun zasoby, aby uniknac kosztow.

## 11. Deprovisioning

```bash
make destroy CONFIRM=YES AUTO=1
```

Komenda usuwa zasoby Terraform utworzone w Azure.

