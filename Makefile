.PHONY: dev

help:
	@echo "Makefile targets:"
	@echo "  bootstrap-dev    Bootstrap dev environment with Flux"

# Bootstrap dev environment with Flux
bootstrap-dev:
	@echo "Creating flux-system namespace..."
	kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
	
	@echo "Creating sops-age secret from ~/.config/sops/age/keys.txt..."
	kubectl create secret generic sops-age \
		--namespace=flux-system \
		--from-file=age.agekey=$(HOME)/.config/sops/age/keys.txt \
		--dry-run=client -o yaml | kubectl apply -f -
	
	@echo "Bootstrapping Flux for dev environment..."
	flux bootstrap github \
		--owner=spoletum \
		--repository=flux \
		--branch=main \
		--path=clusters/dev \
		--personal
	
	@echo "✅ Dev environment bootstrapped successfully!"
	@echo "Watch deployment with: flux logs --follow"
