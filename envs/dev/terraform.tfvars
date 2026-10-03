environment = "dev"
owner       = "platform-team"

# Five instances, one input variable. Every instance has a different instance type,
# root volume type, root volume size and key pair. The key pairs are expected to
# exist already; add `public_key = "ssh-ed25519 ..."` to an entry to have the
# module create it instead.
instances = {
  "web-01" = {
    instance_type = "t3.micro"
    key_name      = "web-01-key"
    root_volume   = { type = "gp3", size = 20, iops = 3000, throughput = 125 }
  }

  "app-01" = {
    instance_type = "t3.small"
    key_name      = "app-01-key"
    root_volume   = { type = "gp2", size = 30 }
  }

  # Stateful primary database: io2 for durable, consistent IOPS, and protected
  # from destruction (see NOTES.md, Task 1).
  "db-primary" = {
    instance_type   = "m5.large"
    key_name        = "db-primary-key"
    prevent_destroy = true
    root_volume     = { type = "io2", size = 100, iops = 5000 }
  }

  "cache-01" = {
    instance_type = "r5.large"
    key_name      = "cache-01-key"
    root_volume   = { type = "io1", size = 50, iops = 2500 }
  }

  "batch-01" = {
    instance_type = "c5.large"
    key_name      = "batch-01-key"
    root_volume   = { type = "standard", size = 40 }
  }
}
