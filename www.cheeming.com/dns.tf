locals {
  ss_ip_records = {
    tokyo = var.ss_tokyo_ipaddress
    sg    = var.ss_sg_ipaddress
    kr    = var.ss_kr_ipaddress
    hk    = var.ss_hk_ipaddress
    us    = var.ss_us_ipaddress
    us2   = var.ss_us2_ipaddress
  }
}

resource "aws_route53_zone" "tmpsc_net" {
  name = "tmpsc.net"
}

// https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-cloudfront-distribution.html
resource "aws_route53_record" "alias_cf" {
  zone_id = aws_route53_zone.tmpsc_net.zone_id
  name    = "www.tmpsc.net"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.www_tmpsc_net_cf.domain_name
    zone_id                = aws_cloudfront_distribution.www_tmpsc_net_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cname_validation" {
  for_each = {
    for dvo in aws_acm_certificate.www_tmpsc_net_cert.domain_validation_options :
    dvo.domain_name => {
      type   = dvo.resource_record_type
      name   = dvo.resource_record_name
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
    name                   = aws_cloudfront_distribution.tmpsc_net_cf.domain_name
    zone_id                = aws_cloudfront_distribution.tmpsc_net_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cname_validation_tmpsc_net_root" {
  for_each = {
    for dvo in aws_acm_certificate.tmpsc_net_cert.domain_validation_options :
    dvo.domain_name => {
      type   = dvo.resource_record_type
      name   = dvo.resource_record_name
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

resource "aws_route53_record" "tmpsc_ss_tokyo" {
  count = local.ss_ip_records.tokyo == null ? 0 : 1

  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "A"
  name    = "tokyo.ss.tmpsc.net"
  records = [local.ss_ip_records.tokyo]
  ttl     = 60
}

resource "aws_route53_record" "tmpsc_ss_sg" {
  count = local.ss_ip_records.sg == null ? 0 : 1

  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "A"
  name    = "sg.ss.tmpsc.net"
  records = [local.ss_ip_records.sg]
  ttl     = 60
}

resource "aws_route53_record" "tmpsc_ss_kr" {
  count = local.ss_ip_records.kr == null ? 0 : 1

  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "A"
  name    = "kr.ss.tmpsc.net"
  records = [local.ss_ip_records.kr]
  ttl     = 60
}

resource "aws_route53_record" "tmpsc_ss_hk" {
  count = local.ss_ip_records.hk == null ? 0 : 1

  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "A"
  name    = "hk.ss.tmpsc.net"
  records = [local.ss_ip_records.hk]
  ttl     = 60
}

resource "aws_route53_record" "tmpsc_ss_us" {
  count = local.ss_ip_records.us == null ? 0 : 1

  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "A"
  name    = "us.ss.tmpsc.net"
  records = [local.ss_ip_records.us]
  ttl     = 60
}

resource "aws_route53_record" "tmpsc_ss_us2" {
  count = local.ss_ip_records.us2 == null ? 0 : 1

  zone_id = aws_route53_zone.tmpsc_net.zone_id
  type    = "A"
  name    = "us2.ss.tmpsc.net"
  records = [local.ss_ip_records.us2]
  ttl     = 60
}
