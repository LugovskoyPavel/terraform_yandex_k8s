#!/bin/bash
sudo helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && \
sudo helm repo update
sudo helm install my-prom prometheus-community/prometheus
wait
sudo helm repo add tricksterproxy https://helm.tricksterproxy.io
sudo helm repo update
sudo helm install trickster tricksterproxy/trickster --namespace default -f trickster.yaml
sudo kubectl apply -f grafana.yaml
