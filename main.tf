terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.24"
    }
  }

  backend "s3" {
    region         = "us-east-1"
    bucket         = "x-mer-vg-terraform"
    key            = "terraform.tfstate"
    dynamodb_table = "x-mer-vg-terraform"
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  s3_origin_id = "S3-x-mer-vg"
}

resource "aws_route53_zone" "mer-vg" {
  name = "mer.vg"
}

resource "aws_s3_bucket" "x-mer-vg" {
  bucket = "x-mer-vg"
}

resource "aws_s3_bucket_acl" "x-mer-vg" {
  bucket = aws_s3_bucket.x-mer-vg.id
  acl    = "public-read"
}

resource "aws_s3_bucket_policy" "x-mer-vg" {
  bucket = aws_s3_bucket.x-mer-vg.id
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
      {
          "Sid": "PublicReadGetObject",
          "Effect": "Allow",
          "Principal": "*",
          "Action": [
             "s3:GetObject"
          ],
          "Resource": [
             "arn:aws:s3:::${aws_s3_bucket.x-mer-vg.id}/*"
          ]
      }
    ]
}
POLICY
}

resource "aws_s3_bucket" "x-mer-vg-logs" {
  bucket = "x-mer-vg-logs"
}

resource "aws_s3_bucket_acl" "x-mer-vg-logs" {
  bucket = aws_s3_bucket.x-mer-vg-logs.id
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_public_access_block" "x-mer-vg-logs" {
  bucket = aws_s3_bucket.x-mer-vg-logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "x-mer-vg" {
  bucket = aws_s3_bucket.x-mer-vg.id

  target_bucket = aws_s3_bucket.x-mer-vg-logs.id
  target_prefix = "log/"
}

resource "aws_cloudfront_distribution" "x-mer-vg" {
  origin {
    domain_name = aws_s3_bucket.x-mer-vg.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "x.mer.vg"
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.x-mer-vg-logs.bucket_domain_name
  }

  aliases = ["x.mer.vg"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.x-mer-vg-cert.arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_route53_record" "x-mer-vg" {
  zone_id = aws_route53_zone.mer-vg.id
  name    = "x.mer.vg"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_cloudfront_distribution.x-mer-vg.domain_name]
}

resource "aws_acm_certificate" "x-mer-vg-cert" {
  domain_name       = "x.mer.vg"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "x-mer-vg-cert" {
  for_each = {
    for dvo in aws_acm_certificate.x-mer-vg-cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.mer-vg.zone_id
}

resource "aws_acm_certificate_validation" "x-mer-vg-cert" {
  certificate_arn         = aws_acm_certificate.x-mer-vg-cert.arn
  validation_record_fqdns = [for record in aws_route53_record.x-mer-vg-cert : record.fqdn]
}
