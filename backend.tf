terraform {
  backend "s3" {
    bucket                      = "my-tofu-backend"
    region                      = "us-ashburn-1"
    key                         = "infra/tf.tfstate"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    use_path_style              = true
    skip_s3_checksum            = true
    skip_metadata_api_check     = true
    endpoints = {
      s3 = "https://<your-namespace>.compat.objectstorage.<your-region>.oraclecloud.com"
    }
  }
}
