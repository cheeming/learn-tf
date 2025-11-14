
plan:
	terraform plan -out=tfplan -target=${TARGET}
	tf-summarize tfplan

apply:
	terraform apply tfplan && rm tfplan
