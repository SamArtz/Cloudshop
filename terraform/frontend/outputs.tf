output "frontend_bucket_name" {
  description = "Nombre del bucket S3 del frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_bucket_arn" {
  description = "ARN del bucket S3 del frontend"
  value       = aws_s3_bucket.frontend.arn
}

output "cloudfront_distribution_id" {
  description = "ID de la distribución CloudFront"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_domain_name" {
  description = "Dominio público del frontend (HTTPS)"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "cloudfront_url" {
  description = "URL completa del frontend"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "waf_web_acl_arn" {
  description = "ARN del Web ACL de WAF asociado a CloudFront"
  value       = aws_wafv2_web_acl.frontend.arn
}

output "waf_web_acl_name" {
  description = "Nombre del Web ACL"
  value       = aws_wafv2_web_acl.frontend.name
}
