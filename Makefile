KIND_CLUSTER_NAME=local-dev

IMAGE_MINICA="kind-local-minica:local"
IMAGE_RENDER="kind-local-render:local"

ARCH=$(shell ./bin/arch.sh)
OS=$(shell ./bin/os.sh)

DOCKER_RUN_MINICA=docker run --rm -v "$(shell pwd)/certs:/srv" -w /srv $(IMAGE_MINICA)
DOCKER_RUN_RENDER=docker run -it --rm -v "$(shell pwd):/srv" -w /srv $(IMAGE_RENDER)
DOCKER_RUN_JSONNET_CI=docker run --rm -v "$(shell pwd)/cluster/telemetry/kube-prometheus:/srv" -w /srv quay.io/coreos/jsonnet-ci

# This is a combination of the following suggestions:
# https://gist.github.com/prwhite/8168133#gistcomment-1420062
help: ## This help dialog.
	@IFS=$$'\n' ; \
	help_lines=(`fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##/:/'`); \
	printf "%-30s %s\n" "target" "help" ; \
	printf "%-30s %s\n" "------" "----" ; \
	for help_line in $${help_lines[@]}; do \
			IFS=$$':' ; \
			help_split=($$help_line) ; \
			help_command=`echo $${help_split[0]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
			help_info=`echo $${help_split[2]} | sed -e 's/^ *//' -e 's/ *$$//'` ; \
			printf '\033[36m'; \
			printf "%-30s %s" $$help_command ; \
			printf '\033[0m'; \
			printf "%s\n" $$help_info; \
	done

# --- local images --- #
.PHONY: build-render-image
build-render-image:
	docker build --target=final -t $(IMAGE_RENDER) ./docker/images/render

.PHONY: build-minica-image
build-minica-image:
	docker build --target=final -t $(IMAGE_MINICA) ./docker/images/minica

.PHONY: build-local-images
build-local-images: build-render-image build-minica-image

# --- local dev --- #

.PHONY: gen-certs
gen-certs:
	if [ ! -d ./certs/kubedash.dev ]; then $(DOCKER_RUN_MINICA) --domains kubedash.dev; fi;
	if [ ! -d ./certs/mailhog.dev ]; then $(DOCKER_RUN_MINICA) --domains mailhog.dev; fi;
	if [ ! -d ./certs/alertmanager.dev ]; then $(DOCKER_RUN_MINICA) --domains alertmanager.dev; fi;
	if [ ! -d ./certs/prometheus.dev ]; then $(DOCKER_RUN_MINICA) --domains prometheus.dev; fi;
	if [ ! -d ./certs/grafana.dev ]; then $(DOCKER_RUN_MINICA) --domains grafana.dev; fi;

.PHONY: dns
dns: context ## Configures hosts file with DNS entries; pulls ingress rules from k8s to create them
	./bin/dns.sh

.PHONY: tls-trust-ca
tls-trust-ca: ## Trust the self-signed HTTPS certification
	sudo security add-trusted-cert -d -r trustRoot -k "/Library/Keychains/System.keychain" "./certs/minica.pem"

.PHONY: install-hosts
install-hosts: ## Installs the hosts cli utility in ./bin
	curl -Lo ./bin/hosts.tar.gz https://github.com/txn2/txeh/releases/download/v1.3.0/txeh_macOS_amd64.tar.gz
	(cd ./bin && tar -xzvf hosts.tar.gz txeh)
	mv ./bin/txeh ./bin/hosts
	chmod +x ./bin/hosts
	rm ./bin/hosts.tar.gz

.PHONY: prepare-local
prepare-local: install-hosts install-operator-sdk build-local-images gen-certs

# --- Cluster ---
.PHONY: context
context: ## Switches to the kind cluster context (useful to ensure we don't run any of this crap on prod)
	@kubectl config use-context kind-$(KIND_CLUSTER_NAME)

.PHONY: cluster
cluster: kind-cluster telemetry ingress mailhog dashboard dns ## Spins up the base kubernetes platform, ready for application deployments

.PHONY: destroy
destroy: ## Completely destroys the k8s cluster and everything in it
	kind delete cluster --name $(KIND_CLUSTER_NAME)

.PHONY: dashboard
dashboard: context ## Deploys the kubernetes dashboard
	$(DOCKER_RUN_RENDER) --in ./cluster/dashboard/tls.secret.yaml.tmpl --out ./cluster/dashboard/rendered/tls.secret.yaml
	kubectl apply -f ./cluster/dashboard/namespace.yaml
	@sleep 1
	kubectl apply -f ./cluster/dashboard/rbac.yaml
	kubectl apply -f ./cluster/dashboard/rendered/tls.secret.yaml
	helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
	helm upgrade -n kube-dashboard --install -f ./cluster/dashboard/values.yaml kube-dashboard kubernetes-dashboard/kubernetes-dashboard 

.PHONY: rebuild
rebuild: destroy cluster ## Destroys and rebuilds the k8s cluster

.PHONY: kind-cluster
kind-cluster:
	kind create cluster \
	--name $(KIND_CLUSTER_NAME) \
	--kubeconfig=${HOME}/.kube/$(KIND_CLUSTER_NAME) \
	--config ./cluster/kind.cluster.yaml \
	--image=kindest/node:v1.21.1@sha256:69860bda5563ac81e3c0057d654b5253219618a22ec3a346306239bba8cfa1a6

.PHONY: ingress
ingress: context ## Enable the default minikube ingress addon
	curl -o ./cluster/ingress-nginx/manifests/ingress-nginx.yaml -L https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	kubectl apply -k ./cluster/ingress-nginx/
	until kubectl get deployment -n ingress-nginx ingress-nginx-controller &> /dev/null ; do sleep 1; done
	# Wait for the rollout to complete otherwise other stages will fail when adding ingress resources
	kubectl rollout status -n ingress-nginx -w deployment/ingress-nginx-controller

.PHONY: mailhog
mailhog: context ## Spins up mailhog which captures emais in local envs
	$(DOCKER_RUN_RENDER) --in ./cluster/mailhog/mailhog.ingress.yaml.tmpl --out ./cluster/mailhog/rendered/mailhog.ingress.yaml
	kubectl apply -f ./cluster/mailhog/mailhog.deployment.yaml
	kubectl apply -f ./cluster/mailhog/mailhog.svc.yaml
	kubectl apply -f ./cluster/mailhog/rendered/mailhog.ingress.yaml
	# We need this sleep to ensure that the ingress resource is created by  the time the dns task runs
	sleep 5

.PHONY: telemetry-ns
telemetry-ns: context
	$(DOCKER_RUN_RENDER) --in ./cluster/telemetry/alertmanager-tls.secret.yaml.tmpl --out ./cluster/telemetry/rendered/alertmanager-tls.secret.yaml
	$(DOCKER_RUN_RENDER) --in ./cluster/telemetry/prometheus-tls.secret.yaml.tmpl --out ./cluster/telemetry/rendered/prometheus-tls.secret.yaml
	$(DOCKER_RUN_RENDER) --in ./cluster/telemetry/grafana-tls.secret.yaml.tmpl --out ./cluster/telemetry/rendered/grafana-tls.secret.yaml
	kubectl apply -f ./cluster/telemetry/namespace.yaml
	@sleep 1
	kubectl apply -f ./cluster/telemetry/rendered/alertmanager-tls.secret.yaml
	kubectl apply -f ./cluster/telemetry/rendered/prometheus-tls.secret.yaml
	kubectl apply -f ./cluster/telemetry/rendered/grafana-tls.secret.yaml

.PHONY: add-bitnami-helm-charts
add-bitnami-helm-charts:
	helm repo add bitnami https://charts.bitnami.com/bitnami

.PHONY: prometheus-operator
prometheus: context add-bitnami-helm-charts
	helm upgrade -n telemetry -i -f ./cluster/telemetry/prometheus/operator/values.yaml --wait --wait-for-jobs prometheus-operator bitnami/kube-prometheus

.PHONY: grafana
grafana: context add-bitnami-helm-charts
	helm upgrade -n telemetry -i -f ./cluster/telemetry/grafana/operator/values.yaml --wait --wait-for-jobs grafana-operator bitnami/grafana-operator

.PHONY: grafana-resources
grafana-resources: context
	kubectl apply -f ./cluster/telemetry/grafana/datasources/prometheus.yaml
	# For some reason the grafana operator struggles without some time between 
	# Gets itself into a broken state so the dashboards can never be created
	sleep 5
	kubectl apply -f ./cluster/telemetry/grafana/dashboards/cluster.yaml
	kubectl apply -f ./cluster/telemetry/grafana/dashboards/nginx-ingress.yaml

.PHONY: telemetry
telemetry: telemetry-ns prometheus grafana grafana-resources

