ENV ?= beijns

check-auth:
	@OCI_CLI_PROFILE=$(ENV) oci iam region list > /dev/null 2>&1 || \
		(echo "Session expired. Authenticating $(ENV)..."; \
		 oci session authenticate --profile $(ENV))

init: check-auth
	tofu init -reconfigure \
		-backend-config="key=$(ENV).tfstate" \
		-var-file=$(ENV).tfvars

plan: check-auth
	OCI_CLI_PROFILE=$(ENV) tofu plan -var-file=$(ENV).tfvars

deploy: check-auth
	OCI_CLI_PROFILE=$(ENV) tofu apply -var-file=$(ENV).tfvars

fmt:
	tofu fmt -recursive

validate:
	tofu validate
