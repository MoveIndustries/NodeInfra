# IAM role for cert-manager to access Route53 for DNS-01 challenges

locals {
  oidc_issuer = replace(var.cluster_oidc_issuer_url, "https://", "")
}

# IAM policy for Route53 DNS-01 challenge
data "aws_iam_policy_document" "cert_manager_route53" {
  statement {
    effect = "Allow"
    actions = [
      "route53:GetChange"
    ]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
    resources = ["arn:aws:route53:::hostedzone/${var.route53_zone_id}"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZonesByName"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cert_manager_route53" {
  name        = "${var.cluster_name}-cert-manager-route53"
  description = "Policy for cert-manager to manage Route53 DNS records for DNS-01 challenge"
  policy      = data.aws_iam_policy_document.cert_manager_route53.json

  tags = var.tags
}

# Trust policy for IRSA
data "aws_iam_policy_document" "cert_manager_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.certmanager_namespace}:cert-manager"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  name               = "${var.cluster_name}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cert_manager_route53" {
  role       = aws_iam_role.cert_manager.name
  policy_arn = aws_iam_policy.cert_manager_route53.arn
}
