# Security Group for EKS Control Plane
resource "aws_security_group" "control_plane" {
  name_prefix = "${var.validator_name}-eks-control-plane-"
  description = "Security group for EKS control plane"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.validator_name}-eks-control-plane-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Allow HTTPS from nodes to control plane
resource "aws_security_group_rule" "control_plane_ingress_nodes" {
  description              = "Allow nodes to communicate with control plane"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.control_plane.id
  source_security_group_id = aws_security_group.node.id
}

# Allow all egress from control plane
resource "aws_security_group_rule" "control_plane_egress" {
  description       = "Allow control plane egress"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.control_plane.id
}

# Security Group for EKS Nodes
resource "aws_security_group" "node" {
  name_prefix = "${var.validator_name}-eks-node-"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name                                                  = "${var.validator_name}-eks-node-sg"
      "kubernetes.io/cluster/${var.validator_name}-cluster" = "owned"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Allow nodes to communicate with each other
resource "aws_security_group_rule" "node_ingress_self" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.node.id
}

# Allow nodes to receive communication from control plane
resource "aws_security_group_rule" "node_ingress_control_plane" {
  description              = "Allow control plane to communicate with nodes"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.control_plane.id
}

# Allow all egress from nodes
resource "aws_security_group_rule" "node_egress" {
  description       = "Allow node egress"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
}

# Security Group for Load Balancers
resource "aws_security_group" "load_balancer" {
  name_prefix = "${var.validator_name}-lb-"
  description = "Security group for load balancers"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    local.common_tags,
    {
      Name = "${var.validator_name}-lb-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Allow HTTP from anywhere
resource "aws_security_group_rule" "lb_ingress_http" {
  description       = "Allow HTTP traffic"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.load_balancer.id
}

# Allow HTTPS from anywhere
resource "aws_security_group_rule" "lb_ingress_https" {
  description       = "Allow HTTPS traffic"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.load_balancer.id
}

# Allow Aptos P2P port (for fullnode network)
resource "aws_security_group_rule" "lb_ingress_p2p" {
  description       = "Allow Aptos P2P traffic"
  type              = "ingress"
  from_port         = 6182
  to_port           = 6182
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.load_balancer.id
}

# Allow all egress from load balancer
resource "aws_security_group_rule" "lb_egress" {
  description       = "Allow load balancer egress"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.load_balancer.id
}
