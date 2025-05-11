resource "aws_acm_certificate" "www_tmpsc_net_cert" {
  domain_name       = "www.tmpsc.net"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  provider = aws.us-east-1
}

resource "aws_cloudfront_origin_access_control" "www_tmpsc_net_cf_oac" {
  name                              = "www_tmpsc_net_cf_oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "www_tmpsc_net_cf" {
  origin {
    domain_name              = aws_s3_bucket.www_cheeming_com.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.www_tmpsc_net_cf_oac.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "To host www.tmpsc.net"
  default_root_object = "index.html"

  aliases = ["www.tmpsc.net"]

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
    acm_certificate_arn = aws_acm_certificate.www_tmpsc_net_cert.arn
    ssl_support_method  = "sni-only"
  }

  depends_on = [
    // cname validation needs to be complete for the ACM certificate,
    // before CF can be created successfully
    aws_route53_record.cname_validation
  ]
}
