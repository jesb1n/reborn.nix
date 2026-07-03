terraform {
  backend "s3" {
    bucket                      = "tofu-backend"
    key                         = "beijns/terraform.tfstate"
    region                      = "garage"
    endpoint                    = "http://100.69.231.117:31900"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true
  }
}
