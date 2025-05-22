resource "aws_route53_zone" "tmpsc_net" {
  name = "tmpsc.net"
}

// https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-cloudfront-distribution.html
resource "aws_route53_record" "alias_cf" {
  zone_id = aws_route53_zone.tmpsc_net.zone_id
  name    = "www.tmpsc.net"
  type    = "A"
  alias {
    name = aws_cloudfront_distribution.www_tmpsc_net_cf.domain_name
    zone_id = aws_cloudfront_distribution.www_tmpsc_net_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cname_validation" {
  for_each = {
    for dvo in aws_acm_certificate.www_tmpsc_net_cert.domain_validation_options:
    dvo.domain_name => {
      type = dvo.resource_record_type
      name = dvo.resource_record_name
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = each.value.type
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
}

// create A record that points to the tmpsc.net cloudfront
resource "aws_route53_record" "alias_cf_root" {
  zone_id = aws_route53_zone.tmpsc_net.zone_id
  name    = "tmpsc.net"
  type    = "A"
  alias {
    name = aws_cloudfront_distribution.tmpsc_net_cf.domain_name
    zone_id = aws_cloudfront_distribution.tmpsc_net_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cname_validation_tmpsc_net_root" {
  for_each = {
    for dvo in aws_acm_certificate.tmpsc_net_cert.domain_validation_options:
    dvo.domain_name => {
      type = dvo.resource_record_type
      name = dvo.resource_record_name
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = each.value.type
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
}
