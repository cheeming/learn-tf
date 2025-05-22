provider "aws" {
  region  = "ap-southeast-1"
}

provider "aws" {
  alias   = "us-east-1"
  region  = "us-east-1"
}

resource "aws_acm_certificate" "www_cheeming_com_cert" {
  domain_name       = "www.cheeming.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  provider = aws.us-east-1
}

import {
  to = aws_s3_bucket.www_cheeming_com
  id = "www.cheeming.com"
}

resource "aws_s3_bucket" "www_cheeming_com" {
  bucket = "www.cheeming.com"
}

resource "aws_s3_bucket_acl" "www_cheeming_com_acl" {
  bucket = aws_s3_bucket.www_cheeming_com.id
  acl    = "private"
}

locals {
  s3_origin_id = "www_cheeming_com_s3_origin_id_202501"
}

resource "aws_cloudfront_origin_access_control" "www_cheeming_com_cf_oac" {
  name                              = "www_cheeming_com_cf_oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "www_cheeming_com_cf" {
  origin {
    domain_name              = aws_s3_bucket.www_cheeming_com.bucket_regional_domain_name
    // FIXME: due to s3 website hosting, this is not really needed
    origin_access_control_id = aws_cloudfront_origin_access_control.www_cheeming_com_cf_oac.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "To host www.cheeming.com"
  default_root_object = "index.html"

  aliases = ["www.cheeming.com"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type  = "none"
      locations         = []
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.www_cheeming_com_cert.arn
    ssl_support_method  = "sni-only"
  }
}

