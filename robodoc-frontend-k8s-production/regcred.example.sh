kubectl create secret docker-registry regcred \
  --docker-server=registry.digitalocean.com \
  --docker-username=YOUR_DO_EMAIL \
  --docker-password=YOUR_DO_API_TOKEN \
  --docker-email=YOUR_DO_EMAIL \
  --namespace=robodoc \
  --dry-run=client -o yaml | kubectl apply -f -
