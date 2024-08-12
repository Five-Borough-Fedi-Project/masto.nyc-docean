### I'm going to note that this will, for now, only represent firewalls that are auto-created by things like the k8s cluster
### I'll need to explore the cost/benefit and complexity of separating out the cloudflared/nginx tier of the infra,
### but for right now it will all be on the same private subnet.

resource "digitalocean_firewall" "k8s_public" {
  # the names here just get overwritten so don't bother >_>
  name = "k8s-public-access-0778f05e-49d4-45d3-b777-c83fd31b9320"
  tags = ["k8s:0778f05e-49d4-45d3-b777-c83fd31b9320"]

  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "digitalocean_firewall" "k8s_private" {
  # the names here just get overwritten so don't bother >_>
  name = "k8s-0778f05e-49d4-45d3-b777-c83fd31b9320-worker"
  tags = ["k8s:0778f05e-49d4-45d3-b777-c83fd31b9320"]

  inbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    source_addresses = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  inbound_rule {
    protocol              = "udp"
    port_range            = "all"
    source_addresses = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  inbound_rule {
    protocol              = "icmp"
    source_addresses = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0"]
  }
}