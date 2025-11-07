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

// dns records for email
resource "aws_route53_record" "tmpsc_mx" {
  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "MX"
  name    = "tmpsc.net"
  records = ["10 mx01.mail.icloud.com.", "10 mx02.mail.icloud.com."]
  ttl     = 60
}

resource "aws_route53_record" "tmpsc_txt" {
  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "TXT"
  name    = "tmpsc.net"
  records = ["apple-domain=rqjluaoy8cY0kNmM", "v=spf1 include:icloud.com ~all"]
  ttl     = 60
}

resource "aws_route53_record" "tmpsc_dkim" {
  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "CNAME"
  name    = "sig1._domainkey"
  records = ["sig1.dkim.tmpsc.net.at.icloudmailadmin.com."]
  ttl     = 60
}

resource "aws_route53_record" "tmpsc_ss_jp" {
  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "A"
  name    = "jp.ss.tmpsc.net"
  records = [var.ss_jp_ipaddress]
  ttl     = 60
}
