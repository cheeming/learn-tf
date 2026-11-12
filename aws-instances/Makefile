setup:
	[ ! -f .envrc ] && (cp .envrc.EXAMPLE .envrc && echo "Please setup .envrc" ) || true
	direnv allow .

plan:
	terraform plan -out=tfplan -target=${TARGET}
	tf-summarize tfplan

check-diff:
	terraform plan -out=tfplan.tmp -lock=false && tf-summarize tfplan.tmp && rm tfplan.tmp

apply:
	terraform apply tfplan && rm tfplan

destroy:
	terraform plan -destroy -out=tfplan -target=${TARGET}
	tf-summarize tfplan

update_s3:
	TARGET=aws_s3_object.shadowsock_files $(MAKE) plan
	$(MAKE) apply
