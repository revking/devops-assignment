variable "environment" {
  description = "Environment name applied as the mandatory 'Environment' tag (e.g. dev, staging, prod)."
  type        = string

  validation {
    condition     = length(trimspace(var.environment)) > 0
    error_message = "environment must not be empty."
  }
}

variable "owner" {
  description = "Owning team or person applied as the mandatory 'Owner' tag."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "default_ami_id" {
  description = "AMI used for instances that do not set ami_id. When null, the latest Amazon Linux 2023 AMI is resolved from SSM."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to every instance and root volume. Name/Environment/Owner always win over these."
  type        = map(string)
  default     = {}
}

variable "instances" {
  description = <<-EOT
    Map of instance name => instance spec. The map key becomes the Name tag and the
    stable for_each address, so renaming a key means replacing that instance.

    root_volume.type must be a type that EC2 supports for boot volumes:
    gp2, gp3, io1, io2 or standard (st1/sc1 cannot be root volumes).

    If public_key is set, the module creates an aws_key_pair called key_name from it;
    otherwise key_name must refer to a key pair that already exists in the region.

    prevent_destroy = true puts the instance behind a lifecycle { prevent_destroy = true }
    block and also turns on EC2 termination protection.
  EOT

  type = map(object({
    instance_type          = string
    key_name               = string
    public_key             = optional(string)
    ami_id                 = optional(string)
    subnet_id              = optional(string)
    vpc_security_group_ids = optional(list(string), [])
    prevent_destroy        = optional(bool, false)
    tags                   = optional(map(string), {})

    root_volume = object({
      type       = string
      size       = number
      iops       = optional(number)
      throughput = optional(number)
    })
  }))

  validation {
    condition     = length(var.instances) > 0
    error_message = "At least one instance must be defined."
  }

  validation {
    condition = alltrue([
      for i in values(var.instances) : contains(["gp2", "gp3", "io1", "io2", "standard"], i.root_volume.type)
    ])
    error_message = "root_volume.type must be one of gp2, gp3, io1, io2, standard (st1/sc1 are not bootable)."
  }

  validation {
    condition = alltrue([
      for i in values(var.instances) : i.root_volume.size >= 8 && i.root_volume.size <= 16384
    ])
    error_message = "root_volume.size must be between 8 and 16384 GiB."
  }

  validation {
    condition = alltrue([
      for i in values(var.instances) :
      contains(["io1", "io2"], i.root_volume.type) ? i.root_volume.iops != null : true
    ])
    error_message = "root_volume.iops is required for io1/io2 volumes."
  }

  validation {
    condition = alltrue([
      for i in values(var.instances) :
      i.root_volume.iops == null || contains(["io1", "io2", "gp3"], i.root_volume.type)
    ])
    error_message = "root_volume.iops can only be set for io1, io2 or gp3 volumes."
  }

  validation {
    # io1 allows up to 50 IOPS per GiB, io2 up to 1000 IOPS per GiB.
    condition = alltrue([
      for i in values(var.instances) :
      i.root_volume.type == "io1" ? coalesce(i.root_volume.iops, 0) >= 100 && coalesce(i.root_volume.iops, 0) <= i.root_volume.size * 50 :
      i.root_volume.type == "io2" ? coalesce(i.root_volume.iops, 0) >= 100 && coalesce(i.root_volume.iops, 0) <= i.root_volume.size * 1000 :
      true
    ])
    error_message = "Provisioned IOPS out of range: io1 allows 100..50*size, io2 allows 100..1000*size."
  }

  validation {
    condition = alltrue([
      for i in values(var.instances) : i.root_volume.throughput == null || i.root_volume.type == "gp3"
    ])
    error_message = "root_volume.throughput can only be set for gp3 volumes."
  }

  validation {
    condition     = length(distinct([for i in values(var.instances) : i.key_name])) == length(var.instances)
    error_message = "Every instance must use its own key pair (key_name values must be unique)."
  }
}
