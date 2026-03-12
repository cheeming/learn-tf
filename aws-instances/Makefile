setup:
	[ ! -f .envrc ] && (cp .envrc.EXAMPLE .envrc && echo "Please setup .envrc" ) || true
	direnv allow .

plan:
	terraform plan -out=tfplan -target=${TARGET}
	tf-summarize tfplan

apply:
	terraform apply tfplan && rm tfplan

update_s3:
	TARGET=aws_s3_object.shadowsock_files $(MAKE) plan
	$(MAKE) apply
