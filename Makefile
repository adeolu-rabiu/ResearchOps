.PHONY: init plan apply destroy provision backup test-ping test-condor test-prometheus test-all

init:
	cd terraform && terraform init

plan:
	cd terraform && terraform plan

apply:
	cd terraform && terraform apply -auto-approve

destroy:
	cd terraform && terraform destroy -auto-approve

provision:
	ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml

backup:
	rsync -avz --delete /mnt/vmdata/researchops/ /mnt/datastore2tb/researchops-backup/
	@echo "Backup complete: $$(date)"

test-ping:
	ansible all -i ansible/inventory/hosts.ini -m ping

test-condor:
	ssh root@10.0.0.11 condor_status

test-prometheus:
	curl -sf http://10.0.0.15:9090/-/healthy && echo "Prometheus OK"

test-all: test-ping test-condor test-prometheus
	@echo "All tests passed"

log-phase:
	@echo "Logging deployment at $$(date)" >> docs/phases/$(PHASE)/deployment-log.md
