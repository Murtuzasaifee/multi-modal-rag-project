# Get default VPC if not provided
data "aws_vpc" "default" {
  count = var.vpc_id == null ? 1 : 0

  default = true
}

# Get default subnets if not provided
data "aws_subnets" "default" {
  count = length(coalesce(var.subnet_ids, [])) == 0 ? 1 : 0

  filter {
    name   = "defaultForAz"
    values = ["true"]
  }
}
