ENV ?= beijns
SOPS_AGE_KEY_FILE := $(HOME)/.config/sops/age/keys.txt
REGION := $(shell SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops -d $(ENV).tfvars | grep ^region | head -1 | cut -d'"' -f2)
EDITOR ?= code --wait

check-auth:
	@OCI_CLI_PROFILE=$(ENV) oci iam region list --auth security_token > /dev/null 2>&1 || \
		(echo "Session expired. Authenticating $(ENV)..."; \
		 oci session authenticate --profile-name $(ENV) --region $(REGION))

init: check-auth
	SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) \
	env $$(SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops -d secrets/$(ENV).env) \
		sops exec-file $(ENV).tfvars \
		'tofu init -reconfigure \
		-backend-config="key=$(ENV).tfstate" \
		-var-file={} \
		-var="config_file_profile=$(ENV)"'

plan: check-auth
	SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) \
	env $$(SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops -d secrets/$(ENV).env) \
		sops exec-file $(ENV).tfvars \
		'tofu plan -var-file={} -var="config_file_profile=$(ENV)"'

deploy: check-auth
	SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) \
	env $$(SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops -d secrets/$(ENV).env) \
		sops exec-file $(ENV).tfvars \
		'tofu apply -var-file={} -var="config_file_profile=$(ENV)"'

edit:
	@EDITOR="$(EDITOR)" SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops $(ENV).tfvars; \
		rc=$$?; test $$rc -eq 200 -o $$rc -eq 0 || exit $$rc
	@EDITOR="$(EDITOR)" SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops secrets/$(ENV).env; \
		rc=$$?; test $$rc -eq 200 -o $$rc -eq 0 || exit $$rc

fmt:
	find . -name '*.tf' -exec tofu fmt {} +

validate:
	tofu validate
