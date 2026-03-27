# --- Zmienne ---
SHELL       := /bin/bash
TF_DIR      := terraform
ANSIBLE_DIR := ansible
TF          := terraform -chdir=$(TF_DIR)

# Ścieżki Ansible
INVENTORY   := $(ANSIBLE_DIR)/inventory.ini
SITE_PLAY   := $(ANSIBLE_DIR)/playbook.yaml
ANSIBLE_CFG := $(ANSIBLE_DIR)/ansible.cfg
ANSIBLE_REQ := $(ANSIBLE_DIR)/requirements.yml

# SSH (z fallbackiem do ansible/inventory.ini)
SSH_USER    ?= $(shell awk -F= '/^ansible_user=/{print $$2; exit}' $(INVENTORY))
SSH_KEY     ?= $(shell awk -F= '/^ansible_ssh_private_key_file=/{print $$2; exit}' $(INVENTORY))
SSH_OPTS    ?= $(shell awk '/^ansible_ssh_common_args=/{sub(/^ansible_ssh_common_args=/,""); print; exit}' $(INVENTORY) | sed 's/^"//; s/"$$//')
SERVER_HOST ?= $(shell awk '/^\[azure_vm\]/{f=1;next}/^\[/{f=0}f && NF {print $$1; exit}' $(INVENTORY))
AGENT_HOST  ?= $(shell awk '/^\[agent_vm\]/{f=1;next}/^\[/{f=0}f && NF {print $$1; exit}' $(INVENTORY))

# --- Cele główne (Phony) ---
.PHONY: help init plan apply provision ansible-deps ansible-check deploy status ping open ssh-server ssh-agent destroy clean

help:
	@echo "Dostepne cele:"
	@echo "  make init                 - Inicjalizacja Terraform"
	@echo "  make plan                 - Pokaz plan zmian"
	@echo "  make apply [AUTO=1]       - Zastosuj zmiany (AUTO=1 zatwierdza automatycznie)"
	@echo "  make ansible-deps         - Instalacja kolekcji Ansible z requirements.yml"
	@echo "  make ansible-check        - Sprawdzenie skladni playbooka (wymaga hasla Vault)"
	@echo "  make provision            - Konfiguracja Ansible (wymaga hasła Vault)"
	@echo "  make deploy               - Full stack: Apply + Provision"
	@echo "  make status               - Sprawdz IP i polaczenie"
	@echo "  make ssh-server           - Polacz SSH z serwerem (azure_vm)"
	@echo "  make ssh-agent            - Polacz SSH z agentem (agent_vm)"
	@echo "     + opcje: SSH_USER=... SSH_KEY=... SSH_OPTS='-o ...'"
	@echo "  make destroy CONFIRM=YES  - Usun infrastrukture"

# --- Terraform ---
init:
	$(TF) init

plan:
	$(TF) plan

# Uproszczona logika auto-approve
apply:
	$(TF) apply $(if $(filter 1,$(AUTO)),-auto-approve,)

destroy:
	@if [ "$(CONFIRM)" != "YES" ]; then \
		echo "BŁĄD: Uruchom: make destroy CONFIRM=YES"; exit 1; \
	fi
	$(TF) destroy $(if $(filter 1,$(AUTO)),-auto-approve,)

# --- Ansible ---
provision:
	ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(SITE_PLAY) --ask-vault-pass

ansible-deps:
	ansible-galaxy collection install -r $(ANSIBLE_REQ) --force

ansible-check:
	ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible-playbook -i $(INVENTORY) $(SITE_PLAY) --syntax-check --ask-vault-pass

ping:
	ANSIBLE_CONFIG=$(ANSIBLE_CFG) ansible -i $(INVENTORY) all -m ping

# --- Narzędzia ---
deploy: init apply provision open

status:
	@echo "== Terraform outputs =="
	@$(TF) output || true
	@echo "== Ansible ping =="
	@make ping || true

open:
	@ip=$$($(TF) output -raw public_ip_address 2>/dev/null); \
	if [ -n "$$ip" ]; then \
		echo "Otwieram http://$$ip"; \
		xdg-open "http://$$ip" >/dev/null 2>&1 || open "http://$$ip" >/dev/null 2>&1 || echo "Otwórz ręcznie: http://$$ip"; \
	else \
		echo "Brak IP. Uruchom: make apply"; \
	fi

ssh-server:
	@host="$(SERVER_HOST)"; \
	if [ -z "$$host" ]; then \
		echo "Brak hosta [azure_vm] w $(INVENTORY)"; exit 1; \
	fi; \
	echo "Lacze: $(SSH_USER)@$$host"; \
	ssh $(if $(SSH_KEY),-i $(SSH_KEY),) $(SSH_OPTS) "$(SSH_USER)@$$host"

ssh-agent:
	@host="$(AGENT_HOST)"; \
	if [ -z "$$host" ]; then \
		echo "Brak hosta [agent_vm] w $(INVENTORY)"; exit 1; \
	fi; \
	echo "Lacze: $(SSH_USER)@$$host"; \
	ssh $(if $(SSH_KEY),-i $(SSH_KEY),) $(SSH_OPTS) "$(SSH_USER)@$$host"

clean:
	rm -rf $(TF_DIR)/.terraform $(TF_DIR)/.terraform.lock.hcl