aws_region     = "eu-central-1"
project_name   = "scaa-final"
environment    = "dev"
owner          = "Nikoloz Chkhartishvili"
repository_url = "https://github.com/nikachkharti/SCAA-FinalProject.git"

instance_type    = "t3.micro"
root_volume_size = 20

container_port = 8080
host_port      = 80

allowed_http_cidr  = "0.0.0.0/0"
log_retention_days = 7

cpu_alarm_threshold = 80