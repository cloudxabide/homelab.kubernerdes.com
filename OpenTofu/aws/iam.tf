# IAM user for Rancher's Amazon EC2 node driver (cloud downstream clusters).
# No access key is created here — it would land in state. Create one by hand
# and paste it into a Rancher cloud credential:
#   aws iam create-access-key --user-name <rancher_node_driver_user output>
#
# Scoped to what the node driver does: launch/terminate/tag instances, manage
# key pairs and its security groups, describe everything it picks from.

data "aws_iam_policy_document" "node_driver" {
  statement {
    sid    = "Describe"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Instances"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:RebootInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:CreateTags",
      "ec2:CreateKeyPair",
      "ec2:ImportKeyPair",
      "ec2:DeleteKeyPair",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid    = "SecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_user" "node_driver" {
  name = "${local.name}-rancher-node-driver"
}

resource "aws_iam_user_policy" "node_driver" {
  name   = "rancher-ec2-node-driver"
  user   = aws_iam_user.node_driver.name
  policy = data.aws_iam_policy_document.node_driver.json
}
