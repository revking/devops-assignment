module "ec2_fleet" {
  source = "../../modules/ec2-fleet"

  environment = var.environment
  owner       = var.owner
  instances   = var.instances

  tags = {
    Project = "devops-assignment"
  }
}
