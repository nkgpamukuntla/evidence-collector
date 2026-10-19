# WIRE-UP: the only file that references resources already in network.tf / iam.tf / s3.tf.
# The names below are GUESSES. Open those files and point each local at the real
# resource before running tools/terraform.sh check.
locals {
  name_prefix = "ec-${var.environment}"

  vpc_id               = aws_vpc.main.id                  # TODO: network.tf
  evaluator_subnet_ids = aws_subnet.evaluator[*].id       # TODO: network.tf
  evaluator_sg_id      = aws_security_group.evaluator.id  # TODO: network.tf
  s3_gateway_endpoint  = aws_vpc_endpoint.s3.id           # TODO: network.tf
  worker_role_arn      = aws_iam_role.worker.arn          # TODO: iam.tf (trust must allow ecs-tasks.amazonaws.com)
  evaluator_role_arn   = aws_iam_role.evaluator.arn       # TODO: iam.tf (trust must allow ecs-tasks.amazonaws.com)
  raw_bucket_name      = aws_s3_bucket.raw.bucket         # TODO: s3.tf

  # New subnets carve /20s (on a /16) from netnums the evaluator does NOT use.
  # TODO: confirm against the cidrsubnet() calls in network.tf.
  subnet_newbits  = 4
  public_netnums  = [8, 9]
  worker_netnums  = [10, 11]
  db_netnums      = [12, 13]

  image_file = "${path.module}/envs/${var.environment}.image"
  image_tag  = fileexists(local.image_file) ? trimspace(file(local.image_file)) : "unset"
}
