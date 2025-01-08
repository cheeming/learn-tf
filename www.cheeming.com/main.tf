
provider "aws" {
  region  = "ap-southeast-1"
}

import {
  to = aws_s3_bucket.www_cheeming_com
  id = "www.cheeming.com"
}

resource "aws_s3_bucket" "www_cheeming_com" {
  bucket = "www.cheeming.com"
}
