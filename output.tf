output "cluster_external_v4_endpoint" {
  value = yandex_kubernetes_cluster.lugk8s.master[0].external_v4_endpoint
}

output "cluster_id" {
  value = yandex_kubernetes_cluster.lugk8s.id
}
output "registry_id" {
  description = "registry ID"
  value       = yandex_container_registry.my-reg.id
}