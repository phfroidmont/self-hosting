Terraform Scaleaway
===================

```
export SCALEWAY_TOKEN=<your-access-key>  
export SCALEWAY_ORGANIZATION=<your-organization-key>  
# terraform init
# terraform plan
# terraform apply
# terraform show
data.scaleway_image.ubuntu:
  id = 
  architecture = x86_64
  creation_date = 2017-01-05T10:01:28.406069+00:00
  name = Ubuntu Xenial (16.04 latest)
  organization = 
  public = true
scaleway_server.server1:
  id = 
  enable_ipv6 = false
  image = 
  name = server1
  private_ip = 
  public_ip = 
  state = stopped
  state_detail = 
  tags.# = 0
  type = VC1S
  volume.# = 1
  volume.0.size_in_gb = 50
  volume.0.type = l_ssd
  volume.0.volume_id = 
```

