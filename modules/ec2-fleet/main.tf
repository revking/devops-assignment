locals {
  # Terraform does not allow lifecycle arguments to be driven by variables, so the
  # single var.instances map is split into two for_each sets. Instances flagged with
  # prevent_destroy go to aws_instance.protected, which has the lifecycle block.
  protected_instances = { for name, spec in var.instances : name => spec if spec.prevent_destroy }
  standard_instances  = { for name, spec in var.instances : name => spec if !spec.prevent_destroy }

  needs_default_ami = var.default_ami_id == null && anytrue([for spec in values(var.instances) : spec.ami_id == null])
  default_ami_id    = var.default_ami_id != null ? var.default_ami_id : try(nonsensitive(data.aws_ssm_parameter.al2023[0].value), null)

  # Mandatory tags are merged last so callers cannot override them by accident.
  instance_tags = {
    for name, spec in var.instances : name => merge(var.tags, spec.tags, {
      Name        = name
      Environment = var.environment
      Owner       = var.owner
    })
  }
}

data "aws_ssm_parameter" "al2023" {
  count = local.needs_default_ami ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_key_pair" "this" {
  for_each = { for name, spec in var.instances : name => spec if spec.public_key != null }

  key_name   = each.value.key_name
  public_key = each.value.public_key
  tags       = local.instance_tags[each.key]
}

resource "aws_instance" "standard" {
  for_each = local.standard_instances

  ami                     = coalesce(each.value.ami_id, local.default_ami_id)
  instance_type           = each.value.instance_type
  key_name                = try(aws_key_pair.this[each.key].key_name, each.value.key_name)
  subnet_id               = each.value.subnet_id
  vpc_security_group_ids  = length(each.value.vpc_security_group_ids) > 0 ? each.value.vpc_security_group_ids : null
  disable_api_termination = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type           = each.value.root_volume.type
    volume_size           = each.value.root_volume.size
    iops                  = each.value.root_volume.iops
    throughput            = each.value.root_volume.throughput
    encrypted             = true
    delete_on_termination = true
    tags                  = local.instance_tags[each.key]
  }

  tags = local.instance_tags[each.key]

  lifecycle {
    # A new AMI published to SSM must not silently replace running instances.
    ignore_changes = [ami]
  }
}

resource "aws_instance" "protected" {
  for_each = local.protected_instances

  ami                     = coalesce(each.value.ami_id, local.default_ami_id)
  instance_type           = each.value.instance_type
  key_name                = try(aws_key_pair.this[each.key].key_name, each.value.key_name)
  subnet_id               = each.value.subnet_id
  vpc_security_group_ids  = length(each.value.vpc_security_group_ids) > 0 ? each.value.vpc_security_group_ids : null
  disable_api_termination = true # EC2 termination protection (console/API/CLI)

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = each.value.root_volume.type
    volume_size           = each.value.root_volume.size
    iops                  = each.value.root_volume.iops
    throughput            = each.value.root_volume.throughput
    encrypted             = true
    delete_on_termination = true
    tags                  = local.instance_tags[each.key]
  }

  tags = local.instance_tags[each.key]

  lifecycle {
    # Terraform refuses any plan that would destroy (or replace) this instance.
    prevent_destroy = true
    ignore_changes  = [ami]
  }
}
