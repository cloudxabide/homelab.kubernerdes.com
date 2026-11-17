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

# ---------------------------------------------------------------------------
# rancher-01 instance role: lets cert-manager in the AWS Rancher cluster solve
# Let's Encrypt DNS-01 for rancher-aws.<env>.<domain> by itself (ambient
# credentials via IMDSv2; hop limit 2 lets pods reach it). Scoped to TXT
# records for that one _acme-challenge name in the one zone, so it cannot
# touch the *.<env> wildcard nuc-00 manages or any other record.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "rancher_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rancher" {
  name               = "${local.name}-rancher-01"
  assume_role_policy = data.aws_iam_policy_document.rancher_assume.json
}

resource "aws_iam_instance_profile" "rancher" {
  name = "${local.name}-rancher-01"
  role = aws_iam_role.rancher.name
}

data "aws_iam_policy_document" "rancher_cert_dns01" {
  count = var.rancher_cert_dns01 ? 1 : 0

  statement {
    sid       = "GetChange"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid       = "ListZones"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadZone"
    actions   = ["route53:ListResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.main[0].zone_id}"]
  }

  statement {
    sid       = "ChallengeRecordOnly"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.main[0].zone_id}"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["_acme-challenge.${local.rancher_hostname}"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }
  }
}

resource "aws_iam_role_policy" "rancher_cert_dns01" {
  count  = var.rancher_cert_dns01 ? 1 : 0
  name   = "cert-manager-dns01-rancher-aws"
  role   = aws_iam_role.rancher.id
  policy = data.aws_iam_policy_document.rancher_cert_dns01[0].json
}
