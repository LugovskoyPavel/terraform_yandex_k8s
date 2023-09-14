# Дипломный практикум в Yandex.Cloud студента Луговского П.С.
 
---
## Цели:

1. Подготовить облачную инфраструктуру на базе облачного провайдера Яндекс.Облако.
2. Запустить и сконфигурировать Kubernetes кластер.
3. Установить и настроить систему мониторинга.
4. Настроить и автоматизировать сборку тестового приложения с использованием Docker-контейнеров.
5. Настроить CI для автоматической сборки и тестирования.
6. Настроить CD для автоматического развёртывания приложения.

---
## Этапы выполнения:


### Создание облачной инфраструктуры

Для начала необходимо подготовить облачную инфраструктуру в ЯО при помощи [Terraform](https://www.terraform.io/).

Особенности выполнения:

- Бюджет купона ограничен, что следует иметь в виду при проектировании инфраструктуры и использовании ресурсов;
- Следует использовать последнюю стабильную версию [Terraform](https://www.terraform.io/).

Предварительная подготовка к установке и запуску Kubernetes кластера.

1. Создайте сервисный аккаунт, который будет в дальнейшем использоваться Terraform для работы с инфраструктурой с необходимыми и достаточными правами. Не стоит использовать права суперпользователя
2. Подготовьте [backend](https://www.terraform.io/docs/language/settings/backends/index.html) для Terraform:  
   а. Рекомендуемый вариант: [Terraform Cloud](https://app.terraform.io/)  
   б. Альтернативный вариант: S3 bucket в созданном ЯО аккаунте
3. Настройте [workspaces](https://www.terraform.io/docs/language/state/workspaces.html)  
   а. Рекомендуемый вариант: создайте два workspace: *stage* и *prod*. В случае выбора этого варианта все последующие шаги должны учитывать факт существования нескольких workspace.  
   б. Альтернативный вариант: используйте один workspace, назвав его *stage*. Пожалуйста, не используйте workspace, создаваемый Terraform-ом по-умолчанию (*default*).
4. Создайте VPC с подсетями в разных зонах доступности.
5. Убедитесь, что теперь вы можете выполнить команды `terraform destroy` и `terraform apply` без дополнительных ручных действий.
6. В случае использования [Terraform Cloud](https://app.terraform.io/) в качестве [backend](https://www.terraform.io/docs/language/settings/backends/index.html) убедитесь, что применение изменений успешно проходит, используя web-интерфейс Terraform cloud.

Ожидаемые результаты:

1. Terraform сконфигурирован и создание инфраструктуры посредством Terraform возможно без дополнительных ручных действий. 

Ответ: Terraform сконфигурирован и создан. В качестве backend выбран Terraform Cloud с одним workspace - stage

```
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    
  }
  cloud {
    organization = "lug-org"
    workspaces {
      tags = ["stage"]
    }
  }
}
```
![image](https://github.com/LugovskoyPavel/terraform_yandex_k8s/assets/104651372/b0fb7e88-2641-4daa-b981-3e2b5484b862)


Конфигурационный файл terraform для yandex cloud

```
locals {
  
  k8s_version = "1.23"
  
}

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    
  }
  cloud {
    organization = "lug-org"
    workspaces {
      tags = ["stage"]
    }
  }
}

provider "yandex" {
  zone = "ru-central1-a"
  service_account_key_file = "key.json"
  cloud_id  = "${var.yandex_cloud_id}"
  folder_id = "${var.yandex_folder_id}"
}

resource "yandex_kubernetes_cluster" "lugk8s" {
  network_id = yandex_vpc_network.mynet.id
 
  master {
    version = local.k8s_version
    public_ip=true
    regional {
      region = "ru-central1"
      
      location {
        zone      = yandex_vpc_subnet.mysubnet-a.zone
        subnet_id = yandex_vpc_subnet.mysubnet-a.id
      }
      location {
        zone      = yandex_vpc_subnet.mysubnet-b.zone
        subnet_id = yandex_vpc_subnet.mysubnet-b.id
      }
      location {
        zone      = yandex_vpc_subnet.mysubnet-c.zone
        subnet_id = yandex_vpc_subnet.mysubnet-c.id
      }
    }
    
  }
  service_account_id      = "ajelifsgup0jg2bkjr6t"
  node_service_account_id = "ajelifsgup0jg2bkjr6t"
  kms_provider {
    key_id = yandex_kms_symmetric_key.kms-key.id
  }
}

resource "yandex_vpc_network" "mynet" {
  name = "mynet"
}

resource "yandex_vpc_subnet" "mysubnet-a" {
  v4_cidr_blocks = ["10.5.0.0/16"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mynet.id
}

resource "yandex_vpc_subnet" "mysubnet-b" {
  v4_cidr_blocks = ["10.6.0.0/16"]
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.mynet.id
}

resource "yandex_vpc_subnet" "mysubnet-c" {
  v4_cidr_blocks = ["10.7.0.0/16"]
  zone           = "ru-central1-c"
  network_id     = yandex_vpc_network.mynet.id
}

resource "yandex_kms_symmetric_key" "kms-key" {
  # Ключ для шифрования важной информации, такой как пароли, OAuth-токены и SSH-ключи.
  name              = "kms-key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h" # 1 год.
}

resource "yandex_kubernetes_node_group" "node-group-0" {
  cluster_id  = yandex_kubernetes_cluster.lugk8s.id
  name        = "node-group-0"
  version     = local.k8s_version

  instance_template {
    platform_id = "standard-v2"
    nat         = true

    resources {
      memory = 4
      cores  = 2
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    scheduling_policy {
      preemptible = false
    }
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }

    location {
      zone = "ru-central1-b"
    }

    location {
      zone = "ru-central1-c"
    }
  }

  maintenance_policy {
    auto_upgrade = false
    auto_repair  = true
  }
  

}

```
2. Полученная конфигурация инфраструктуры является предварительной, поэтому в ходе дальнейшего выполнения задания возможны изменения.

Ответ: Конфигурация создана (уже с k8s кластером)

```
PS C:\Users\lugy1\terraform_yandex_k8s> terraform apply
Running apply in Terraform Cloud. Output will stream here. Pressing Ctrl-C
will cancel the remote apply if it's still pending. If the apply started it
will stop streaming the logs, but will not stop the apply running remotely.

Preparing the remote apply...

To view this run in a browser, visit:
https://app.terraform.io/app/lug-org/stage/runs/run-mz8ZP2p9AbKZWU5G

Waiting for the plan to start...

Terraform v1.5.3
on linux_amd64
Initializing plugins and modules...
yandex_container_registry.my-reg: Refreshing state... [id=crp52u9gli262gfbvk5r]
yandex_kms_symmetric_key.kms-key: Refreshing state... [id=abjbje6s09h16iqphvig]
yandex_container_registry.my-reg: Drift detected (delete)
yandex_kms_symmetric_key.kms-key: Drift detected (delete)

Note: Objects have changed outside of Terraform

Terraform detected the following changes made outside of Terraform since the last "terraform apply" which may have affected this plan:

  # yandex_container_registry.my-reg has been deleted
  - resource "yandex_container_registry" "my-reg" {
      - id         = "crp52u9gli262gfbvk5r" -> null
        name       = "my-registry"
        # (4 unchanged attributes hidden)
    }

  # yandex_kms_symmetric_key.kms-key has been deleted
  - resource "yandex_kms_symmetric_key" "kms-key" {
      - id                  = "abjbje6s09h16iqphvig" -> null
        name                = "kms-key"
        # (7 unchanged attributes hidden)
    }


Unless you have made equivalent changes to your configuration, or ignored the relevant attributes using ignore_changes, the following plan may include actions to undo or respond to these changes.

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── 

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # yandex_container_registry.my-reg will be created
  + resource "yandex_container_registry" "my-reg" {
      + created_at = (known after apply)
      + folder_id  = "b1gtuqdg509g01fvo4sm"
      + id         = (known after apply)
      + labels     = {
          + "my-label" = "my-label-value"
        }
      + name       = "my-registry"
      + status     = (known after apply)
    }

  # yandex_kms_symmetric_key.kms-key will be created
  + resource "yandex_kms_symmetric_key" "kms-key" {
      + created_at          = (known after apply)
      + default_algorithm   = "AES_128"
      + deletion_protection = false
      + folder_id           = (known after apply)
      + id                  = (known after apply)
      + name                = "kms-key"
      + rotated_at          = (known after apply)
      + rotation_period     = "8760h"
      + status              = (known after apply)
    }

  # yandex_kubernetes_cluster.lugk8s will be created
  + resource "yandex_kubernetes_cluster" "lugk8s" {
      + cluster_ipv4_range       = (known after apply)
      + cluster_ipv6_range       = (known after apply)
      + created_at               = (known after apply)
      + description              = (known after apply)
      + folder_id                = (known after apply)
      + health                   = (known after apply)
      + id                       = (known after apply)
      + labels                   = (known after apply)
      + log_group_id             = (known after apply)
      + name                     = (known after apply)
      + network_id               = (known after apply)
      + node_ipv4_cidr_mask_size = 24
      + node_service_account_id  = "ajelifsgup0jg2bkjr6t"
      + release_channel          = (known after apply)
      + service_account_id       = "ajelifsgup0jg2bkjr6t"
      + service_ipv4_range       = (known after apply)
      + service_ipv6_range       = (known after apply)
      + status                   = (known after apply)

      + kms_provider {
          + key_id = (known after apply)
        }

      + master {
          + cluster_ca_certificate = (known after apply)
          + external_v4_address    = (known after apply)
          + external_v4_endpoint   = (known after apply)
          + external_v6_endpoint   = (known after apply)
          + internal_v4_address    = (known after apply)
          + internal_v4_endpoint   = (known after apply)
          + public_ip              = true
          + version                = "1.23"
          + version_info           = (known after apply)

          + regional {
              + region = "ru-central1"

              + location {
                  + subnet_id = (known after apply)
                  + zone      = "ru-central1-a"
                }
              + location {
                  + subnet_id = (known after apply)
                  + zone      = "ru-central1-b"
                }
              + location {
                  + subnet_id = (known after apply)
                  + zone      = "ru-central1-c"
                }
            }
        }
    }

  # yandex_kubernetes_node_group.node-group-0 will be created
  + resource "yandex_kubernetes_node_group" "node-group-0" {
      + cluster_id        = (known after apply)
      + created_at        = (known after apply)
      + description       = (known after apply)
      + id                = (known after apply)
      + instance_group_id = (known after apply)
      + labels            = (known after apply)
      + name              = "node-group-0"
      + status            = (known after apply)
      + version           = "1.23"
      + version_info      = (known after apply)

      + allocation_policy {
          + location {
              + subnet_id = (known after apply)
              + zone      = "ru-central1-a"
            }
          + location {
              + subnet_id = (known after apply)
              + zone      = "ru-central1-b"
            }
          + location {
              + subnet_id = (known after apply)
              + zone      = "ru-central1-c"
            }
        }

      + instance_template {
          + metadata                  = (known after apply)
          + nat                       = true
          + network_acceleration_type = (known after apply)
          + platform_id               = "standard-v2"

          + boot_disk {
              + size = 64
              + type = "network-hdd"
            }

          + resources {
              + core_fraction = (known after apply)
              + cores         = 2
              + gpus          = 0
              + memory        = 4
            }

          + scheduling_policy {
              + preemptible = false
            }
        }

      + maintenance_policy {
          + auto_repair  = true
          + auto_upgrade = false
        }

      + scale_policy {
          + fixed_scale {
              + size = 3
            }
        }
    }

  # yandex_vpc_network.mynet will be created
  + resource "yandex_vpc_network" "mynet" {
      + created_at                = (known after apply)
      + default_security_group_id = (known after apply)
      + folder_id                 = (known after apply)
      + id                        = (known after apply)
      + labels                    = (known after apply)
      + name                      = "mynet"
      + subnet_ids                = (known after apply)
    }

  # yandex_vpc_subnet.mysubnet-a will be created
  + resource "yandex_vpc_subnet" "mysubnet-a" {
      + created_at     = (known after apply)
      + folder_id      = (known after apply)
      + id             = (known after apply)
      + labels         = (known after apply)
      + name           = (known after apply)
      + network_id     = (known after apply)
      + v4_cidr_blocks = [
          + "10.5.0.0/16",
        ]
      + v6_cidr_blocks = (known after apply)
      + zone           = "ru-central1-a"
    }

  # yandex_vpc_subnet.mysubnet-b will be created
  + resource "yandex_vpc_subnet" "mysubnet-b" {
      + created_at     = (known after apply)
      + folder_id      = (known after apply)
      + id             = (known after apply)
      + labels         = (known after apply)
      + name           = (known after apply)
      + network_id     = (known after apply)
      + v4_cidr_blocks = [
          + "10.6.0.0/16",
        ]
      + v6_cidr_blocks = (known after apply)
      + zone           = "ru-central1-b"
    }

  # yandex_vpc_subnet.mysubnet-c will be created
  + resource "yandex_vpc_subnet" "mysubnet-c" {
      + created_at     = (known after apply)
      + folder_id      = (known after apply)
      + id             = (known after apply)
      + labels         = (known after apply)
      + name           = (known after apply)
      + network_id     = (known after apply)
      + v4_cidr_blocks = [
          + "10.7.0.0/16",
        ]
      + v6_cidr_blocks = (known after apply)
      + zone           = "ru-central1-c"
    }

Plan: 8 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + cluster_external_v4_endpoint = (known after apply)
  + cluster_id                   = (known after apply)
  + registry_id                  = (known after apply)

Do you want to perform these actions in workspace "stage"?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.
```

---
### Создание Kubernetes кластера

На этом этапе необходимо создать [Kubernetes](https://kubernetes.io/ru/docs/concepts/overview/what-is-kubernetes/) кластер на базе предварительно созданной инфраструктуры.   Требуется обеспечить доступ к ресурсам из Интернета.

Это можно сделать двумя способами:

1. Рекомендуемый вариант: самостоятельная установка Kubernetes кластера.  
   а. При помощи Terraform подготовить как минимум 3 виртуальных машины Compute Cloud для создания Kubernetes-кластера. Тип виртуальной машины следует выбрать самостоятельно с учётом требовании к производительности и стоимости. Если в дальнейшем поймете, что необходимо сменить тип инстанса, используйте Terraform для внесения изменений.  
   б. Подготовить [ansible](https://www.ansible.com/) конфигурации, можно воспользоваться, например [Kubespray](https://kubernetes.io/docs/setup/production-environment/tools/kubespray/)  
   в. Задеплоить Kubernetes на подготовленные ранее инстансы, в случае нехватки каких-либо ресурсов вы всегда можете создать их при помощи Terraform.
2. Альтернативный вариант: воспользуйтесь сервисом [Yandex Managed Service for Kubernetes](https://cloud.yandex.ru/services/managed-kubernetes)  
  а. С помощью terraform resource для [kubernetes](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/kubernetes_cluster) создать региональный мастер kubernetes с размещением нод в разных 3 подсетях      
  б. С помощью terraform resource для [kubernetes node group](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs/resources/kubernetes_node_group)
  
Ожидаемый результат:

1. Работоспособный Kubernetes кластер.

Ответ: Кластер создан с помощью Yandex Managed Service for Kubernetes, создано три ноды, создан региональный кластер, с размещением нод в разных 3 подсетях

![image](https://github.com/LugovskoyPavel/terraform_yandex_k8s/assets/104651372/fd289264-a320-4054-bd1c-99bc00c27f20)


2. В файле `~/.kube/config` находятся данные для доступа к кластеру.

Ответ: Конфигурационный файл получен для созданного кластера с помощью команды 

```
yc managed-kubernetes cluster get-credentials --id catd205ilrqs17rokmj9 --external
```
Содержание конфигурационного файла
```
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUM1ekNDQWMrZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJek1Ea3hOREU0TWpFd09Wb1hEVE16TURreE1URTRNakV3T1Zvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTWF3CmlwMVNiS1Fkb0IxUjdVWTZpeStKNUYxVkUxTENLczZrenVwVVJkTXNOWXZiM1ZrUjlOb3A5cnVsY2UvOGYxK0kKdDZBdzRIZWZuZnVJUlFXRThtdThxUUQxZ0h4N25VWmVNZmZtRWk2OTNrdVNKRzNtZlJ2OXBoeXQxV2MvU0h1QgpLRmhVaTRBQ0hKZjlnYVp2YUltSnovV0ZNZnlLdUNONDc2M3d4TXVrWllrTUY5aVpHN0F3L0tKZThBNSswNlBMCjBjYzl4R3hUcVVhMVJlK1FLbGlVNUFKT2lxdzR2WGdJdFBrZTBWTTEvY1pmM01WUExLdS9rRmpjbGtVUXpCZWoKaFhzZUp5bDNuMHZSRXRzZFpQUXVuSlNZcDYyV20xRlBEeHZ1UVAxN2hYTnV5cm1Wek56cVdoVVJtcWlTQW4wKwpoZkpybk5SMzdZOFBWekZ4ZFhFQ0F3RUFBYU5DTUVBd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0hRWURWUjBPQkJZRUZHV2lsaDN3LzFGYmV5ZlZOL2VIenhtTG5lQlFNQTBHQ1NxR1NJYjMKRFFFQkN3VUFBNElCQVFCM0wxU3daM0lXUDJINjFDLzA5bVk1Ny9nYWVacVYrdlVQc3BuNmdmd3MzN21QRE9wOQpycDRGZi9YTGdrZ1NVT3BycVRBREhVMlpWeUhoKzJsOFpkVENodW0yYlVWbm5GQWlkZ09WdWRvM1QrV0tndC9oClR4Yjk1V3pUS1JwYkdUNytoRnhSUXJ4VmRMRDZPcjlhWVBqU3ZYVFJ4ZWd6R1AwOStKTXRwK2hBRk0xa01Md3UKSE5TT0hHbHJrbzNXZE1PTHB1bUhFWW1xUXJvR0VXVk13bjJKeW1paGgzRFNCb2ZkTmQ1RG16SjBrd0dqaHJZSQovb1ZTdVNyZGxveGFHQlk4SjdBUTNRLzhDSlFMckF3bXhmV2VRWWgzNHJiVTlZeGNzL3JaV0Rsdmorbjh3M0d2CjlWSVM3UDUrTDY5a1hZMTZzRUkvamRWcjR1U0tsallNQzJ4VgotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    server: https://158.160.29.61
  name: yc-managed-k8s-catd205ilrqs17rokmj9
contexts:
- context:
    cluster: yc-managed-k8s-catd205ilrqs17rokmj9
    user: yc-managed-k8s-catd205ilrqs17rokmj9
  name: yc-managed-k8s-catd205ilrqs17rokmj9
current-context: yc-managed-k8s-catd205ilrqs17rokmj9
kind: Config
preferences: {}
users:
- name: yc-managed-k8s-catd205ilrqs17rokmj9
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - k8s
      - create-token
      - --profile=lugter
      command: C:\Users\lugy1\yandex-cloud\bin\yc.exe
      env: null
      provideClusterInfo: false

```

3. Команда `kubectl get pods --all-namespaces` отрабатывает без ошибок.

Ответ: Результат выполнения команды

```
PS C:\Users\lugy1\terraform_yandex_k8s> kubectl get pods --all-namespaces
NAMESPACE     NAME                                   READY   STATUS    RESTARTS   AGE
kube-system   coredns-84b7668fb4-4b65s               1/1     Running   0          22m
kube-system   coredns-84b7668fb4-b9d62               1/1     Running   0          18m
kube-system   ip-masq-agent-4zkww                    1/1     Running   0          18m
kube-system   ip-masq-agent-9ll89                    1/1     Running   0          18m
kube-system   ip-masq-agent-p97x5                    1/1     Running   0          18m
kube-system   kube-dns-autoscaler-75b9577f68-mw4q8   1/1     Running   0          21m
kube-system   kube-proxy-cpxqt                       1/1     Running   0          18m
kube-system   kube-proxy-ktzqp                       1/1     Running   0          18m
kube-system   kube-proxy-nj2gs                       1/1     Running   0          18m
kube-system   metrics-server-6f8c7f57fd-qqn9b        2/2     Running   0          18m
kube-system   npd-v0.8.0-bbsvb                       1/1     Running   0          18m
kube-system   npd-v0.8.0-crxhh                       1/1     Running   0          18m
kube-system   npd-v0.8.0-rw4vf                       1/1     Running   0          18m
kube-system   yc-disk-csi-node-v2-c8kgb              6/6     Running   0          18m
kube-system   yc-disk-csi-node-v2-xmvt6              6/6     Running   0          18m
kube-system   yc-disk-csi-node-v2-xng5b              6/6     Running   0          18m
```
Подключение к кластеру через Lens

![image](https://github.com/LugovskoyPavel/terraform_yandex_k8s/assets/104651372/77e58013-6658-4ff4-a847-a47c0e8d9a71)


---
### Создание тестового приложения

Для перехода к следующему этапу необходимо подготовить тестовое приложение, эмулирующее основное приложение разрабатываемое вашей компанией.

Способ подготовки:

1. Рекомендуемый вариант:  
   а. Создайте отдельный git репозиторий с простым nginx конфигом, который будет отдавать статические данные.  
   б. Подготовьте Dockerfile для создания образа приложения.  
2. Альтернативный вариант:  
   а. Используйте любой другой код, главное, чтобы был самостоятельно создан Dockerfile.

Ожидаемый результат:

1. Git репозиторий с тестовым приложением и Dockerfile.

Ответ: Ссылка на репозиторий с тестовым приложением https://github.com/LugovskoyPavel/nginx_sample.git

В качестве приложение выбран простой nginx сервер cо стартовой страницей

2. Регистр с собранным docker image. В качестве регистра может быть DockerHub или [Yandex Container Registry](https://cloud.yandex.ru/services/container-registry), созданный также с помощью terraform.

Ответ: docker image собран с помощью GitHub Actions. Сборка происходит автоматически при коммитах в репозиторий.

![image](https://github.com/LugovskoyPavel/terraform_yandex_k8s/assets/104651372/8b0ee70e-c7e1-4e8f-b0b5-32ca57240c0d)

Код yaml файла с настройкой создания docker image

```
name: Docker

# This workflow uses actions that are not certified by GitHub.
# They are provided by a third-party and are governed by
# separate terms of service, privacy policy, and support
# documentation.

on:
  schedule:
    - cron: '45 4 * * *'
  push:
    branches: [ "main" ]
    # Publish semver tags as releases.
    tags: [ 'v*.*.*' ]
  pull_request:
    branches: [ "main" ]

env:
  # Use docker.io for Docker Hub if empty
  REGISTRY: ghcr.io
  # github.repository as <account>/<repo>
  IMAGE_NAME: ${{ github.repository }}


jobs:
  build:

    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      # This is used to complete the identity challenge
      # with sigstore/fulcio when running outside of PRs.
      id-token: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      # Workaround: https://github.com/docker/build-push-action/issues/461
      - name: Setup Docker buildx
        uses: docker/setup-buildx-action@79abd3f86f79a9d68a23c75a09a9a85889262adf

      # Login against a Docker registry except on PR
      # https://github.com/docker/login-action
      - name: Log into registry ${{ env.REGISTRY }}
        if: github.event_name != 'pull_request'
        uses: docker/login-action@28218f9b04b4f3f62068d7b6ce6ca5b26e35336c
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      # Extract metadata (tags, labels) for Docker
      # https://github.com/docker/metadata-action
      - name: Extract Docker metadata
        id: meta
        uses: docker/metadata-action@98669ae865ea3cffbcbaa878cf57c20bbf1c6c38
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}

      # Build and push Docker image with Buildx (don't push on PR)
      # https://github.com/docker/build-push-action
      - name: Build and push Docker image
        id: build-and-push
        uses: docker/build-push-action@ac9327eae2b366085ac7f6a2d02df8aa8ead720a
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```
---
### Подготовка cистемы мониторинга и деплой приложения

Уже должны быть готовы конфигурации для автоматического создания облачной инфраструктуры и поднятия Kubernetes кластера.  
Теперь необходимо подготовить конфигурационные файлы для настройки нашего Kubernetes кластера.

Цель:
1. Задеплоить в кластер [prometheus](https://prometheus.io/), [grafana](https://grafana.com/), [alertmanager](https://github.com/prometheus/alertmanager), [экспортер](https://github.com/prometheus/node_exporter) основных метрик Kubernetes.
2. Задеплоить тестовое приложение, например, [nginx](https://www.nginx.com/) сервер отдающий статическую страницу.

Рекомендуемый способ выполнения:
1. Воспользовать пакетом [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus), который уже включает в себя [Kubernetes оператор](https://operatorhub.io/) для [grafana](https://grafana.com/), [prometheus](https://prometheus.io/), [alertmanager](https://github.com/prometheus/alertmanager) и [node_exporter](https://github.com/prometheus/node_exporter). При желании можете собрать все эти приложения отдельно.
2. Для организации конфигурации использовать [qbec](https://qbec.io/), основанный на [jsonnet](https://jsonnet.org/). Обратите внимание на имеющиеся функции для интеграции helm конфигов и [helm charts](https://helm.sh/)
3. Если на первом этапе вы не воспользовались [Terraform Cloud](https://app.terraform.io/), то задеплойте в кластер [atlantis](https://www.runatlantis.io/) для отслеживания изменений инфраструктуры.

Альтернативный вариант:
1. Для организации конфигурации можно использовать [helm charts](https://helm.sh/)

Ожидаемый результат:
1. Git репозиторий с конфигурационными файлами для настройки Kubernetes.

Ответ: В качестве способа выполнения  воспользовался пакетом kube-prometheus

![image](https://github.com/LugovskoyPavel/terraform_yandex_k8s/assets/104651372/bc6097c0-0050-47cd-a8b1-46f937ce18f2)

2. Http доступ к web интерфейсу grafana.

Ответ: Доступ по  по адресу: http://51.250.33.86:30811

3. Дашборды в grafana отображающие состояние Kubernetes кластера.

Ответ: Скриншоты дашбордов grafana

![image](https://github.com/LugovskoyPavel/terraform_yandex_k8s/assets/104651372/e734a2d0-180c-4d1e-94e9-6e57c61f5cb4)

![image](https://github.com/LugovskoyPavel/terraform_yandex_k8s/assets/104651372/d51c58a1-35f1-48f5-ba77-36482afd0e32)


4. Http доступ к тестовому приложению.

Ответ: Тестовое приложение собрано

```
apiVersion: v1
kind: Namespace
metadata:
  name: netology
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: lug-app
  namespace: netology
  labels:
    k8s-app: lug-app
spec:
  replicas: 2
  selector:
    matchLabels:
      k8s-app: lug-app
  template:
    metadata:
      name: lug-app
      labels:
        k8s-app: lug-app
    spec:
      containers:
      - name: lug-nginx
        image: cr.yandex/crpjtbfk7rh581pgd1hk/my-registry:main
        imagePullPolicy: IfNotPresent
        
---
kind: Service
apiVersion: v1
metadata:
  name: nginx-lug
  namespace: netology
  labels:
    k8s-app: lug-app
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30080
  selector:
    k8s-app: lug-app
  type: NodePort
```
И установлено

```
PS C:\Users\lugy1\terraform_yandex_k8s> kubectl apply -f nginx_install.yaml
namespace/netology created
deployment.apps/lug-app created
service/nginx-lug created
```
Доступ к тестовому приложению http://51.250.33.86:30080/

![image](https://github.com/LugovskoyPavel/terraform_yandex_k8s/assets/104651372/9e9becda-b01c-4317-9c34-1c20c5f95e03)



---
### Установка и настройка CI/CD

Осталось настроить ci/cd систему для автоматической сборки docker image и деплоя приложения при изменении кода.

Цель:

1. Автоматическая сборка docker образа при коммите в репозиторий с тестовым приложением.
2. Автоматический деплой нового docker образа.

Можно использовать [teamcity](https://www.jetbrains.com/ru-ru/teamcity/), [jenkins](https://www.jenkins.io/), [GitLab CI](https://about.gitlab.com/stages-devops-lifecycle/continuous-integration/) или GitHub Actions.

Ожидаемый результат:

1. Интерфейс ci/cd сервиса доступен по http.

Ответ: В качестве ci/cd сервиса был выбран GitHub Actions. Была настроен pull образа docker при создании в yandex container registry
Делал вот по этой инструкции https://nikolaymatrosov.medium.com/github-action-%D0%B4%D0%BB%D1%8F-%D0%BF%D1%83%D1%88%D0%B0-%D0%B2-yandex-cloud-container-registry-cbe91d8b0198
Немного изменил строки кода, сделав возможным сбор образа с ранее создаваемого также с помощью GitHub Actions

Код отвечающий за регистрацию на yandex container registry и pull docker образа
```
deploy:

      runs-on: ubuntu-latest
      permissions:
        contents: read
        packages: write
      # This is used to complete the identity challenge
      # with sigstore/fulcio when running outside of PRs.
        id-token: write

      steps:      
      - name: Login to Yandex Cloud Container Registry
        id: login-cr
        uses: yc-actions/yc-cr-login@v1
        with:
          yc-sa-json-credentials: ${{ secrets.YC_SA_JSON_CREDENTIALS }}

      - name: Build, tag, and push image to Yandex Cloud Container Registry
        env:
          CR_REGISTRY: crp52u9gli262gfbvk5r
          CR_REPOSITORY: my-registry
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker pull ghcr.io/lugovskoypavel/nginx_sample:main
          docker tag ghcr.io/lugovskoypavel/nginx_sample:main cr.yandex/$CR_REGISTRY/$CR_REPOSITORY:main
          docker push cr.yandex/$CR_REGISTRY/$CR_REPOSITORY:main
```


2. При любом коммите в репозиторие с тестовым приложением происходит сборка и отправка в регистр Docker образа.

Ответ: Сборка настроина при любом комите

![image](https://github.com/LugovskoyPavel/terraform_yandex_k8s/assets/104651372/c2f6ebbc-ecae-4594-b990-2b3f7297a812)


3. При создании тега (например, v1.0.0) происходит сборка и отправка с соответствующим label в регистр, а также деплой соответствующего Docker образа в кластер Kubernetes.

Ответ: Строка кода отвечающая за выполнеие кода при создании тэга, также сборка и отправка в регистр Docker образа происходит по расписанию

```
on:
  schedule:
    - cron: '45 4 * * *'
  push:
    branches: [ "main" ]
    # Publish semver tags as releases.
    tags: [ 'v*.*.*' ]
  pull_request:
    branches: [ "main" ]
```
---
## Что необходимо для сдачи задания?

1. Репозиторий с конфигурационными файлами Terraform и готовность продемонстрировать создание всех ресурсов с нуля.
2. Пример pull request с комментариями созданными atlantis'ом или снимки экрана из Terraform Cloud.
3. Репозиторий с конфигурацией ansible, если был выбран способ создания Kubernetes кластера при помощи ansible.
4. Репозиторий с Dockerfile тестового приложения и ссылка на собранный docker image.
5. Репозиторий с конфигурацией Kubernetes кластера.
6. Ссылка на тестовое приложение и веб интерфейс Grafana с данными доступа.
7. Все репозитории рекомендуется хранить на одном ресурсе (github, gitlab)

---

