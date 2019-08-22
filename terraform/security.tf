# resource "scaleway_security_group" "k8s-sg" {
#   name                    = "Kubernetes"
#   description             = "Kubernetes cluster nodes security group"
#   enable_default_security = true
#   stateful                = true
#   inbound_default_policy  = "drop"
#   outbound_default_policy = "accept"
# }


# resource "scaleway_security_group_rule" "k8s-sg-rule-ssh" {
#   security_group = "${scaleway_security_group.k8s-sg.id}"

#   action    = "accept"
#   direction = "inbound"
#   ip_range  = "0.0.0.0/0"
#   protocol  = "TCP"
#   port      = 22
# }

# resource "scaleway_security_group_rule" "k8s-sg-rule-http" {
#   security_group = "${scaleway_security_group.k8s-sg.id}"

#   action    = "accept"
#   direction = "inbound"
#   ip_range  = "0.0.0.0/0"
#   protocol  = "TCP"
#   port      = 80
# }

# resource "scaleway_security_group_rule" "k8s-sg-rule-https" {
#   security_group = "${scaleway_security_group.k8s-sg.id}"

#   action    = "accept"
#   direction = "inbound"
#   ip_range  = "0.0.0.0/0"
#   protocol  = "TCP"
#   port      = 443
# }
