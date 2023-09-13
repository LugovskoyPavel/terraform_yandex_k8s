resource "yandex_container_registry" "my-reg" {
  name = "my-registry"
  folder_id = var.yandex_folder_id
  labels = {
    my-label = "my-label-value"
  }
}

