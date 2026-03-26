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

# --- Cele główne (Phony) ---
.PHONY: help init plan apply provision ansible-deps ansible-check deploy status ping open destroy clean

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
	ansible-galaxy collection install -r $(ANSIBLE_REQ)

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

clean:
	rm -rf $(TF_DIR)/.terraform $(TF_DIR)/.terraform.lock.hcl