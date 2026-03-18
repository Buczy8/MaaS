provision:
.PHONY: help init tf-init plan apply provision deploy status ping open destroy clean
SHELL := /bin/bash

TF_DIR := terraform
ANSIBLE_DIR := ansible
DOCKER_DIR := docker
ANSIBLE_PLAYBOOK := $(ANSIBLE_DIR)/setup.yml
ANSIBLE_INVENTORY := $(ANSIBLE_DIR)/inventory.ini
.PHONY: help init tf-init plan apply provision deploy status ping destroy clean

help:
	@echo "Dostepne cele:"
	@echo "  make init                 - terraform init"
	@echo "  make plan                 - terraform plan"
	@echo "  make apply                - terraform apply (AUTO_APPROVE=1 wlacza -auto-approve)"
	@echo "  make provision            - ansible-playbook setup.yml"
	@echo "  make deploy               - init -> plan -> apply -> provision"
	@echo "  make status               - terraform output + ansible ping"
	@echo "  make ping                 - szybkie polaczenie Ansible"
	@echo "  make open                 - otwiera http://<public_ip> w przegladarce"
	@echo "  make destroy CONFIRM=YES  - terraform destroy"
	@echo "  make clean                - usuniecie lokalnych artefaktow terraform"

tf-init:
	terraform -chdir=$(TF_DIR) init

init: tf-init

plan:
	terraform -chdir=$(TF_DIR) plan

apply:
	terraform -chdir=$(TF_DIR) apply $(if $(filter 1 true yes,$(AUTO_APPROVE)),-auto-approve,)

provision:
	ansible-playbook -i $(ANSIBLE_INVENTORY) $(ANSIBLE_PLAYBOOK)
	ansible-playbook -i $(ANSIBLE_INVENTORY) $(ANSIBLE_DIR)/install_agent.yml --ask-vault-pass

deploy: init plan apply provision

status:
	@echo "== Terraform outputs =="
	terraform -chdir=$(TF_DIR) output || true
	@echo "== Ansible ping =="
	ansible -i $(ANSIBLE_INVENTORY) all -m ping || true

ping:
	ansible -i $(ANSIBLE_INVENTORY) all -m ping

open:
	@ip=$$(terraform -chdir=$(TF_DIR) output -raw public_ip_address 2>/dev/null); \
	if [ -z "$$ip" ]; then \
		echo "Brak publicznego IP w stanie Terraform. Uruchom najpierw: make apply"; \
		exit 1; \
	fi; \
	url="http://$$ip"; \
	echo "Otwieram $$url"; \
	if command -v xdg-open >/dev/null 2>&1; then \
		xdg-open "$$url" >/dev/null 2>&1 & \
	else \
		echo "Nie znaleziono xdg-open. Otworz recznie: $$url"; \
	fi

destroy:
	@if [ "$(CONFIRM)" != "YES" ]; then \
		echo "Aby zniszczyc infrastrukture, uruchom: make destroy CONFIRM=YES"; \
		exit 1; \
	fi
	terraform -chdir=$(TF_DIR) destroy $(if $(filter 1 true yes,$(AUTO_APPROVE)),-auto-approve,)

clean:
	rm -rf $(TF_DIR)/.terraform
	rm -f $(TF_DIR)/.terraform.lock.hcl

