terraform {
  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = "0.11.12"
    }
  }
}

provider "volterra" {
  api_p12_file = var.api_p12_file
  url          = var.api_url
}

locals {
  baseobj_csv = csvdecode(file("${path.module}/input.csv"))
  baseobj     = { for app in local.baseobj_csv : app.base_name => app }
}

resource "volterra_healthcheck" "origin-heath-check" {
  for_each    = local.baseobj
  name        = format("%s-health-check", each.value.base_name)
  namespace   = var.namespace
  dynamic "http_health_check" {
    for_each = each.value.health_check == "http" ? [1] : []
    content {
      use_origin_server_name = true
      path                   = "/"
    }
  }
  dynamic "tcp_health_check" {
    for_each = each.value.health_check == "tcp" ? [1] : []
    content {
    }
  }
  healthy_threshold   = 3
  interval            = 15
  timeout             = 3
  unhealthy_threshold = 1
}


resource "volterra_origin_pool" "f5-origin" {
  for_each               = local.baseobj
  name                   = format("%s-f5-origin", each.value.base_name)
  namespace              = var.namespace
  description            = format("Origin pool pointing to our origin!")
  loadbalancer_algorithm = "LB_OVERRIDE"
  endpoint_selection     = "LOCAL_PREFERRED"

  dynamic "origin_servers" {
    for_each = split(",", each.value.origin_server)
    content {
      dynamic "public_ip" {
        for_each = length(regexall("^([0-9]{1,3}\\.){3}[0-9]{1,3}(\\/([0-9]|[1-2][0-9]|3[0-2]))?$", origin_servers.value)) > 0 ? [1] : []
        content {
          ip = origin_servers.value
        }
      }
    }
  }
  port   = each.value.origin_server_port
  no_tls = each.value.origin_server_no_tls

  healthcheck {
    name = volterra_healthcheck.origin-heath-check[each.key].name
  }
}
