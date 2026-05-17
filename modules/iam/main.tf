
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pcs_compute_role" {
  name_prefix        = "pcs-compute-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  path = "/aws-pcs/"
}

data "aws_iam_policy_document" "pcs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "pcs:RegisterComputeNodeGroupInstance",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "pcs_policy" {
  name        = "pcs_policy"
  role        = aws_iam_role.pcs_compute_role.name
  policy      = data.aws_iam_policy_document.pcs_policy.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.pcs_compute_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.pcs_compute_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "pcs_compute_profile" {
  role = aws_iam_role.pcs_compute_role.name
}

resource "aws_key_pair" "pcs" {
  key_name   = "pcs-key"
  public_key = var.ssh_key
}
